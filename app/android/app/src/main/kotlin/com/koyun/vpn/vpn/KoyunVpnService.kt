package com.koyun.vpn.vpn

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.ConnectivityManager
import android.net.IpPrefix
import android.net.NetworkCapabilities
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import android.os.Process
import android.system.OsConstants
import android.util.Log
import androidx.core.app.NotificationCompat
import com.koyun.vpn.MainActivity
import com.koyun.vpn.R
import io.nekohasekai.libbox.BridgeOptions
import io.nekohasekai.libbox.BridgeSession
import io.nekohasekai.libbox.CommandServer
import io.nekohasekai.libbox.CommandServerHandler
import io.nekohasekai.libbox.ConnectionOwner
import io.nekohasekai.libbox.InterfaceUpdateListener
import io.nekohasekai.libbox.Libbox
import io.nekohasekai.libbox.LocalDNSTransport
import io.nekohasekai.libbox.NeighborUpdateListener
import io.nekohasekai.libbox.NetworkInterfaceIterator
import io.nekohasekai.libbox.OverrideOptions
import io.nekohasekai.libbox.PlatformInterface
import io.nekohasekai.libbox.PlatformUser
import io.nekohasekai.libbox.RoutePrefix
import io.nekohasekai.libbox.SetupOptions
import io.nekohasekai.libbox.ShellSession
import io.nekohasekai.libbox.StringIterator
import io.nekohasekai.libbox.SystemProxyStatus
import io.nekohasekai.libbox.TunOptions
import io.nekohasekai.libbox.WIFIState
import java.io.File
import java.net.Inet6Address
import java.net.InetAddress
import java.net.InetSocketAddress
import java.util.concurrent.Executors
import io.nekohasekai.libbox.Notification as BoxNotification
import io.nekohasekai.libbox.NetworkInterface as BoxNetworkInterface

/**
 * Android VPN 服务：内嵌 sing-box（libbox），在前台服务中运行。
 * 系统收回 VPN 授权（被其它 VPN 抢占）时自动停止并通知界面。
 */
class KoyunVpnService : VpnService(), PlatformInterface, CommandServerHandler {

    companion object {
        const val TAG = "KoyunVpn"
        const val ACTION_START = "com.koyun.vpn.START"
        const val ACTION_STOP = "com.koyun.vpn.STOP"
        private const val CHANNEL = "vpn"
        private const val NOTIFY_ID = 1

        @Volatile private var libboxReady = false

        fun configFile(ctx: Context) = File(ctx.filesDir, "vpn-config.json")

        fun saveConfig(ctx: Context, config: String) {
            val tmp = File(ctx.filesDir, "vpn-config.json.tmp")
            tmp.writeText(config)
            tmp.renameTo(configFile(ctx))
        }

        fun stop(ctx: Context) {
            if (VpnState.status == "stopped") return
            ctx.startService(Intent(ctx, KoyunVpnService::class.java).setAction(ACTION_STOP))
        }

        @Synchronized
        fun setupLibbox(ctx: Context) {
            if (libboxReady) return
            val work = File(ctx.filesDir, "box").apply { mkdirs() }
            Libbox.setup(SetupOptions().apply {
                basePath = ctx.filesDir.path
                workingPath = work.path
                tempPath = ctx.cacheDir.path
                fixAndroidStack = Build.VERSION.SDK_INT >= 30
                logMaxLines = 2000L
                debug = false
                crashReportSource = "Koyun"
                // 内存保护：移动端防止被系统因内存过高杀掉
                oomKillerEnabled = true
            })
            libboxReady = true
        }
    }

    private val worker = Executors.newSingleThreadExecutor()
    private var commandServer: CommandServer? = null
    private var tunFd: ParcelFileDescriptor? = null
    private val monitor by lazy { NetworkMonitor(this) }
    private val cm by lazy { getSystemService(ConnectivityManager::class.java) }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                worker.execute { stopVpn() }
                return START_NOT_STICKY
            }
            else -> {
                // ACTION_START，或系统"始终开启 VPN"拉起（intent 为空）
                showNotification()
                VpnState.set("starting")
                worker.execute { startVpn() }
            }
        }
        return START_STICKY
    }

    private fun startVpn() {
        try {
            val config = configFile(this).takeIf { it.exists() }?.readText()
                ?: error("no config, open the app and connect once")
            setupLibbox(this)
            monitor.start()
            var server = commandServer
            if (server == null) {
                server = CommandServer(this, this)
                server.start()
                commandServer = server
            }
            // 已在运行时会热重载（换节点列表 / 改设置），不需要先停
            // App 自身不排除：连接后访问面板 / 刷新订阅也走代理，面板域名被墙时依然可用
            server.startOrReloadService(config, OverrideOptions().apply { autoRedirect = false })
            VpnState.set("running")
        } catch (e: Throwable) {
            Log.e(TAG, "start failed", e)
            cleanup()
            VpnState.set("stopped", e.message ?: e.toString())
            stopForegroundCompat()
            stopSelf()
        }
    }

    private fun stopVpn() {
        cleanup()
        VpnState.set("stopped")
        stopForegroundCompat()
        stopSelf()
    }

    private fun cleanup() {
        runCatching { tunFd?.close() }
        tunFd = null
        runCatching { commandServer?.closeService() }
        runCatching { commandServer?.close() }
        commandServer = null
        runCatching { monitor.stop() }
    }

    override fun onRevoke() {
        // 被其它 VPN 抢占或用户在系统设置里关闭
        worker.execute { stopVpn() }
    }

    override fun onDestroy() {
        if (VpnState.status != "stopped") {
            cleanup()
            VpnState.set("stopped")
        }
        super.onDestroy()
    }

    // ---------------- 通知 ----------------

    private fun showNotification() {
        val nm = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26) {
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL, "VPN", NotificationManager.IMPORTANCE_LOW).apply {
                    setShowBadge(false)
                },
            )
        }
        val open = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE,
        )
        val stop = PendingIntent.getService(
            this, 1, Intent(this, KoyunVpnService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_IMMUTABLE,
        )
        val zh = resources.configuration.locales[0].language == "zh"
        val n: Notification = NotificationCompat.Builder(this, CHANNEL)
            .setSmallIcon(R.drawable.ic_tile)
            .setContentTitle("Koyun")
            .setContentText(if (zh) "安全连接已开启" else "Secure connection is on")
            .setOngoing(true)
            .setShowWhen(false)
            .setOnlyAlertOnce(true)
            .setContentIntent(open)
            .addAction(0, if (zh) "断开" else "Disconnect", stop)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .build()
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(NOTIFY_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_SYSTEM_EXEMPTED)
        } else {
            startForeground(NOTIFY_ID, n)
        }
    }

    private fun stopForegroundCompat() {
        if (Build.VERSION.SDK_INT >= 24) stopForeground(STOP_FOREGROUND_REMOVE)
    }

    // ---------------- CommandServerHandler ----------------

    override fun serviceStop() {
        worker.execute { stopVpn() }
    }

    override fun serviceReload() {
        worker.execute { startVpn() }
    }

    override fun getSystemProxyStatus(): SystemProxyStatus = SystemProxyStatus()
    override fun setSystemProxyEnabled(isEnabled: Boolean) {}
    override fun triggerNativeCrash() {}
    override fun writeDebugMessage(message: String?) {
        Log.d(TAG, message ?: "")
    }
    override fun connectSSHAgent(): Int = -1

    // ---------------- PlatformInterface ----------------

    override fun localDNSTransport(): LocalDNSTransport? = null
    override fun usePlatformAutoDetectInterfaceControl(): Boolean = true

    /** 让内核自己的出站连接不走 VPN（防止回环） */
    override fun autoDetectInterfaceControl(fd: Int) {
        protect(fd)
    }

    override fun openTun(options: TunOptions): Int {
        if (prepare(this) != null) error("android: missing vpn permission")
        val b = Builder().setSession("Koyun").setMtu(options.mtu)
        if (Build.VERSION.SDK_INT >= 29) b.setMetered(false)

        options.inet4Address.forEach { b.addAddress(it.address(), it.prefix()) }
        options.inet6Address.forEach { b.addAddress(it.address(), it.prefix()) }

        if (options.autoRoute) {
            val dns = options.dnsServerAddress
            while (dns.hasNext()) b.addDnsServer(dns.next())

            if (Build.VERSION.SDK_INT >= 33) {
                var any4 = false
                options.inet4RouteAddress.forEach { any4 = true; b.addRoute(it.toIpPrefix()) }
                if (!any4 && options.inet4Address.hasNext()) b.addRoute("0.0.0.0", 0)
                var any6 = false
                options.inet6RouteAddress.forEach { any6 = true; b.addRoute(it.toIpPrefix()) }
                if (!any6 && options.inet6Address.hasNext()) b.addRoute("::", 0)
                options.inet4RouteExcludeAddress.forEach { b.excludeRoute(it.toIpPrefix()) }
                options.inet6RouteExcludeAddress.forEach { b.excludeRoute(it.toIpPrefix()) }
            } else {
                options.inet4RouteRange.forEach { b.addRoute(it.address(), it.prefix()) }
                options.inet6RouteRange.forEach { b.addRoute(it.address(), it.prefix()) }
            }

            val inc = options.includePackage
            while (inc.hasNext()) runCatching { b.addAllowedApplication(inc.next()) }
            val exc = options.excludePackage
            while (exc.hasNext()) runCatching { b.addDisallowedApplication(exc.next()) }
        }

        val pfd = b.establish() ?: error("android: the application is not prepared or is revoked")
        runCatching { tunFd?.close() }
        tunFd = pfd
        return pfd.fd
    }

    override fun findConnectionOwner(
        ipProtocol: Int, sourceAddress: String, sourcePort: Int,
        destinationAddress: String, destinationPort: Int,
    ): ConnectionOwner {
        if (Build.VERSION.SDK_INT < 29) error("android: connection owner unsupported")
        val uid = cm.getConnectionOwnerUid(
            ipProtocol,
            InetSocketAddress(sourceAddress, sourcePort),
            InetSocketAddress(destinationAddress, destinationPort),
        )
        if (uid == Process.INVALID_UID) error("android: connection owner not found")
        val owner = ConnectionOwner()
        owner.userId = uid
        val pkgs = packageManager.getPackagesForUid(uid)?.toList() ?: emptyList()
        owner.userName = pkgs.firstOrNull() ?: ""
        owner.setAndroidPackageNames(StringArray(pkgs.iterator()))
        return owner
    }

    override fun startDefaultInterfaceMonitor(listener: InterfaceUpdateListener) = monitor.setListener(listener)
    override fun closeDefaultInterfaceMonitor(listener: InterfaceUpdateListener) = monitor.setListener(null)

    override fun getInterfaces(): NetworkInterfaceIterator {
        val javaIfs = java.net.NetworkInterface.getNetworkInterfaces()?.toList() ?: emptyList()
        val list = mutableListOf<BoxNetworkInterface>()
        @Suppress("DEPRECATION")
        for (network in cm.allNetworks) {
            val lp = cm.getLinkProperties(network) ?: continue
            val caps = cm.getNetworkCapabilities(network) ?: continue
            val ji = javaIfs.find { it.name == lp.interfaceName } ?: continue
            val bi = BoxNetworkInterface()
            bi.name = lp.interfaceName
            bi.index = ji.index
            runCatching { bi.mtu = ji.mtu }
            bi.dnsServer = StringArray(lp.dnsServers.mapNotNull { it.hostAddress }.iterator())
            bi.gateway = StringArray(
                lp.routes.filter { it.destination.prefixLength == 0 }
                    .mapNotNull { it.gateway }.filterNot { it.isAnyLocalAddress }
                    .mapNotNull { it.hostAddress }.iterator(),
            )
            bi.type = when {
                caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> Libbox.InterfaceTypeWIFI
                caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> Libbox.InterfaceTypeCellular
                caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> Libbox.InterfaceTypeEthernet
                else -> Libbox.InterfaceTypeOther
            }
            bi.addresses = StringArray(ji.interfaceAddresses.map {
                val a = it.address
                if (a is Inet6Address) "${Inet6Address.getByAddress(a.address).hostAddress}/${it.networkPrefixLength}"
                else "${a.hostAddress}/${it.networkPrefixLength}"
            }.iterator())
            var f = 0
            if (caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)) f = OsConstants.IFF_UP or OsConstants.IFF_RUNNING
            if (ji.isLoopback) f = f or OsConstants.IFF_LOOPBACK
            if (ji.isPointToPoint) f = f or OsConstants.IFF_POINTOPOINT
            if (ji.supportsMulticast()) f = f or OsConstants.IFF_MULTICAST
            bi.flags = f
            bi.metered = !caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED)
            list.add(bi)
        }
        return object : NetworkInterfaceIterator {
            val it = list.iterator()
            override fun hasNext() = it.hasNext()
            override fun next(): BoxNetworkInterface = it.next()
        }
    }

    override fun underNetworkExtension(): Boolean = false
    override fun includeAllNetworks(): Boolean = false
    override fun readWIFIState(): WIFIState? = null
    override fun clearDNSCache() {}
    override fun sendNotification(notification: BoxNotification) {}
    override fun cancelNotification(identifier: String?, typeID: Int) {}
    override fun startNeighborMonitor(listener: NeighborUpdateListener?) {}
    override fun closeNeighborMonitor(listener: NeighborUpdateListener?) {}
    override fun registerMyInterface(name: String?) {}
    override fun usePlatformShell(): Boolean = false
    override fun checkPlatformShell() = error("not supported")
    override fun openShellSession(
        user: PlatformUser?, command: String?, environ: StringIterator?,
        term: String?, rows: Int, cols: Int,
    ): ShellSession = error("not supported")
    override fun lookupUser(username: String?): PlatformUser = error("not supported")
    override fun lookupSFTPServer(): String = error("not supported")
    override fun readSystemSSHHostKey(): String = error("not supported")
    override fun tailscaleHostname(): String = "${Build.MANUFACTURER} ${Build.MODEL}"
    override fun usePlatformBridge(): Boolean = false
    override fun createBridge(options: BridgeOptions?): BridgeSession = error("not supported")

    // ---------------- 工具 ----------------

    class StringArray(private val it: Iterator<String>) : StringIterator {
        override fun len(): Int = 0
        override fun hasNext(): Boolean = it.hasNext()
        override fun next(): String = it.next()
    }

    private inline fun io.nekohasekai.libbox.RoutePrefixIterator.forEach(f: (RoutePrefix) -> Unit) {
        while (hasNext()) f(next())
    }

    private fun RoutePrefix.toIpPrefix(): IpPrefix =
        if (Build.VERSION.SDK_INT >= 33) IpPrefix(InetAddress.getByName(address()), prefix())
        else error("unreachable")
}

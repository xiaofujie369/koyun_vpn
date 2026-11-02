package com.koyun.vpn.vpn

import android.annotation.TargetApi
import android.content.Context
import android.net.ConnectivityManager
import android.net.LinkProperties
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import io.nekohasekai.libbox.InterfaceUpdateListener
import java.net.NetworkInterface

/**
 * 监听"真实的"默认网络（排除 VPN 自身），Wi-Fi / 移动数据切换时通知内核，
 * 内核据此重新绑定出口，切网不断线。
 */
class NetworkMonitor(context: Context) {
    private val cm = context.getSystemService(ConnectivityManager::class.java)
    private val handler by lazy { Handler(HandlerThread("koyun-network").apply { start() }.looper) }
    private var listener: InterfaceUpdateListener? = null
    @Volatile var defaultNetwork: Network? = null
    private var registered = false

    private val request = NetworkRequest.Builder()
        .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
        .addCapability(NetworkCapabilities.NET_CAPABILITY_NOT_RESTRICTED)
        .addCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
        .build()

    private val callback = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) = update(network)
        override fun onCapabilitiesChanged(network: Network, caps: NetworkCapabilities) = update(network)
        override fun onLinkPropertiesChanged(network: Network, lp: LinkProperties) = update(network)
        override fun onLost(network: Network) {
            if (network == defaultNetwork) {
                defaultNetwork = null
                notifyListener(null)
            }
        }
    }

    fun start() {
        if (registered) return
        registered = true
        when {
            Build.VERSION.SDK_INT >= 31 -> registerBest()
            Build.VERSION.SDK_INT >= 28 -> cm.requestNetwork(request, callback, handler)
            else -> cm.registerDefaultNetworkCallback(callback, handler)
        }
    }

    @TargetApi(31)
    private fun registerBest() = cm.registerBestMatchingNetworkCallback(request, callback, handler)

    fun stop() {
        if (!registered) return
        registered = false
        runCatching { cm.unregisterNetworkCallback(callback) }
        listener = null
    }

    fun setListener(l: InterfaceUpdateListener?) {
        listener = l
        notifyListener(defaultNetwork)
    }

    private fun update(network: Network) {
        defaultNetwork = network
        notifyListener(network)
    }

    private fun notifyListener(network: Network?) {
        val l = listener ?: return
        if (network == null) {
            l.updateDefaultInterface("", -1, false, false)
            return
        }
        repeat(10) {
            val lp = cm.getLinkProperties(network)
            val name = lp?.interfaceName
            if (name != null) {
                val index = runCatching { NetworkInterface.getByName(name).index }.getOrNull()
                if (index != null) {
                    val caps = cm.getNetworkCapabilities(network)
                    val expensive = caps?.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED) == false
                    l.updateDefaultInterface(name, index, expensive, false)
                    return
                }
            }
            Thread.sleep(100)
        }
    }
}

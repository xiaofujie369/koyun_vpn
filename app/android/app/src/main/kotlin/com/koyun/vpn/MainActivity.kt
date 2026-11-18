package com.koyun.vpn

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.net.VpnService
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import androidx.core.content.ContextCompat
import com.koyun.vpn.vpn.KoyunVpnService
import com.koyun.vpn.vpn.VpnState
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Flutter <-> 原生桥：
 *  koyun/core         prepare / start / stop / status
 *  koyun/core/events  状态推送（stopped / starting / running + 错误）
 */
class MainActivity : FlutterActivity() {
    private var pendingPrepare: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        MethodChannel(messenger, "koyun/core").setMethodCallHandler { call, result ->
            when (call.method) {
                "prepare" -> prepare(result)
                "start" -> {
                    val config = call.argument<String>("config")
                    if (config.isNullOrEmpty()) {
                        result.error("bad_config", "empty config", null)
                    } else {
                        KoyunVpnService.saveConfig(this, config)
                        ContextCompat.startForegroundService(
                            this,
                            Intent(this, KoyunVpnService::class.java).setAction(KoyunVpnService.ACTION_START),
                        )
                        result.success(null)
                    }
                }
                "stop" -> {
                    KoyunVpnService.stop(this)
                    result.success(null)
                }
                "status" -> result.success(VpnState.status)
                "interrupted" -> result.success(KoyunVpnService.interrupted(this))
                "abis" -> result.success(Build.SUPPORTED_ABIS.toList())
                "batteryExempt" -> result.success(batteryExempt())
                "requestBatteryExempt" -> result.success(requestBatteryExempt())
                "openAppSettings" -> result.success(openAppSettings())
                "brand" -> result.success(Build.MANUFACTURER ?: "")
                else -> result.notImplemented()
            }
        }

        EventChannel(messenger, "koyun/core/events").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                VpnState.sink = events
                events.success(mapOf("status" to VpnState.status))
            }

            override fun onCancel(arguments: Any?) {
                VpnState.sink = null
            }
        })
    }

    /** 申请 VPN 授权（首次连接时系统弹窗），Android 13+ 顺便申请通知权限 */
    /** 是否已允许后台运行（不受电池优化限制）。国产系统不允许的话，切到后台不久内核就会被杀 */
    private fun batteryExempt(): Boolean =
        getSystemService(PowerManager::class.java)?.isIgnoringBatteryOptimizations(packageName) ?: true

    /** 弹系统窗口请用户允许；个别系统没有这个窗口，就打开电池优化列表 */
    private fun requestBatteryExempt(): Boolean {
        if (batteryExempt()) return true
        return runCatching {
            startActivity(Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:$packageName")))
            true
        }.recoverCatching {
            startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
            true
        }.getOrDefault(false)
    }

    /** 打开本 App 的系统设置页（小米 / 华为 / OPPO 的“自启动”“省电策略”在这里面） */
    private fun openAppSettings(): Boolean = runCatching {
        startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName")))
        true
    }.getOrDefault(false)

    private fun prepare(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 2)
        }
        val intent = VpnService.prepare(this)
        if (intent == null) {
            result.success(true)
            return
        }
        pendingPrepare = result
        @Suppress("DEPRECATION")
        startActivityForResult(intent, 1)
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == 1) {
            pendingPrepare?.success(resultCode == RESULT_OK)
            pendingPrepare = null
        }
    }
}

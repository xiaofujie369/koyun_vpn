package com.koyun.vpn

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.VpnService
import android.os.Build
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

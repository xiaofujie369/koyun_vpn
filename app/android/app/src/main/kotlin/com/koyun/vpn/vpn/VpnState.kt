package com.koyun.vpn.vpn

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel

/** VPN 状态（进程内单例），变化时推送给 Flutter 和快捷开关 */
object VpnState {
    @Volatile
    var status: String = "stopped"
        private set

    var sink: EventChannel.EventSink? = null
    private val main = Handler(Looper.getMainLooper())
    val listeners = mutableListOf<(String) -> Unit>()

    fun set(newStatus: String, error: String? = null) {
        status = newStatus
        main.post {
            val m = mutableMapOf<String, Any>("status" to newStatus)
            if (error != null) m["error"] = error
            sink?.success(m)
            listeners.toList().forEach { it(newStatus) }
        }
    }
}

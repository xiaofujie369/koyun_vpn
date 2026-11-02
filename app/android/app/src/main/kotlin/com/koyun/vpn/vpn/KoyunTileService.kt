package com.koyun.vpn.vpn

import android.content.Intent
import android.net.VpnService
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import androidx.core.content.ContextCompat
import com.koyun.vpn.MainActivity

/** 下拉通知栏的快捷开关：不打开 App 也能一键连接 / 断开（使用上次的配置） */
class KoyunTileService : TileService() {
    private val listener: (String) -> Unit = { refresh() }

    override fun onStartListening() {
        VpnState.listeners.add(listener)
        refresh()
    }

    override fun onStopListening() {
        VpnState.listeners.remove(listener)
    }

    private fun refresh() {
        val tile = qsTile ?: return
        tile.state = if (VpnState.status == "running") Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
        tile.updateTile()
    }

    override fun onClick() {
        if (VpnState.status == "running" || VpnState.status == "starting") {
            KoyunVpnService.stop(this)
            return
        }
        // 没授权过或没连接过：打开 App
        if (VpnService.prepare(this) != null || !KoyunVpnService.configFile(this).exists()) {
            val i = Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            @Suppress("DEPRECATION")
            startActivityAndCollapse(i)
            return
        }
        ContextCompat.startForegroundService(
            this, Intent(this, KoyunVpnService::class.java).setAction(KoyunVpnService.ACTION_START),
        )
    }
}

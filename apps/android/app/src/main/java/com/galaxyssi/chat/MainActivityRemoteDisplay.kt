package com.galaxyssi.chat

import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.widget.Toast
import kotlin.concurrent.thread

internal fun MainActivity.openDesktopRemoteControlPage(device: DesktopSecuritySummary) {
    activeDesktopControlId = null
    activeDesktopPerceptionId = null
    startActivityForResult(Intent(this, DesktopRemoteControlActivity::class.java)
        .putExtra(DesktopRemoteControlActivity.EXTRA_DESKTOP_ID, device.id)
        .putExtra(DesktopRemoteControlActivity.EXTRA_DESKTOP_NAME, device.name),
        DesktopRemoteControlActivity.REQUEST_CONTROL)
}

internal fun MainActivity.handleDesktopRemoteControlResult(code: Int, result: Int, data: Intent?): Boolean {
    if (code != DesktopRemoteControlActivity.REQUEST_CONTROL) return false
    if (result == Activity.RESULT_OK) {
        if (data?.getBooleanExtra(DesktopRemoteControlActivity.EXTRA_DISCONNECTED, false) == true) {
            refreshDirectoryContacts()
            showDesktopControlPicker(openSingle = false)
            return true
        }
        val id = data?.getStringExtra(DesktopRemoteControlActivity.EXTRA_DESKTOP_ID)
        desktopControlDevices().firstOrNull { it.id == id }?.let { showDesktopRemoteControlPage(it) }
    }
    return true
}

internal fun Activity.confirmDesktopDisconnect(desktopId: String, onDisconnected: () -> Unit) {
    val link = GalaxySSILinkProtocol.serverLink(this, desktopId) ?: return
    val fingerprint = link.desktopFingerprint
    if (fingerprint.isBlank()) return
    AlertDialog.Builder(this)
        .setTitle(R.string.desktop_disconnect_keep_history)
        .setMessage(getString(R.string.desktop_disconnect_confirmation, link.desktopName, fingerprint.chunked(4).joinToString(" ")))
        .setNegativeButton(R.string.common_cancel, null)
        .setPositiveButton(R.string.desktop_disconnect_action) { _, _ ->
            thread(name = "desktop-disconnect") {
                val disconnected = runCatching {
                    AppStore.disconnectDesktopKeepingHistory(applicationContext, desktopId, fingerprint)
                }.getOrDefault(false)
                runOnUiThread {
                    if (isFinishing || isDestroyed) return@runOnUiThread
                    if (disconnected) onDisconnected()
                    else Toast.makeText(this, R.string.desktop_disconnect_failed, Toast.LENGTH_SHORT).show()
                }
            }
        }
        .show()
}

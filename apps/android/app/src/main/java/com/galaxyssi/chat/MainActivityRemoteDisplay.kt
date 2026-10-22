package com.galaxyssi.chat

import android.app.Activity
import android.content.Intent

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
        val id = data?.getStringExtra(DesktopRemoteControlActivity.EXTRA_DESKTOP_ID)
        desktopControlDevices().firstOrNull { it.id == id }?.let { showDesktopRemoteControlPage(it) }
    }
    return true
}

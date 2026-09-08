package com.galaxyssi.chat

import android.accessibilityservice.AccessibilityServiceInfo
import android.graphics.Bitmap
import android.os.Bundle
import android.os.SystemClock
import android.view.accessibility.AccessibilityNodeInfo
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File

internal object AgentVoiceCameraDeviceActions {
    fun openAndConfirm(activity: MainActivity) {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val automation = instrumentation.uiAutomation
        automation.serviceInfo = automation.serviceInfo.apply {
            flags = flags or AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS
        }
        instrumentation.runOnMainSync { activity.agentVoiceConversation!!.panel.camera.performClick() }
        val deadline = SystemClock.elapsedRealtime() + 15_000L
        var confirmed = false
        while (SystemClock.elapsedRealtime() < deadline) {
            var ready = false
            instrumentation.runOnMainSync { ready = activity.agentVoiceConversation!!.cameraPreview.ready }
            if (ready) return
            if (!confirmed) {
                val button = automation.rootInActiveWindow
                    ?.findAccessibilityNodeInfosByViewId("android:id/button1")?.firstOrNull()
                if (button != null && button.text?.toString() == activity.getString(R.string.common_confirm)) {
                    check(button.performAction(AccessibilityNodeInfo.ACTION_CLICK))
                    confirmed = true
                    instrumentation.sendStatus(0, Bundle().apply { putString("camera_confirmation", "clicked_visible_dialog") })
                }
            }
            SystemClock.sleep(100)
        }
        val path = File(activity.getExternalFilesDir(null), "voice-ui-tests/camera-open-failed.png")
        path.parentFile?.mkdirs()
        automation.takeScreenshot()?.let {
            try { path.outputStream().use { stream -> it.compress(Bitmap.CompressFormat.PNG, 100, stream) } }
            finally { it.recycle() }
        }
        var state = ""
        instrumentation.runOnMainSync {
            val voice = activity.agentVoiceConversation!!
            state = "confirmed=$confirmed visible=${voice.visible()} active=${voice.cameraPreview.active} frames=${voice.cameraPreview.frames}"
        }
        throw AssertionError("Camera preview did not become ready: $state; screenshot=${path.absolutePath}")
    }
}

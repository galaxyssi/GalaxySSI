package com.galaxyssi.chat

import android.app.Instrumentation
import android.graphics.Bitmap
import android.graphics.Rect
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import java.io.File

internal data class BusinessVisualCapture(val stable: Boolean, val focused: Boolean, val text: String)

/** Sample only the output region for stability; the status-bar clock and composer cursor may keep changing. */
internal fun captureBusinessOutput(instrumentation: Instrumentation, window: MainActivity, file: File): BusinessVisualCapture {
    val deadline = SystemClock.elapsedRealtime() + 8_000L
    var previous: Bitmap? = null
    var matchingFrames = 0
    var focused = false
    var text = ""
    try {
        do {
            val bounds = Rect()
            instrumentation.runOnMainSync {
                focused = !window.isFinishing && !window.isDestroyed && window.hasWindowFocus()
                if (focused) {
                    window.agentOutputList.getGlobalVisibleRect(bounds)
                    text = businessVisibleText(window.agentOutputList).joinToString("\n")
                }
            }
            if (!focused || bounds.isEmpty) {
                previous?.recycle()
                previous = null
                matchingFrames = 0
                SystemClock.sleep(250)
                continue
            }
            val screenshot = instrumentation.uiAutomation.takeScreenshot()
            if (screenshot == null) {
                SystemClock.sleep(250)
                continue
            }
            try {
                if (!bounds.intersect(0, 0, screenshot.width, screenshot.height)) continue
                val cropped = Bitmap.createBitmap(screenshot, bounds.left, bounds.top, bounds.width(), bounds.height())
                val region = if (cropped === screenshot) screenshot.copy(Bitmap.Config.ARGB_8888, false) else cropped
                matchingFrames = if (previous?.sameAs(region) == true) matchingFrames + 1 else 0
                previous?.recycle()
                previous = region
                if (matchingFrames >= 2 || SystemClock.elapsedRealtime() >= deadline) {
                    file.outputStream().use { screenshot.compress(Bitmap.CompressFormat.PNG, 100, it) }
                    return BusinessVisualCapture(matchingFrames >= 2, focused, text)
                }
            } finally { screenshot.recycle() }
            SystemClock.sleep(250)
        } while (SystemClock.elapsedRealtime() < deadline)
        return BusinessVisualCapture(false, focused, text)
    } finally { previous?.recycle() }
}

private fun businessVisibleText(view: View): List<String> = if (!view.isShown) emptyList() else when (view) {
    is ViewGroup -> (0 until view.childCount).flatMap { businessVisibleText(view.getChildAt(it)) }
    is TextView -> listOf(view.text.toString())
    else -> emptyList()
}

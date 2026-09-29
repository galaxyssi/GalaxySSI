package com.galaxyssi.chat

import android.app.Instrumentation
import android.graphics.Bitmap
import android.graphics.Rect
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import java.io.File

internal data class BusinessVisualCapture(
    val stable: Boolean, val focused: Boolean, val text: String, val targetVisible: Boolean,
    val entryId: String = ""
)

/** Sample only the output region for stability; the status-bar clock and composer cursor may keep changing. */
internal fun captureBusinessOutput(
    instrumentation: Instrumentation, window: MainActivity, file: File, entryId: String,
    resolveEntryId: (() -> String?)? = null
): BusinessVisualCapture {
    val deadline = SystemClock.elapsedRealtime() + 8_000L
    var previous: Bitmap? = null
    var matchingFrames = 0
    var focused = false
    var text = ""
    var targetVisible = false
    var currentEntryId = entryId
    instrumentation.runOnMainSync {
        window.agentTranscriptAutoFollow = false
        val position = window.agentTranscriptAdapter.indexOfEntry(entryId)
        if (position >= 0) window.agentOutputLayout.scrollToPositionWithOffset(position, 0)
    }
    try {
        do {
            val bounds = Rect()
            var identityChanged = false
            instrumentation.runOnMainSync {
                val resolved = if (resolveEntryId == null) entryId else resolveEntryId().orEmpty()
                if (resolved != currentEntryId) {
                    currentEntryId = resolved
                    identityChanged = true
                    val position = window.agentTranscriptAdapter.indexOfEntry(currentEntryId)
                    if (position >= 0) window.agentOutputLayout.scrollToPositionWithOffset(position, 0)
                }
                focused = !window.isFinishing && !window.isDestroyed && window.hasWindowFocus()
                targetVisible = false
                text = ""
                if (focused) {
                    window.agentOutputList.getGlobalVisibleRect(bounds)
                    val position = window.agentTranscriptAdapter.indexOfEntry(currentEntryId)
                    val holder = window.agentOutputList.findViewHolderForAdapterPosition(position)
                    val visible = Rect()
                    targetVisible = position >= 0 && holder != null &&
                        currentEntryId.isNotBlank() && window.agentTranscriptAdapter.entryIdAt(holder.adapterPosition) == currentEntryId &&
                        holder.itemView.getGlobalVisibleRect(visible) && visible.intersect(bounds)
                    if (targetVisible) text = businessVisibleText(requireNotNull(holder).itemView).joinToString("\n")
                }
            }
            if (identityChanged) {
                previous?.recycle()
                previous = null
                matchingFrames = 0
            }
            if (!focused || !targetVisible || bounds.isEmpty) {
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
                    return BusinessVisualCapture(matchingFrames >= 2, focused, text, targetVisible, currentEntryId)
                }
            } finally { screenshot.recycle() }
            SystemClock.sleep(250)
        } while (SystemClock.elapsedRealtime() < deadline)
        instrumentation.uiAutomation.takeScreenshot()?.let { screenshot ->
            try { file.outputStream().use { screenshot.compress(Bitmap.CompressFormat.PNG, 100, it) } }
            finally { screenshot.recycle() }
        }
        return BusinessVisualCapture(false, focused, text, targetVisible, currentEntryId)
    } finally { previous?.recycle() }
}

private fun businessVisibleText(view: View): List<String> =
    if (!view.isShown || !view.getGlobalVisibleRect(Rect())) emptyList() else when (view) {
    is ViewGroup -> (0 until view.childCount).flatMap { businessVisibleText(view.getChildAt(it)) }
    is TextView -> listOf(view.text.toString())
    else -> emptyList()
}

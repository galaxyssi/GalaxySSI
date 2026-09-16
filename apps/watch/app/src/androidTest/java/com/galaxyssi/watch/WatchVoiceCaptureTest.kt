package com.galaxyssi.watch

import android.content.Intent
import android.os.SystemClock
import android.view.KeyEvent
import android.view.MotionEvent
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test

class WatchVoiceCaptureTest {
    private val inst get() = InstrumentationRegistry.getInstrumentation()
    private fun launch(): WatchVoiceCaptureActivity {
        val activity = inst.startActivitySync(Intent(inst.targetContext, WatchVoiceCaptureActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as WatchVoiceCaptureActivity
        val deadline = SystemClock.elapsedRealtime() + 6000
        var focused = false
        while (!focused && SystemClock.elapsedRealtime() < deadline) {
            inst.runOnMainSync { focused = activity.hasWindowFocus() }
            Thread.sleep(50)
        }
        assertTrue("Voice preview must be visible", focused)
        inst.runOnMainSync { call(activity, "releaseRecognizer") }
        return activity
    }
    private fun call(activity: WatchVoiceCaptureActivity, name: String) =
        WatchVoiceCaptureActivity::class.java.getDeclaredMethod(name).apply { isAccessible = true }.invoke(activity)
    private fun result(activity: WatchVoiceCaptureActivity) {
        WatchVoiceCaptureActivity::class.java.getDeclaredMethod("acceptFinal", String::class.java)
            .apply { isAccessible = true }.invoke(activity, "test transcript")
    }
    @Test fun finalResultReturnsAfterTwoSecondsWithoutConfirmation() {
        val activity = launch()
        try {
            inst.runOnMainSync { result(activity) }
            Thread.sleep(1000)
            inst.runOnMainSync { assertFalse(activity.isFinishing) }
            Thread.sleep(1500)
            inst.runOnMainSync { assertTrue(activity.isFinishing) }
        } finally { inst.runOnMainSync { activity.finish() } }
    }
    @Test fun touchKeyAndBackgroundCancelCountdown() {
        val activity = launch()
        try {
            for (kind in 0..2) {
                inst.runOnMainSync {
                    result(activity)
                    when (kind) {
                        0 -> {
                            val now = SystemClock.uptimeMillis()
                            val event = MotionEvent.obtain(now, now, MotionEvent.ACTION_DOWN, 225f, 100f, 0)
                            activity.dispatchTouchEvent(event); event.recycle()
                            val up = MotionEvent.obtain(now, now + 10, MotionEvent.ACTION_UP, 225f, 100f, 0)
                            activity.dispatchTouchEvent(up); up.recycle()
                        }
                        1 -> activity.dispatchKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_DPAD_CENTER))
                        else -> { inst.callActivityOnPause(activity); inst.callActivityOnResume(activity) }
                    }
                }
                Thread.sleep(2300)
                inst.runOnMainSync {
                    assertFalse(activity.isFinishing)
                    val draft = WatchVoiceCaptureActivity::class.java.getDeclaredField("draft").apply { isAccessible = true }.get(activity) as WatchVoiceDraft
                    assertEquals("test transcript", draft.text)
                    assertNull(draft.deadline)
                }
            }
        } finally { inst.runOnMainSync { activity.finish() } }
    }
}

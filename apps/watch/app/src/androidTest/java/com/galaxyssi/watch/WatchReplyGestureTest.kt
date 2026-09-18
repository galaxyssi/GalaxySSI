package com.galaxyssi.watch

import android.content.Intent
import android.os.SystemClock
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import androidx.test.platform.app.InstrumentationRegistry
import com.galaxyssi.chat.ui.ParagraphSelectingTextView
import org.junit.Assert.*
import org.junit.Test

class WatchReplyGestureTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private fun views(v: View): List<View> = listOf(v) + if (v is ViewGroup) (0 until v.childCount).flatMap { views(v.getChildAt(it)) } else emptyList()
    private fun event(action: Int, down: Long, x: Float, y: Float) {
        val e = MotionEvent.obtain(down, SystemClock.uptimeMillis(), action, x, y, 0)
        instrumentation.sendPointerSync(e); e.recycle()
    }
    private fun tap(x: Float, y: Float) {
        val down = SystemClock.uptimeMillis()
        event(MotionEvent.ACTION_DOWN, down, x, y); SystemClock.sleep(50)
        event(MotionEvent.ACTION_UP, down, x, y)
    }
    private fun withReply(check: (ParagraphSelectingTextView, Float, Float, () -> Int, () -> Int) -> Unit) {
        val activity = instrumentation.startActivitySync(Intent(instrumentation.targetContext, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as MainActivity
        var reads = 0
        var stops = 0
        var active = false
        lateinit var message: ParagraphSelectingTextView
        try {
            instrumentation.runOnMainSync {
                activity.window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                val conversation = WatchConversationView(activity, "", {}, {}, {}, {}, {}, {}, {}, {}, {},
                    onStopReading = { if (active) { active = false; stops++; true } else false },
                    onReadFrom = { _, _, _ -> reads++; active = true })
                activity.setContentView(conversation)
                conversation.update(listOf(WatchTask.create("api", "test", "test", "Gesture test").copy(state = TaskState.COMPLETED, reply = "First paragraph.\n\nSecond paragraph.")), "Test", true)
                message = views(conversation).filterIsInstance<ParagraphSelectingTextView>().single()
            }
            instrumentation.waitForIdleSync()
            val xy = IntArray(2)
            instrumentation.runOnMainSync { message.getLocationOnScreen(xy) }
            check(message, xy[0] + 35f, xy[1] + message.totalPaddingTop + 12f, { reads }, { stops })
        } finally { instrumentation.runOnMainSync { activity.finish() } }
    }
    @Test fun doubleTapReadsWithoutCopyAndNextDoubleTapStops() = withReply { message, x, y, reads, stops ->
        tap(x, y); SystemClock.sleep(80); tap(x, y)
        instrumentation.waitForIdleSync()
        instrumentation.runOnMainSync { assertEquals(1, reads()); assertFalse(message.hasSelection()); assertEquals(0, stops()) }
        SystemClock.sleep(400)
        tap(x, y); SystemClock.sleep(80); tap(x, y)
        instrumentation.waitForIdleSync()
        instrumentation.runOnMainSync { assertEquals(1, reads()); assertEquals(1, stops()); assertFalse(message.hasSelection()) }
    }
    @Test fun longPressStillSelectsParagraphWithoutReading() = withReply { message, x, y, reads, _ ->
        val down = SystemClock.uptimeMillis()
        event(MotionEvent.ACTION_DOWN, down, x, y)
        SystemClock.sleep(android.view.ViewConfiguration.getLongPressTimeout().toLong() + 200)
        event(MotionEvent.ACTION_UP, down, x, y)
        instrumentation.waitForIdleSync()
        instrumentation.runOnMainSync { assertEquals(0, reads()); assertTrue(message.hasSelection()) }
    }
    @Test fun cancelledSecondTapDoesNotReadOnNextSingleTap() = withReply { _, x, y, reads, _ ->
        tap(x, y); SystemClock.sleep(80)
        val down = SystemClock.uptimeMillis()
        event(MotionEvent.ACTION_DOWN, down, x, y)
        event(MotionEvent.ACTION_CANCEL, down, x, y)
        SystemClock.sleep(400); tap(x, y)
        instrumentation.waitForIdleSync()
        instrumentation.runOnMainSync { assertEquals(0, reads()) }
    }
}

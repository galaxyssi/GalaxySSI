package com.galaxyssi.chat

import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import android.widget.ImageView
import android.view.WindowManager
import android.view.MotionEvent
import android.os.SystemClock
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertFalse
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Isolated overlay and request; never captures a screen or submits a real Agent task. */
@RunWith(AndroidJUnit4::class)
class ScreenAssistantStopDeviceTest {
    @Test fun tappingBubbleTogglesToolsWithoutStartingAnalysis() = withOverlay { overlay, request, _ ->
        invoke(overlay, "ensureBubble")
        val bubble = field(overlay, "bubble") as View
        repeat(3) {
            touch(bubble, MotionEvent.ACTION_DOWN)
            touch(bubble, MotionEvent.ACTION_UP)
            assertNotNull(field(overlay, "menu"))
            touch(bubble, MotionEvent.ACTION_DOWN)
            touch(bubble, MotionEvent.ACTION_UP)
            assertEquals(null, field(overlay, "menu"))
            assertTrue(bubble.isAttachedToWindow)
        }
        assertTrue(request.turnId.isBlank())
        assertFalse(request.isCancelled)
    }

    @Test fun draggingOrCancellingDoesNotOpenTools() = withOverlay { overlay, _, _ ->
        invoke(overlay, "ensureBubble")
        val bubble = field(overlay, "bubble") as View
        val layout = field(overlay, "bubbleParams") as WindowManager.LayoutParams
        val x = layout.x
        val y = layout.y
        touch(bubble, MotionEvent.ACTION_DOWN)
        touch(bubble, MotionEvent.ACTION_MOVE, 200f)
        touch(bubble, MotionEvent.ACTION_CANCEL, 200f)
        assertEquals(null, field(overlay, "menu"))
        assertTrue(bubble.isAttachedToWindow)
        layout.x = x
        layout.y = y
        touch(bubble, MotionEvent.ACTION_DOWN)
        touch(bubble, MotionEvent.ACTION_CANCEL)
        assertEquals(null, field(overlay, "menu"))
    }

    private fun touch(view: View, action: Int, x: Float = 20f) {
        val now = SystemClock.uptimeMillis()
        val event = MotionEvent.obtain(now, now, action, x, 20f, 0)
        try { view.dispatchTouchEvent(event) } finally { event.recycle() }
    }

    @Test fun preparingRequestCanBeStoppedBeforeAnyTurnIsSubmitted() = withOverlay { overlay, request, _ ->
        assertTrue(request.turnId.isBlank())
        set(overlay, "pageCollection", ScreenAssistantPageCollection(request))
        invoke(overlay, "showPanel")
        invoke(overlay, "stopAnalysis")
        assertTrue(request.isCancelled)
    }

    @Test fun bubbleUsesSmallerTranslucentControlAndKeepsStatusBadge() = withOverlay { overlay, _, service ->
        invoke(overlay, "ensureBubble")
        val bubble = field(overlay, "bubble") as ViewGroup
        val layout = field(overlay, "bubbleParams") as WindowManager.LayoutParams
        val icon = bubble.getChildAt(0) as ImageView
        val density = service.resources.displayMetrics.density
        assertEquals(0.5f, bubble.alpha, 0.001f)
        assertEquals((48 * density + 0.5f).toInt(), layout.width)
        assertEquals(layout.width, layout.height)
        assertTrue(kotlin.math.abs((46.4f * density + 0.5f).toInt() - icon.layoutParams.width) <= 1)
        assertEquals(icon.layoutParams.width, icon.layoutParams.height)
        assertNotNull(icon.drawable)
        assertEquals(View.VISIBLE, bubble.getChildAt(1).visibility)
        set(overlay, "currentStatus", service.getString(R.string.screen_assistant_ready))
        invoke(overlay, "updateBubbleBadge")
        assertEquals(View.GONE, bubble.getChildAt(1).visibility)
    }

    @Test fun stopCancelsRequestAndPreservesPartialOutput() = withOverlay { overlay, request, service ->
        invoke(overlay, "stopAnalysis")
        assertTrue(request.isCancelled)
        assertEquals(service.getString(R.string.screen_assistant_cancelled), field(overlay, "currentStatus"))
        assertEquals("Test partial response", field(overlay, "currentText"))
        assertFalse(accepts(overlay, request))
    }

    @Test fun collapseKeepsAnalysisRunningAndMenuStillOffersStop() = withOverlay { overlay, request, service ->
        invoke(overlay, "dismissPanel")
        assertFalse(request.isCancelled)
        invoke(overlay, "showMenu")
        val menu = field(overlay, "menu") as ViewGroup
        descendants(menu).filterIsInstance<TextView>()
            .single { it.text.toString() == service.getString(R.string.screen_assistant_stop) }.performClick()
        assertTrue(request.isCancelled)
    }

    private fun withOverlay(test: (ScreenAssistantOverlay, ScreenAssistantAnalysisRequest, GalaxySSIAccessibilityService) -> Unit) {
        val serviceField = GalaxySSIAccessibilityService::class.java.getDeclaredField("activeService")
            .apply { isAccessible = true }
        val deadline = SystemClock.elapsedRealtime() + 15_000L
        var service = serviceField.get(null) as? GalaxySSIAccessibilityService
        while (service == null && SystemClock.elapsedRealtime() < deadline) {
            SystemClock.sleep(100L)
            service = serviceField.get(null) as? GalaxySSIAccessibilityService
        }
        val active = requireNotNull(service) { "Enable the accessibility service before running overlay tests" }
        assertTrue("Do not replace a queued user capture", ScreenAssistantSettings.pending(active) == null)
        val enabledBeforeTest = ScreenAssistantSettings.enabled(active)
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        instrumentation.runOnMainSync {
            val overlay = ScreenAssistantOverlay(active)
            val request = ScreenAssistantAnalysisRequest()
            try {
                ScreenAssistantSettings.setEnabled(active, true)
                set(overlay, "activeTurn", "")
                set(overlay, "request", request)
                set(overlay, "currentStatus", active.getString(R.string.screen_assistant_analyzing))
                set(overlay, "currentText", "Test partial response")
                test(overlay, request, active)
            } finally {
                overlay.close()
                ScreenAssistantSettings.setEnabled(active, enabledBeforeTest)
            }
        }
    }

    private fun descendants(view: View): Sequence<View> = sequence {
        yield(view)
        if (view is ViewGroup) for (index in 0 until view.childCount) yieldAll(descendants(view.getChildAt(index)))
    }
    private fun field(overlay: ScreenAssistantOverlay, name: String): Any? =
        ScreenAssistantOverlay::class.java.getDeclaredField(name).apply { isAccessible = true }.get(overlay)
    private fun set(overlay: ScreenAssistantOverlay, name: String, value: Any) =
        ScreenAssistantOverlay::class.java.getDeclaredField(name).apply { isAccessible = true }.set(overlay, value)
    private fun invoke(overlay: ScreenAssistantOverlay, name: String) =
        ScreenAssistantOverlay::class.java.getDeclaredMethod(name).apply { isAccessible = true }.invoke(overlay)
    private fun accepts(overlay: ScreenAssistantOverlay, request: ScreenAssistantAnalysisRequest): Boolean =
        ScreenAssistantOverlay::class.java.getDeclaredMethod("accepts", ScreenAssistantAnalysisRequest::class.java)
            .apply { isAccessible = true }.invoke(overlay, request) as Boolean
}

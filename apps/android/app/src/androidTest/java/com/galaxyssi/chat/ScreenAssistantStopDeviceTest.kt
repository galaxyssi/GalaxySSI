package com.galaxyssi.chat

import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import android.widget.ImageView
import android.view.WindowManager
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
    @Test fun firstAnalysisTapShowsPreparationAndCancelableRequestImmediately() = withOverlay { overlay, _, service ->
        invoke(overlay, "startAnalysisPreparation")
        val request = field(overlay, "request") as ScreenAssistantAnalysisRequest
        assertTrue(request.turnId.isBlank())
        val panel = field(overlay, "panel") as ViewGroup
        val text = descendants(panel).filterIsInstance<TextView>().map { it.text.toString() }.toList()
        assertTrue(service.getString(R.string.screen_assistant_preparing) in text)
        descendants(panel).filterIsInstance<TextView>()
            .single { it.text.toString() == service.getString(R.string.screen_assistant_stop) }.performClick()
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

    @Test fun stopButtonCancelsRequestAndPreservesPartialOutput() = withOverlay { overlay, request, service ->
        invoke(overlay, "showPanel")
        val panel = field(overlay, "panel") as ViewGroup
        val stop = descendants(panel).filterIsInstance<TextView>()
            .single { it.text.toString() == service.getString(R.string.screen_assistant_stop) }
        assertTrue(stop.visibility == View.VISIBLE)
        stop.performClick()
        assertTrue(request.isCancelled)
        val stoppedPanel = field(overlay, "panel") as ViewGroup
        val text = descendants(stoppedPanel).filterIsInstance<TextView>().map { it.text.toString() }.toList()
        assertTrue(service.getString(R.string.screen_assistant_cancelled) in text)
        assertTrue("Test partial response" in text)
        assertFalse(accepts(overlay, request))
    }

    @Test fun collapseKeepsAnalysisRunningAndMenuStillOffersStop() = withOverlay { overlay, request, service ->
        invoke(overlay, "showPanel")
        val panel = field(overlay, "panel") as ViewGroup
        descendants(panel).filterIsInstance<TextView>()
            .single { it.text.toString() == service.getString(R.string.screen_assistant_collapse) }.performClick()
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

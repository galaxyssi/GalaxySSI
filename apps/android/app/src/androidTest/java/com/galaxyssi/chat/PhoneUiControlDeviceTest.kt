package com.galaxyssi.chat

import android.content.Intent
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class PhoneUiControlDeviceTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private fun fixture(): GalaxySSIAccessibilityService {
        if (initialServiceBind.compareAndSet(false, true)) SystemClock.sleep(3_000)
        val deadline = SystemClock.elapsedRealtime() + 30_000
        while (!GalaxySSIAccessibilityService.isActive() && SystemClock.elapsedRealtime() < deadline) SystemClock.sleep(100)
        val service = requireNotNull(GalaxySSIAccessibilityService.targetService()) { "Enable GalaxySSI screen access first" }
        instrumentation.context.startActivity(Intent().setClassName(instrumentation.context.packageName,
            PhoneUiFixtureActivity::class.java.name).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK))
        SystemClock.sleep(500)
        val ready = SystemClock.elapsedRealtime() + 5_000
        var previousRevision = ""
        while (SystemClock.elapsedRealtime() < ready) {
            val snapshot = GalaxySSIAccessibilityService.readTargetUi()
            if (snapshot?.nodes?.any { it.text == "Fixture idle" } == true) {
                if (snapshot.revision == previousRevision) return service
                previousRevision = snapshot.revision
            } else previousRevision = ""
            SystemClock.sleep(100)
        }
        error("Fixture did not appear")
    }
    @Test fun readsUnderlyingFixtureWhileOwnPanelIsVisibleAndMasksPasswords() {
        val service = fixture()
        val overlay = ScreenAssistantOverlay(service)
        try {
            instrumentation.runOnMainSync {
                ScreenAssistantOverlay::class.java.getDeclaredField("currentText").apply { isAccessible = true }.set(overlay, "Assistant panel must not be observed")
                invoke(overlay, "ensureBubble")
            }
            val snapshot = requireNotNull(GalaxySSIAccessibilityService.readTargetUi())
            assertEquals(instrumentation.context.packageName, snapshot.packageName)
            assertTrue(snapshot.nodes.any { it.text == "Fixture idle" })
            assertFalse(snapshot.nodes.any { it.text.contains("Assistant panel must not be observed") })
            assertFalse(snapshot.nodes.any { it.text.contains("test-secret-never-export") || it.description.contains("test-secret") })
            assertTrue(snapshot.nodes.filter { it.password }.all { it.text == "[password]" && it.description.isBlank() })
            val screenshot = PhoneUiScreenshot.capture(service)
            assertTrue(screenshot.length() > 0)
            screenshot.delete()
        } finally { instrumentation.runOnMainSync { overlay.close() } }
    }
    @Test fun nodeClickAndInputReturnActualObservationAndRejectStaleRevision() {
        fixture()
        val before = requireNotNull(GalaxySSIAccessibilityService.readTargetUi())
        val button = before.nodes.first { it.text.equals("Fixture click", ignoreCase = true) }
        val clicked = GalaxySSIAccessibilityService.actOnTargetUi(before.windowId, before.revision, button.path, "click", "")
        assertEquals(true, clicked["accepted"])
        assertEquals(false, clicked["business_success_verified"])
        assertTrue(requireNotNull(GalaxySSIAccessibilityService.readTargetUi()).nodes.any { it.text == "Fixture clicked" })
        assertThrows(IllegalArgumentException::class.java) {
            GalaxySSIAccessibilityService.actOnTargetUi(before.windowId, before.revision, button.path, "click", "")
        }
        val current = requireNotNull(GalaxySSIAccessibilityService.readTargetUi())
        val input = current.nodes.first { it.editable && !it.password }
        val typed = GalaxySSIAccessibilityService.actOnTargetUi(current.windowId, current.revision, input.path, "set_text", "Fixture typed")
        assertEquals(true, typed["accepted"])
        assertTrue(requireNotNull(GalaxySSIAccessibilityService.readTargetUi()).nodes.any { it.text == "Fixture typed" })
        val typedPage = requireNotNull(GalaxySSIAccessibilityService.readTargetUi())
        val longTarget = typedPage.nodes.first { it.text.equals("Fixture click", ignoreCase = true) }
        assertEquals(true, GalaxySSIAccessibilityService.actOnTargetUi(typedPage.windowId, typedPage.revision,
            longTarget.path, "long_click", "")["accepted"])
        assertTrue(requireNotNull(GalaxySSIAccessibilityService.readTargetUi()).nodes.any { it.text == "Fixture long clicked" })
        val scrollingPage = requireNotNull(GalaxySSIAccessibilityService.readTargetUi())
        val scroll = scrollingPage.nodes.first { it.scrollable }
        assertEquals(true, GalaxySSIAccessibilityService.actOnTargetUi(scrollingPage.windowId, scrollingPage.revision,
            scroll.path, "scroll_forward", "")["accepted"])
        val scrolledPage = requireNotNull(GalaxySSIAccessibilityService.readTargetUi())
        assertNotEquals(scrollingPage.revision, scrolledPage.revision)
    }
    @Test fun pauseAndConfirmationControlsUseSameTaskAndCancellation() {
        val service = fixture()
        val overlay = ScreenAssistantOverlay(service)
        val request = ScreenAssistantAnalysisRequest().apply { automation = true }
        try {
            instrumentation.runOnMainSync {
                ScreenAssistantOverlay::class.java.getDeclaredField("request").apply { isAccessible = true }.set(overlay, request)
                ScreenAssistantOverlay::class.java.getDeclaredField("activeTurn").apply { isAccessible = true }.set(overlay, "")
                ScreenAssistantOverlay::class.java.getDeclaredField("pageCollection").apply { isAccessible = true }
                    .set(overlay, ScreenAssistantPageCollection(request))
                invoke(overlay, "showPanel")
                val panel = ScreenAssistantOverlay::class.java.getDeclaredField("panel").apply { isAccessible = true }.get(overlay) as View
                descendants(panel).filterIsInstance<TextView>().single { it.text == service.getString(R.string.screen_assistant_pause_task) }.performClick()
                assertTrue(request.isPaused)
                descendants(panel).filterIsInstance<TextView>().single { it.text == service.getString(R.string.screen_assistant_resume_task) }.performClick()
                assertFalse(request.isPaused)
                descendants(panel).filterIsInstance<TextView>().single { it.text == service.getString(R.string.screen_assistant_page_cancel) }.performClick()
                assertTrue(request.isCancelled)
            }
        } finally { instrumentation.runOnMainSync { overlay.close() } }
    }
    @Test fun nativeToolRejectsUnownedMutationAndAllowsExplicitTask() {
        val service = fixture()
        val before = requireNotNull(GalaxySSIAccessibilityService.readTargetUi())
        val button = before.nodes.first { it.text.equals("Fixture click", ignoreCase = true) }
        val registry = AgentNativeToolRegistry().registerAll(AgentPhoneUiNativeTools.definitions(service))
        val input = mapOf("window_id" to before.windowId, "revision" to before.revision,
            "node_path" to button.path, "operation" to "click")
        val turn = "fixture-ui-${java.util.UUID.randomUUID()}"
        val invocation = AgentNativeToolInvocationContext(sessionId = turn, conversationId = turn,
            turnId = turn, idempotencyKey = "fixture-unowned")
        assertFalse(registry.invoke(AgentPhoneUiNativeTools.ACT, input, invocation).isSuccess)
        PhoneAssistantTaskControl.bind(turn, ScreenAssistantAnalysisRequest().apply { automation = true })
        try {
            val current = requireNotNull(GalaxySSIAccessibilityService.readTargetUi())
            val freshInput = input + mapOf("window_id" to current.windowId, "revision" to current.revision,
                "node_path" to current.nodes.first { it.text.equals("Fixture click", ignoreCase = true) }.path)
            val result = registry.invoke(AgentPhoneUiNativeTools.ACT, freshInput,
                invocation.copy(idempotencyKey = "fixture-authorized:$turn"))
            assertTrue("Authorized tool failed: ${result.message} ${result.error}", result.isSuccess)
            assertTrue(requireNotNull(GalaxySSIAccessibilityService.readTargetUi()).nodes.any { it.text == "Fixture clicked" })
        } finally { PhoneAssistantTaskControl.finish(turn) }
    }
    private fun invoke(overlay: ScreenAssistantOverlay, method: String) =
        ScreenAssistantOverlay::class.java.getDeclaredMethod(method).apply { isAccessible = true }.invoke(overlay)
    private fun descendants(view: View): Sequence<View> = sequence {
        yield(view)
        if (view is ViewGroup) for (index in 0 until view.childCount) yieldAll(descendants(view.getChildAt(index)))
    }
    companion object { private val initialServiceBind = java.util.concurrent.atomic.AtomicBoolean(false) }
}

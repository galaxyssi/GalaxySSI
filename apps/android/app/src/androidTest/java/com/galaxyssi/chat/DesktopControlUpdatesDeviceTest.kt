package com.galaxyssi.chat

import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import android.content.Context
import android.os.Bundle
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.util.UUID

@RunWith(AndroidJUnit4::class)
class DesktopControlUpdatesDeviceTest {
    private val context = ApplicationProvider.getApplicationContext<Context>()
    private val desktopId = "test-control-${UUID.randomUUID()}"
    private val listeners = mutableListOf<GalaxySSIMqttClient.Listener>()

    @After fun cleanup() {
        listeners.forEach(GalaxySSIMqttClient::removeListener)
        DesktopRemoteControl.clearDesktop(context, desktopId)
    }

    private fun listen(listener: GalaxySSIMqttClient.Listener) {
        listeners.add(listener)
        GalaxySSIMqttClient.addListener(listener)
    }

    private fun event(type: String = "desktop_executor_event") = JSONObject()
        .put("type", type).put("desktop_id", desktopId)
        .put("status", "running").put("summary", "Synthetic control update")

    @Test fun realAndroidCanonicalDigestMatchesDesktopPython() {
        val value = JSONObject()
            .put("contract_version", "galaxyssi.desktop-control/1.6")
            .put("image_mime", "image/jpeg")
            .put("text", "</tag>\u2028\u2029\u0000\n\t\\/\"\u4e2d\u6587")
        assertEquals("3d9f851b7ac913baa5dd80afd1ab6211245b17a0c0ad4e4a22bec2e841522744",
            DesktopControlReceiptProtocol.digest(value))
    }

    @Test fun controlStateIsAppliedBeforeDedicatedNotificationAndNeverBecomesChat() {
        var updated = false
        var chatMessages = 0
        listen(object : GalaxySSIMqttClient.Listener {
            override fun onMessage(payload: String) { chatMessages++ }
            override fun onDesktopControlChanged(id: String, streamFrame: Boolean) {
                if (id != desktopId) return
                assertFalse(streamFrame)
                updated = DesktopRemoteControl.snapshot(context, id).lastActionStatus == "running"
            }
        })
        assertTrue(GalaxySSIMqttClient.dispatchDesktopControlInbound(context, event()))
        assertTrue(updated)
        assertEquals(0, chatMessages)
    }

    @Test fun authorizationUpdatesReachTheOpenPage() {
        var enabled = false
        listen(object : GalaxySSIMqttClient.Listener {
            override fun onDesktopControlChanged(id: String, streamFrame: Boolean) {
                if (id == desktopId) enabled = DesktopRemoteControl.snapshot(context, id).enabled
            }
        })
        assertTrue(GalaxySSIMqttClient.dispatchDesktopControlInbound(context,
            event("desktop_control_authorizations").put("enabled", true)))
        assertTrue(enabled)
    }

    @Test fun rejectedScreenshotNotifiesStatusWithoutExposingUnverifiedPixels() {
        var updated = false
        listen(object : GalaxySSIMqttClient.Listener {
            override fun onDesktopControlChanged(id: String, streamFrame: Boolean) {
                if (id != desktopId) return
                val state = DesktopRemoteControl.snapshot(context, id)
                updated = state.lastActionStatus == "unverified" && state.screenshot == null
            }
        })
        assertTrue(GalaxySSIMqttClient.dispatchDesktopControlInbound(context,
            event("desktop_action_receipt").put("action_id", UUID.randomUUID().toString())
                .put("output", JSONObject().put("screenshot", JSONObject()
                    .put("image_mime", "image/jpeg").put("image_base64", "AQID")))))
        assertTrue(updated)
    }

    @Test fun streamUpdatesKeepTheirLightweightRenderingFlag() {
        var frame = false
        listen(object : GalaxySSIMqttClient.Listener {
            override fun onDesktopControlChanged(id: String, streamFrame: Boolean) {
                if (id == desktopId) frame = streamFrame
            }
        })
        assertTrue(GalaxySSIMqttClient.dispatchDesktopControlInbound(context,
            event("desktop_action_receipt").put("output", JSONObject().put("stream_frame", true))))
        assertTrue(frame)
    }

    @Test fun brokenUiListenerDoesNotPreventOtherListenersOrUndoCommittedState() {
        var updated = false
        listen(object : GalaxySSIMqttClient.Listener {
            override fun onDesktopControlChanged(id: String, streamFrame: Boolean) {
                if (id == desktopId) error("Synthetic detached UI")
            }
        })
        listen(object : GalaxySSIMqttClient.Listener {
            override fun onDesktopControlChanged(id: String, streamFrame: Boolean) {
                if (id == desktopId) updated = true
            }
        })
        assertTrue(GalaxySSIMqttClient.dispatchDesktopControlInbound(context, event()))
        assertTrue(updated)
        assertEquals("running", DesktopRemoteControl.snapshot(context, desktopId).lastActionStatus)
    }

    @Test fun controlStateSurvivesWithoutAnOpenUi() {
        assertTrue(GalaxySSIMqttClient.dispatchDesktopControlInbound(context, event()))
        assertEquals("running", DesktopRemoteControl.snapshot(context, desktopId).lastActionStatus)
    }

    @Test fun ordinaryMessagesAndAgentTaskEventsRetainTheirExistingDispatch() {
        var updates = 0
        listen(object : GalaxySSIMqttClient.Listener {
            override fun onDesktopControlChanged(id: String, streamFrame: Boolean) { updates++ }
        })
        for (type in listOf("text", "peer_message", "agent_task_event", "connector_status")) {
            assertFalse(GalaxySSIMqttClient.dispatchDesktopControlInbound(context, event(type)))
        }
        assertEquals(0, updates)
    }

    @Test fun explicitlyRequestedLiveDesktopScreenshotIsVerifiedAndDelivered() {
        val target = InstrumentationRegistry.getArguments().getString("desktop_control_live_id").orEmpty()
        assumeTrue("Live Desktop validation is opt-in", target.isNotBlank())
        assertNotNull(GalaxySSILinkProtocol.serverLink(context, target))
        GalaxySSIMqttClient.connect(context)
        val connectedBy = System.currentTimeMillis() + 30_000
        while (!GalaxySSIMqttClient.isConnected() && System.currentTimeMillis() < connectedBy) Thread.sleep(100)
        assertTrue("MQTT did not connect", GalaxySSIMqttClient.isConnected())
        GalaxySSIMqttClient.bindApplicationContext(context)
        DesktopRemoteControl.requestAuthorizations(target)
        val authorizedBy = System.currentTimeMillis() + 20_000
        while ((DesktopRemoteControl.snapshot(context, target).currentAuthorization?.desktopSessionExpiresAt ?: 0) <=
            System.currentTimeMillis() && System.currentTimeMillis() < authorizedBy) Thread.sleep(100)
        val started = System.currentTimeMillis()
        val updates = java.util.concurrent.atomic.AtomicInteger()
        listen(object : GalaxySSIMqttClient.Listener {
            override fun onDesktopControlChanged(id: String, streamFrame: Boolean) {
                if (id == target) updates.incrementAndGet()
            }
        })
        assertTrue("Screenshot request not accepted", DesktopRemoteControl.requestScreenshot(target))
        val deadline = started + 45_000
        while (System.currentTimeMillis() < deadline &&
            (DesktopRemoteControl.snapshot(context, target).screenshot?.capturedAt ?: 0) < started) Thread.sleep(100)
        val state = DesktopRemoteControl.snapshot(context, target)
        InstrumentationRegistry.getInstrumentation().sendStatus(0, Bundle().apply {
            putString("stream", "Live Desktop: status=${state.lastActionStatus}, " +
                "summary=${state.lastActionSummary}, updates=${updates.get()}, " +
                "jpeg_bytes=${state.screenshot?.jpegBytes?.size ?: 0}, elapsed_ms=${System.currentTimeMillis() - started}\n")
        })
        assertNotNull("No verified screenshot: ${state.lastActionStatus}/${state.lastActionSummary}", state.screenshot)
        assertTrue(state.screenshot!!.capturedAt >= started)
        assertTrue("No UI change callback", updates.get() > 0)
    }
}

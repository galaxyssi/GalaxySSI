package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class DesktopRunControlTest {
    @Test
    fun parsesActiveRunControlsAndTakeoverIdentity() {
        val runs = parseDesktopRunSummaries(
            JSONArray()
                .put(
                    JSONObject()
                        .put("task_id", "task-running")
                        .put("conversation_id", "conversation-1")
                        .put("turn_id", "turn-1")
                        .put("agent_id", "codex")
                        .put("status", "running")
                        .put("prompt", "Build the project")
                        .put("current_step", "Running tests")
                        .put("updated_at", 1_800_000_000_000L)
                        .put(
                            "execution_view",
                            JSONObject()
                                .put("pausable", true)
                                .put("resumable", false)
                                .put("takeover_available", false)
                                .put("takeover_active", false)
                        )
                )
                .put(
                    JSONObject()
                        .put("task_id", "task-takeover")
                        .put("task_status", "takeover")
                        .put(
                            "execution_view",
                            JSONObject()
                                .put("pausable", false)
                                .put("resumable", true)
                                .put("takeover_available", false)
                                .put("takeover_active", true)
                                .put(
                                    "takeover",
                                    JSONObject().put("controller_name", "Galaxy")
                                )
                        )
                )
                .put(JSONObject().put("status", "running"))
        )

        assertEquals(2, runs.size)
        assertEquals("running", runs[0].status)
        assertEquals("Running tests", runs[0].currentStep)
        assertTrue(runs[0].pausable)
        assertFalse(runs[0].resumable)
        assertEquals("takeover", runs[1].status)
        assertTrue(runs[1].resumable)
        assertTrue(runs[1].takeoverActive)
        assertEquals("Galaxy", runs[1].takeoverController)
    }

    @Test
    fun taskControlRequestDigestBindsTargetTaskAndAction() {
        fun request(toolId: String, targetTaskId: String) = JSONObject()
            .put("type", "desktop_executor_request")
            .put("task_id", "desktop-control-action")
            .put("action_id", "00000000-0000-4000-8000-000000000001")
            .put("authorization_id", "00000000-0000-4000-8000-000000000002")
            .put("desktop_session_id", "session-1")
            .put("tool_id", toolId)
            .put("input", JSONObject().put("task_id", targetTaskId))
            .put("sent_at", 1_800_000_000_000L)
            .put("expires_at", 1_800_000_030_000L)

        val pause = DesktopControlReceiptProtocol.pendingRequest(
            request(DesktopRemoteControl.TASK_PAUSE, "task-1"),
            "client-route-1",
            "controller-fingerprint",
            "galaxyssi:phone"
        )
        val anotherTask = DesktopControlReceiptProtocol.pendingRequest(
            request(DesktopRemoteControl.TASK_PAUSE, "task-2"),
            "client-route-1",
            "controller-fingerprint",
            "galaxyssi:phone"
        )
        val continueRequest = DesktopControlReceiptProtocol.pendingRequest(
            request(DesktopRemoteControl.TASK_CONTINUE, "task-1"),
            "client-route-1",
            "controller-fingerprint",
            "galaxyssi:phone"
        )

        assertEquals("galaxyssi.desktop-control/1.6", DesktopControlReceiptProtocol.CONTRACT_VERSION)
        assertEquals(DesktopRemoteControl.TASK_PAUSE, pause.toolId)
        assertNotEquals(pause.inputSha256, anotherTask.inputSha256)
        assertNotEquals(pause.requestSha256, continueRequest.requestSha256)
    }
}

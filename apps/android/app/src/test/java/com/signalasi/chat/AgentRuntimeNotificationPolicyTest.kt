package com.signalasi.chat

import org.json.JSONObject
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentRuntimeNotificationPolicyTest {
    @Test
    fun authenticatedAgentFinalDoesNotCreateForegroundMessageNotification() {
        val envelope = JSONObject()
            .put("type", "text")
            .put("source_message_id", 42L)
            .put("conversation_id", "conversation")
            .put("turn_id", "turn")
            .put("task_id", "task")

        assertTrue(AgentRuntimeNotificationPolicy.suppressMessageNotification(envelope))
    }

    @Test
    fun ordinaryPeerMessageStillCreatesForegroundNotification() {
        val envelope = JSONObject()
            .put("type", "text")
            .put("source_message_id", 42L)
            .put("contact_id", "peer")
            .put("content", "hello")

        assertFalse(AgentRuntimeNotificationPolicy.suppressMessageNotification(envelope))
    }

    @Test
    fun agentTaskProgressDoesNotCreateMessageNotification() {
        assertTrue(
            AgentRuntimeNotificationPolicy.suppressMessageNotification(
                JSONObject().put("type", "agent_task_event")
            )
        )
    }
}

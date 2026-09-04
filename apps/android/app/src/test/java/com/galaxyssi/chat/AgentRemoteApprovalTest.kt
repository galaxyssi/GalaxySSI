package com.galaxyssi.chat

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentRemoteApprovalTest {
    @Test
    fun validTaskApprovalRoundTripsAnExactDecision() {
        val request = AgentRemoteApprovalRequest.fromTaskEvent(taskEvent())

        requireNotNull(request)
        assertEquals("approval-12345678", request.approvalId)
        assertEquals("python verify.py", request.detail)
        assertEquals("aaaaaaaa...aaaaaaaa", request.compactActionHash)

        val approved = AgentRemoteApprovalDecision.decode(
            request.decision(AgentPermissionChoice.ALLOW_SESSION).encode()
        )
        requireNotNull(approved)
        assertTrue(approved.approved)
        assertEquals(AgentPermissionChoice.ALLOW_SESSION, approved.choice)
        assertEquals(request.taskId, approved.taskId)
        assertEquals(request.clientRouteId, approved.clientRouteId)
        assertEquals(request.conversationId, approved.conversationId)
        assertEquals(request.turnId, approved.turnId)
        assertEquals(request.actionHash, approved.actionHash)
    }

    @Test
    fun expiredOrMalformedApprovalsAreRejected() {
        assertNull(
            AgentRemoteApprovalRequest.fromTaskEvent(
                taskEvent(expiresAt = 1_500L),
                nowMillis = 2_000L
            )
        )
        assertNull(
            AgentRemoteApprovalRequest.fromTaskEvent(
                taskEvent(actionHash = "changed")
            )
        )
        assertNull(
            AgentRemoteApprovalRequest.fromTaskEvent(
                taskEvent(sourceMessageId = 0L)
            )
        )
    }

    @Test
    fun decisionDecoderRejectsChangedIdentityFields() {
        val request = requireNotNull(AgentRemoteApprovalRequest.fromTaskEvent(taskEvent()))
        val raw = JSONObject(request.decision(AgentPermissionChoice.DENY_ALWAYS).encode())
            .put("approval_id", "short")
            .toString()

        assertNull(AgentRemoteApprovalDecision.decode(raw))
        assertFalse(request.decision(AgentPermissionChoice.DENY_ALWAYS).approved)
    }

    private fun taskEvent(
        sourceMessageId: Long = 42L,
        actionHash: String = "a".repeat(64),
        expiresAt: Long = System.currentTimeMillis() + 300_000L
    ): JSONObject = JSONObject()
        .put("type", "agent_task_event")
        .put("task_status", "waiting_approval")
        .put("task_id", "task-approval")
        .put("client_route_id", "client-route")
        .put("conversation_id", "conversation-approval")
        .put("turn_id", "turn-approval")
        .put("contact_id", "codex-contact")
        .put("source_message_id", sourceMessageId)
        .put("approval_request", JSONObject()
            .put("approval_id", "approval-12345678")
            .put("action_hash", actionHash)
            .put("kind", "command")
            .put("title", "Run a command")
            .put("detail", "python verify.py")
            .put("target", "python verify.py")
            .put("reason", "Verify the result")
            .put("requested_at_ms", expiresAt - 300_000L)
            .put("expires_at_ms", expiresAt)
            .put("parameters", JSONObject()
                .put("command", "python verify.py")
                .put("cwd", "C:/workspace")))
}

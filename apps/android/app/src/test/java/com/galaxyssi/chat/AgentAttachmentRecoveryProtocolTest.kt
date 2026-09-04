package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class AgentAttachmentRecoveryProtocolTest {
    @Test
    fun decodesBoundedTaskScopedRequest() {
        val request = AgentAttachmentRecoveryRequest.decode(
            basePayload().put(
                "attachment_ids",
                JSONArray().put("image-one").put("image-one").put("file-two")
            )
        )

        requireNotNull(request)
        assertEquals(listOf("image-one", "file-two"), request.attachmentIds)
        assertEquals("conversation-one", request.conversationId)
        assertEquals(42L, request.sourceMessageId)
        assertEquals(
            AgentAttachmentRecoveryRequest.RESULT_TYPE,
            request.result("transferring", listOf("image-one")).getString("type")
        )
    }

    @Test
    fun rejectsInvalidRequestIdentityAndEmptyAttachmentSet() {
        assertNull(
            AgentAttachmentRecoveryRequest.decode(
                basePayload()
                    .put("request_id", "not-valid")
                    .put("attachment_ids", JSONArray().put("image-one"))
            )
        )
        assertNull(
            AgentAttachmentRecoveryRequest.decode(
                basePayload().put("attachment_ids", JSONArray())
            )
        )
    }

    private fun basePayload(): JSONObject = JSONObject()
        .put("type", AgentAttachmentRecoveryRequest.REQUEST_TYPE)
        .put("request_id", "0123456789abcdef0123456789abcdef")
        .put("client_route_id", "route-one")
        .put("conversation_id", "conversation-one")
        .put("task_id", "task-one")
        .put("turn_id", "turn-one")
        .put("contact_id", "codex")
        .put("source_message_id", "42")
}

package com.galaxyssi.chat

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CollaborationRemoteRecallProtocolTest {
    private fun request() = JSONObject().apply {
        AgentResultRecoveryClient.FIELDS.forEach { put(it, if (it == "agent_id") "codex" else it) }
        put("execution_generation", 1).put("expires_at", 30_000L)
        put("type", CollaborationRemoteRecallProtocol.REQUEST).put("contract", CollaborationRemoteRecallProtocol.CONTRACT)
        put("request_id", "nonce").put("arguments", JSONObject().put("mode", "workspace"))
    }

    @Test fun requestMustBeFreshAndCompletelyScoped() {
        assertTrue(CollaborationRemoteRecallProtocol.valid(request(), 10_000))
        for (field in AgentResultRecoveryClient.FIELDS + listOf("execution_generation", "request_id", "arguments", "contract")) {
            val changed = request().apply { remove(field) }
            assertFalse(field, CollaborationRemoteRecallProtocol.valid(changed, 10_000))
        }
        assertFalse(CollaborationRemoteRecallProtocol.valid(request(), 30_000))
        assertFalse(CollaborationRemoteRecallProtocol.valid(request().put("expires_at", 100_000L), 10_000))
        assertFalse(CollaborationRemoteRecallProtocol.valid(request().put("agent_id", "other"), 10_000))
        assertFalse(CollaborationRemoteRecallProtocol.valid(request().put("arguments", "not-object"), 10_000))
    }

    @Test fun responseCopiesOnlyHostIdentityAndNonce() {
        val request = request().put("group_id", "untrusted").put("member_id", "untrusted")
        val response = CollaborationRemoteRecallProtocol.response(request, JSONObject().put("success", true))
        AgentResultRecoveryClient.FIELDS.forEach { assertEquals(request.get(it), response.get(it)) }
        assertEquals(1, response.getInt("execution_generation"))
        assertEquals("nonce", response.getString("request_id"))
        assertEquals(CollaborationRemoteRecallProtocol.RESPONSE, response.getString("type"))
        assertFalse(response.has("arguments"))
        assertFalse(response.has("group_id"))
        assertFalse(response.has("member_id"))
        assertTrue(MqttQueryDeliveryPolicy.isTransient(response.getString("type")))
    }
}

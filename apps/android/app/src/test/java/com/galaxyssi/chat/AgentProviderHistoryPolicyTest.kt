package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentProviderHistoryPolicyTest {
    @Test
    fun automaticAgentProviderTraceIsInternalHistory() {
        val message = JSONObject()
            .put("contactId", "codex")
            .put(
                "deliveryTrace",
                JSONArray().put(JSONObject().put("stage", "agent_confirmed"))
            )

        assertTrue(AgentProviderHistoryPolicy.isInternalAgentRuntimeMessage(message))
    }

    @Test
    fun directContactMessageRemainsVisible() {
        val message = JSONObject()
            .put("contactId", "codex")
            .put(
                "deliveryTrace",
                JSONArray().put(JSONObject().put("stage", "created").put("detail", "user_send"))
            )

        assertFalse(AgentProviderHistoryPolicy.isInternalAgentRuntimeMessage(message))
    }
}

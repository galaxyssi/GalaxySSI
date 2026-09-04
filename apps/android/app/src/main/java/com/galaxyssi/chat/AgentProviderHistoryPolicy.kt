package com.galaxyssi.chat

import org.json.JSONObject

internal object AgentProviderHistoryPolicy {
    fun isInternalAgentRuntimeMessage(message: JSONObject): Boolean {
        val trace = message.optJSONArray("deliveryTrace")
            ?: message.optJSONArray("delivery_trace")
            ?: return false
        for (index in 0 until trace.length()) {
            val event = trace.optJSONObject(index) ?: continue
            if (event.optString("stage") == "agent_confirmed") return true
        }
        return false
    }
}

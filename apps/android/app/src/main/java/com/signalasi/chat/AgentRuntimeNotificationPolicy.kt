package com.signalasi.chat

import org.json.JSONObject

internal object AgentRuntimeNotificationPolicy {
    fun suppressMessageNotification(envelope: JSONObject?): Boolean {
        envelope ?: return false
        val type = envelope.optString("type").ifBlank { "text" }
        if (type == "agent_task_event") return true
        if (type != "text") return false
        val sourceMessageId = envelope.optString("source_message_id").toLongOrNull()
            ?: envelope.optLong("source_message_id", 0L)
        if (sourceMessageId <= 0L) return false
        return envelope.optString("conversation_id").isNotBlank() &&
            envelope.optString("turn_id").isNotBlank() &&
            envelope.optString("task_id").isNotBlank()
    }
}

package com.galaxyssi.chat

import org.json.JSONObject
import java.util.Locale

/** Classification uses authenticated application types, never words in a user's message. */
internal object MqttTrafficPolicy {
    fun classify(payload: JSONObject): String = when (payload.optString("type")) {
        "agent_task_cancel", "desktop_tool_call_cancel", "client_revoked", "desktop_control_revoke", "pairing_revoked" -> "control"
        "delivery_ack" -> "receipt"
        "input_attachment_chunk", "artifact_chunk" -> "chunk"
        "agent_task_event" -> if (payload.optString("task_status").ifBlank { payload.optString("status") }
            in setOf("completed", "failed", "cancelled", "canceled")) "final" else "progress"
        "text", "error", "rich_output" -> if (payload.optString("task_id").isNotBlank()) "final" else "message"
        else -> "message"
    }

    fun parse(value: String) = MqttMultipathPolicy.Traffic.valueOf(value.uppercase(Locale.ROOT))
}

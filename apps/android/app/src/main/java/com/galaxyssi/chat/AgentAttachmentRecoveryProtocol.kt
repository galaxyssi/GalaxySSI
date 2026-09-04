package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject

internal data class AgentAttachmentRecoveryRequest(
    val requestId: String,
    val clientRouteId: String,
    val conversationId: String,
    val taskId: String,
    val turnId: String,
    val contactId: String,
    val sourceMessageId: Long,
    val attachmentIds: List<String>
) {
    fun result(
        status: String,
        availableAttachmentIds: Collection<String> = emptyList(),
        missingAttachmentIds: Collection<String> = emptyList(),
        error: String = ""
    ): JSONObject = JSONObject()
        .put("type", RESULT_TYPE)
        .put("request_id", requestId)
        .put("client_route_id", clientRouteId)
        .put("conversation_id", conversationId)
        .put("task_id", taskId)
        .put("turn_id", turnId)
        .put("contact_id", contactId)
        .put("source_message_id", sourceMessageId.toString())
        .put("status", status)
        .put("available_attachment_ids", JSONArray(availableAttachmentIds.toList()))
        .put("missing_attachment_ids", JSONArray(missingAttachmentIds.toList()))
        .put("time", System.currentTimeMillis())
        .also { payload ->
            error.trim().takeIf(String::isNotBlank)?.let {
                payload.put("error", it.take(300))
            }
        }

    companion object {
        const val REQUEST_TYPE = "input_attachment_request"
        const val RESULT_TYPE = "input_attachment_request_result"
        private const val MAX_ATTACHMENTS = 10
        private val REQUEST_ID = Regex("[a-f0-9]{32}")

        fun decode(payload: JSONObject): AgentAttachmentRecoveryRequest? = runCatching {
            require(payload.optString("type") == REQUEST_TYPE)
            val requestId = payload.getString("request_id").lowercase()
            require(requestId.matches(REQUEST_ID))
            val sourceMessageId = payload.optString("source_message_id").toLongOrNull()
                ?: payload.optLong("source_message_id", 0L)
            require(sourceMessageId > 0L)
            val attachmentIds = payload.optJSONArray("attachment_ids") ?: JSONArray()
            val requested = buildList {
                for (index in 0 until minOf(attachmentIds.length(), MAX_ATTACHMENTS)) {
                    val value = attachmentIds.optString(index).trim()
                    if (value.isNotBlank() && value.length <= 120 && value !in this) add(value)
                }
            }
            require(requested.isNotEmpty())
            AgentAttachmentRecoveryRequest(
                requestId = requestId,
                clientRouteId = identity(payload, "client_route_id"),
                conversationId = identity(payload, "conversation_id"),
                taskId = identity(payload, "task_id"),
                turnId = identity(payload, "turn_id"),
                contactId = identity(payload, "contact_id"),
                sourceMessageId = sourceMessageId,
                attachmentIds = requested
            )
        }.getOrNull()

        private fun identity(payload: JSONObject, key: String): String {
            val value = payload.getString(key).trim()
            require(value.isNotBlank() && value.length <= 256 && value.none { it.code < 32 })
            return value
        }
    }
}

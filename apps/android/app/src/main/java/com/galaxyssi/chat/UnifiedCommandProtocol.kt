package com.galaxyssi.chat

import org.json.JSONObject
import java.util.UUID

object UnifiedCommandProtocol {
    const val REQUEST_TYPE = "unified_command"
    const val RESULT_TYPE = "unified_command_result"

    fun requestPayload(
        commandId: String,
        args: Map<String, Any?> = emptyMap(),
        raw: String = "",
        slash: String = "",
        contactId: String = "system",
        requestedBy: String = "paired_phone",
        approve: Boolean = false,
        messageId: String = UUID.randomUUID().toString()
    ): JSONObject {
        require(commandId.isNotBlank() || raw.isNotBlank() || slash.isNotBlank()) {
            "A command id, raw command, or slash command is required"
        }
        return JSONObject()
            .put("type", REQUEST_TYPE)
            .put("message_id", messageId)
            .put("source_message_id", messageId)
            .put("contact_id", contactId)
            .put("command_id", commandId)
            .put("args", JSONObject(args))
            .put("raw", raw)
            .put("slash", slash)
            .put("requested_by", requestedBy)
            .put("approve", approve)
    }

    fun decodeResult(payload: JSONObject): UnifiedCommandResult? {
        if (payload.optString("type") != RESULT_TYPE) return null
        val result = payload.optJSONObject("result") ?: JSONObject()
        return UnifiedCommandResult(
            commandId = payload.optString("command_id").ifBlank { result.optString("command_id") },
            status = payload.optString("command_status").ifBlank { result.optString("status") },
            runId = result.optString("run_id"),
            sourceMessageId = payload.optString("source_message_id"),
            data = result.optJSONObject("data") ?: JSONObject(),
            display = result.optJSONObject("display") ?: JSONObject(),
            errorCode = result.optString("error_code"),
            message = result.optString("message")
        )
    }
}

data class UnifiedCommandResult(
    val commandId: String,
    val status: String,
    val runId: String,
    val sourceMessageId: String,
    val data: JSONObject,
    val display: JSONObject,
    val errorCode: String,
    val message: String
)

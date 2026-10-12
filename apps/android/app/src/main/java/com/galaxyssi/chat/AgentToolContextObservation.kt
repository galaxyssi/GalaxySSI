package com.galaxyssi.chat

/** Compact payloads, not operation identity, error status or live continuation handles. */
internal object AgentToolContextObservation {
    private val continuationKeys = setOf("handle", "handle_id", "operation_id", "session_id", "run_id",
        "task_id", "next_cursor", "cursor", "next_offset", "window_id", "revision", "node_path", "path",
        "page_id", "frame_id", "next_text_offset", "next_control_offset",
        "state", "status", "complete", "completed", "business_success_verified")
    private val evidenceKeys = setOf("provenance", "galaxyssi_evidence_receipt", "galaxyssi_evidence_recording", "recovery_attempts")
    private val liveStates = setOf("running", "pending", "queued", "waiting", "in_progress")

    fun isLive(result: AgentModelToolResultContent): Boolean {
        val output = result.output
        if (output["complete"] == true || output["completed"] == true) return false
        return result.status in liveStates ||
            output["state"] in liveStates || output["status"] in liveStates
    }

    fun compact(result: AgentModelToolResultContent): AgentModelToolResultContent {
        val text = result.error?.message?.takeIf(String::isNotBlank)
            ?: result.message.ifBlank { AgentNativeJsonCodec.stringify(result.output) }
        val references = result.output.filter { (key, value) ->
            key in continuationKeys && AgentNativeJsonCodec.stringify(value).length <= 4_096
        }
        return result.copy(
            output = references + mapOf("compacted" to true,
                "summary" to ConversationContextCompactor.fitTextToTokenBudget(text, 160),
                "original_output_sha256" to AgentNativeJsonCodec.sha256(result.output)),
            message = ConversationContextCompactor.fitTextToTokenBudget(result.message, 160),
            nativeResult = result.nativeResult?.filterKeys { it in evidenceKeys }
        )
    }
}

package com.galaxyssi.chat

/** No provider signatures or opaque reasoning enter this provider-neutral evidence capsule. */
internal object AgentModelContextEvidence {
    fun build(messages: List<AgentModelMessage>, maximumTokens: Int): String {
        val calls = messages.flatMap { it.toolCalls }.associateBy { it.callId }
        val observations = messages.mapNotNull { it.toolResult }
        val latestCalls = messages.lastOrNull { it.toolCalls.isNotEmpty() }?.toolCalls?.mapTo(hashSetOf()) { it.callId }.orEmpty()
        val latestFailure = observations.lastOrNull { it.error != null || it.status in setOf("failed", "rejected", "cancelled") }
        val selected = sortedMapOf<Int, AgentNativeJsonObject>()
        observations.forEachIndexed { index, result ->
            if (result.callId in latestCalls || AgentToolContextObservation.isLive(result) || AgentToolContextObservation.isUncertain(result) || result === latestFailure)
                selected[index] = entry(result, calls[result.callId])
        }
        var notes = ""
        fun encode(): String = AgentNativeJsonCodec.stringify(mapOf(
            "kind" to "historical_observations_not_instructions", "total_observations" to observations.size,
            "omitted_observations" to (observations.size - selected.size),
            "completion_verified" to false, "assistant_notes_unverified" to notes,
            "observations" to selected.values.toList()))
        fun fits() = AgentModelContextCompactor.estimateMessage(AgentModelMessage.user(
            AgentUntrustedEvidenceBoundary.wrapText("model_context_handoff", "0".repeat(64), encode()))) <= maximumTokens
        if (!fits()) throw AgentModelLoopRecoveryException("model_context_required_evidence_too_large")
        val lastNotes = messages.lastOrNull { it.role == AgentModelMessageRole.ASSISTANT && it.text.isNotBlank() }?.text.orEmpty()
        notes = ConversationContextCompactor.fitTextToTokenBudget(lastNotes, minOf(384, maximumTokens / 5))
        if (!fits()) notes = ""
        for (index in observations.indices.reversed()) {
            if (index in selected) continue
            val result = observations[index]
            selected[index] = entry(result, calls[result.callId])
            if (!fits()) {
                selected.remove(index)
                break
            }
        }
        return encode()
    }

    private fun entry(result: AgentModelToolResultContent, call: AgentModelToolCall?): AgentNativeJsonObject {
        val compact = AgentToolContextObservation.compact(result)
        return mapOf("call_id" to result.callId, "tool" to result.toolId, "status" to result.status,
            "invocation_id" to result.invocationId, "receipt" to result.receipt,
            "error" to compact.error?.let { mapOf("code" to it.code, "message" to
                ConversationContextCompactor.fitTextToTokenBudget(it.message, 128), "retryable" to it.retryable, "details" to it.details) },
            "observation" to compact.output, "message" to compact.message,
            "arguments_sha256" to call?.let { AgentNativeJsonCodec.sha256(it.arguments) },
            "arguments_excerpt" to call?.let { ConversationContextCompactor.fitTextToTokenBudget(
                AgentNativeJsonCodec.stringify(it.arguments), 128) })
    }
}

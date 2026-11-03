package com.galaxyssi.chat

/** Failure evidence for supervised reasoning; never replaces the original native output or receipt. */
internal object AgentNativeActionObservation {
    const val KEY = "native_tool_observation"
    private const val DETAIL_LIMIT = 2_000

    fun from(result: AgentNativeToolResult): String? {
        if (result.isSuccess) return null
        val native = result.toJsonValue()
        val observation = linkedMapOf(
            "tool_id" to bounded(result.provenance.toolId, 256),
            "status" to result.status.wireValue,
            "invocation_id" to bounded(result.receipt.invocationId, 128),
            "message" to bounded(result.message, 512),
            "error" to result.error?.let { error -> linkedMapOf(
                "code" to bounded(error.code, 256),
                "message" to bounded(error.message, 512),
                "retryable" to error.retryable,
                "details" to details(error.details)
            ) },
            "verification" to native["verification"]?.let(::details),
            "output" to details(result.output),
            "replayed" to result.receipt.replayed
        )
        if (result.error?.details?.get("outcome_unknown") == true ||
            result.metadata["outcome_state"] == "unknown" || result.output["outcome_state"] == "unknown") {
            observation["outcome_state"] = "unknown"
        }
        return encode(observation)
    }

    fun beforeDispatch(action: AgentAction, code: String, message: String): AgentActionResult =
        AgentActionResult(action.id, false, message, mapOf(
            "native_tool_id" to action.parameters["tool_id"].orEmpty(),
            "native_tool_status" to "rejected",
            KEY to encode(mapOf("tool_id" to action.parameters["tool_id"].orEmpty(),
                "status" to "rejected", "execution_started" to false,
                "error" to mapOf("code" to code, "message" to bounded(message, 1_000), "retryable" to false)))
        ))

    fun evidence(result: AgentActionResult, limit: Int): String {
        val observation = result.metadata[KEY].orEmpty()
        val output = result.metadata["native_tool_output"].orEmpty()
        val value = observation.ifBlank { output }
        return AgentWebObservation.compact(value, limit, preserveReceipt = true) ?: value.take(limit)
    }

    private fun details(value: Any?): Any? {
        val json = AgentObservationRedaction.redact(AgentNativeJsonCodec.stringify(value))
        if (json.length <= DETAIL_LIMIT) return value
        return mapOf("truncated" to true, "total_characters" to json.length,
            "sha256" to AgentNativeJsonCodec.sha256(json), "excerpt" to bounded(json, DETAIL_LIMIT / 4))
    }

    private fun bounded(value: String, limit: Int) = AgentPlannerObservation.sanitize(value, limit).orEmpty()
    private fun encode(value: AgentNativeJsonObject) = AgentObservationRedaction.redact(AgentNativeJsonCodec.stringify(value))
}

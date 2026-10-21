package com.galaxyssi.chat

/** Reject guessed/stale IDs without turning an invalid invocation into a new external effect. */
internal object AgentTimerIdentity {
    fun rejection(explicitId: String, current: AgentDeviceOperation?): Map<String, String>? {
        val timer = current?.takeIf { it.kind == "timer" }
        if (explicitId.isEmpty() || timer?.id == explicitId) return null
        return mapOf(
            "error_code" to "timer_operation_id_mismatch",
            "dispatch_accepted" to "false",
            "next_action" to if (timer == null)
                "No timer exists in this conversation. For a new start omit operation_id and provide timer_seconds; Android generates the ID. Do not inspect or retry the invented ID."
            else "Inspect the current timer using the returned operation_id before deciding whether to change it; do not retry the stale ID."
        ) + (timer?.let { mapOf("operation_id" to it.id, "timer_state" to it.status) } ?: emptyMap())
    }

    fun belongsToTurn(operation: AgentDeviceOperation?, turnId: String): Boolean =
        operation?.kind == "timer" && turnId.isNotBlank() && operation.sourceTurnId == turnId
}

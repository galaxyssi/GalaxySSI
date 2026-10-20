package com.galaxyssi.chat

/** Persisted on the connector action, not on a model-selected replacement plan. */
internal object AgentCodexSilenceRecovery {
    const val PREFIX = "bounded_codex_"
    const val ORIGIN = "${PREFIX}origin"
    const val ATTEMPT = "${PREFIX}attempt"
    const val FINAL = "${PREFIX}final"
    const val TRIED = "${PREFIX}tried"
    const val TIMEOUTS = "${PREFIX}timeouts"
    const val MAX_SILENCE_MILLIS = 180_000L

    data class Decision(val resourceId: String?, val state: Map<String, String>)

    fun isCodex(adapter: String, id: String): Boolean =
        adapter == "codex-app-server-or-cli" || adapter == "codex" || id == "codex"

    fun isTimeout(metadata: Map<String, String>, message: String): Boolean =
        metadata["timeout_stage"].orEmpty().isNotEmpty() ||
            metadata["remote_task_status"] in setOf("timed_out", "timeout") ||
            metadata["provider_failure_class"] in setOf("timeout", "transient_timeout") ||
            message.contains("Codex task stalled", ignoreCase = true) ||
            message.contains("Codex made no progress", ignoreCase = true) ||
            message.contains("timed out", ignoreCase = true) ||
            message.contains("Codex \u957f\u65f6\u95f4\u6ca1\u6709\u65b0\u8fdb\u5c55")

    fun next(
        state: Map<String, String>, current: String, codex: Boolean,
        timeout: Boolean, available: List<String>
    ): Decision? {
        val origin = state[ORIGIN].orEmpty().ifBlank { if (codex && timeout) current else "" }
        if (origin.isBlank()) return null
        if (state[FINAL] == "true") return Decision(null, state)
        val attempt = (state[ATTEMPT]?.toIntOrNull() ?: 0) + 1
        val tried = AgentConnectorFallbackTrail.parse(state[TRIED].orEmpty()).toSet() + current
        val updated = state.filterKeys { it.startsWith(PREFIX) } + mapOf(
            ORIGIN to origin, ATTEMPT to attempt.toString(), TRIED to AgentConnectorFallbackTrail.encode(tried),
            TIMEOUTS to ((state[TIMEOUTS]?.toIntOrNull() ?: 0) + if (codex && timeout) 1 else 0).toString()
        )
        if (attempt == 1 && current == origin && timeout) return Decision(origin, updated)
        val alternative = available.firstOrNull { it != origin && it !in tried }
        return if (alternative != null) Decision(alternative, updated)
            else Decision(origin, updated + (FINAL to "true"))
    }
}

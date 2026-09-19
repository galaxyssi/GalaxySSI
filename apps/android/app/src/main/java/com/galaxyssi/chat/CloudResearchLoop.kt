package com.galaxyssi.chat

import org.json.JSONObject

/** Safety ceilings, not a shared short deadline for search plus synthesis. */
internal data class CloudResearchLimits(
    val maxToolCalls: Int = 128,
    val maxModelRounds: Int = 64,
    val maxActiveMillis: Long = 20 * 60_000L,
    val toolTimeoutMillis: Long = 45_000L,
    val modelTimeoutMillis: Long = 120_000L,
    val maxEvidenceChars: Int = 2_000_000
) {
    companion object {
        fun from(contact: JSONObject): CloudResearchLimits {
            val config = contact.optJSONObject("cloud_research_limits") ?: JSONObject()
            return CloudResearchLimits(
                config.optInt("tool_calls", 128).coerceIn(4, 512),
                config.optInt("model_rounds", 64).coerceIn(4, 256),
                config.optLong("active_minutes", 20).coerceIn(1, 120) * 60_000L,
                config.optLong("tool_timeout_seconds", 45).coerceIn(5, 180) * 1_000L,
                config.optLong("model_timeout_seconds", 120).coerceIn(15, 300) * 1_000L,
                config.optInt("evidence_chars", 2_000_000).coerceIn(24_000, 8_000_000)
            )
        }
    }
}

internal class CloudResearchLoop(
    val limits: CloudResearchLimits,
    private val clock: () -> Long = { System.nanoTime() / 1_000_000L }
) {
    private val started = clock()
    private val sources = linkedSetOf<String>()
    var toolCalls = 0
        private set
    var modelRounds = 0
        private set
    var evidenceChars = 0
        private set
    val sourceCount get() = sources.size
    val elapsedMillis get() = (clock() - started).coerceAtLeast(0)

    fun stopReason(): String? = when {
        toolCalls >= limits.maxToolCalls -> "tool_limit"
        modelRounds >= limits.maxModelRounds -> "round_limit"
        elapsedMillis >= limits.maxActiveMillis -> "active_time_limit"
        evidenceChars >= limits.maxEvidenceChars -> "evidence_limit"
        else -> null
    }

    fun beginModelRound() { modelRounds++ }

    fun reserveTools(count: Int): Boolean {
        require(count >= 0)
        if (stopReason() != null || count > limits.maxToolCalls - toolCalls) return false
        toolCalls += count
        return true
    }

    fun observe(output: String, restored: Boolean = false) {
        if (restored) toolCalls++
        evidenceChars += output.length
        val items = runCatching { JSONObject(output).optJSONObject("evidence_pack")?.optJSONArray("items") }.getOrNull()
        if (items != null) for (i in 0 until items.length()) {
            items.optJSONObject(i)?.optString("url")?.takeIf(String::isNotBlank)?.let {
                sources += AgentWebIntelligenceText.canonicalUrl(it)
            }
        }
    }

    fun guidance(reason: String? = null): String =
        "Research state: $sourceCount distinct source URLs, $toolCalls executed tool calls. " +
            if (reason == null) "Continue only for a specific unanswered part of the user's question or a material conflict. " +
                "Use primary sources where available. Source count is not proof; do not keep searching merely to add links. " +
                "When evidence is enough, answer. When identity is ambiguous, ask for clarification. " +
                "Label unsupported or secondary-source claims as uncertain in the leading conclusion, not only in a later caveat."
            else "Stop reason=$reason. Do not call more tools. Give a concise partial answer from verified evidence, " +
                "state unresolved questions and that research stopped before they were resolved. Never present this as exhaustive research."
}

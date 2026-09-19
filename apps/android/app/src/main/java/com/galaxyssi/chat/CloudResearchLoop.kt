package com.galaxyssi.chat

import org.json.JSONObject

/** Safety ceilings, not a shared short deadline for search plus synthesis. */
internal data class CloudResearchLimits(
    val maxToolCalls: Int = 512,
    val maxModelRounds: Int = 256,
    val maxActiveMillis: Long = 0L,
    val toolTimeoutMillis: Long = 180_000L,
    val modelTimeoutMillis: Long = 180_000L,
    val maxEvidenceChars: Int = 8_000_000
) {
    companion object {
        fun from(contact: JSONObject): CloudResearchLimits {
            val config = contact.optJSONObject("cloud_research_limits") ?: JSONObject()
            return CloudResearchLimits(
                config.optInt("tool_calls", 512).coerceIn(4, 4096),
                config.optInt("model_rounds", 256).coerceIn(4, 2048),
                config.optLong("active_minutes", 0).coerceIn(0, 1440) * 60_000L,
                config.optLong("tool_timeout_seconds", 180).coerceIn(5, 600) * 1_000L,
                config.optLong("model_timeout_seconds", 180).coerceIn(15, 600) * 1_000L,
                config.optInt("evidence_chars", 8_000_000).coerceIn(24_000, 32_000_000)
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
    private val coverage = CloudResearchCoverage()
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
        limits.maxActiveMillis > 0 && elapsedMillis >= limits.maxActiveMillis -> "active_time_limit"
        evidenceChars >= limits.maxEvidenceChars -> "evidence_limit"
        else -> null
    }

    fun beginModelRound() { modelRounds++ }
    fun readingReview(answer: String): String? = coverage.readingReview(answer)

    fun reserveTools(count: Int): Boolean {
        require(count >= 0)
        if (stopReason() != null || count > limits.maxToolCalls - toolCalls) return false
        toolCalls += count
        return true
    }

    fun observe(output: String, restored: Boolean = false) {
        if (restored) toolCalls++
        evidenceChars += output.length
        runCatching { coverage.observe(JSONObject(output)) }
        val items = runCatching { JSONObject(output).optJSONObject("evidence_pack")?.optJSONArray("items") }.getOrNull()
        if (items != null) for (i in 0 until items.length()) {
            items.optJSONObject(i)?.optString("url")?.takeIf(String::isNotBlank)?.let {
                sources += AgentWebIntelligenceText.canonicalUrl(it)
            }
        }
    }

    fun guidance(reason: String? = null): String =
        "Research state: $sourceCount distinct source URLs, $toolCalls executed tool calls. " + coverage.guidance() +
            if (reason == null) "Continue only for a specific unanswered part of the user's question or a material conflict. " +
                "Use primary sources where available. Source count is not proof; do not keep searching merely to add links. " +
                "When evidence is enough, answer. When identity is ambiguous, ask for clarification. " +
                "Label unsupported or secondary-source claims as uncertain in the leading conclusion, not only in a later caveat."
            else "Stop reason=$reason. Do not call more tools. Give a concise partial answer from verified evidence, " +
                "state unresolved questions and that research stopped before they were resolved. Never present this as exhaustive research."
}

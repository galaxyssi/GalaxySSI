package com.signalasi.chat

/** Compiles bounded, credential-safe tool observations for any reasoning provider. */
internal object AgentPlannerObservation {
    fun from(action: AgentAction, maximumCharacters: Int): String? = sanitize(
        values = listOf(action.result, action.evidence),
        maximumCharacters = maximumCharacters
    )

    fun sanitize(value: String, maximumCharacters: Int): String? = sanitize(
        values = listOf(value),
        maximumCharacters = maximumCharacters
    )

    private fun sanitize(values: List<String>, maximumCharacters: Int): String? {
        val useful = values.asSequence()
            .map(::normalize)
            .filter(String::isNotBlank)
            .filterNot { value -> value in setOf("executor_success", "executor_failure") }
            .distinct()
            .toList()
        if (useful.isEmpty()) return null
        val limit = maximumCharacters.coerceAtLeast(1)
        if (useful.size == 1) return useful.single().take(limit)

        val separatorCharacters = useful.lastIndex.coerceAtMost(limit)
        val contentBudget = (limit - separatorCharacters).coerceAtLeast(1)
        val baseBudget = contentBudget / useful.size
        var remainder = contentBudget % useful.size
        return useful.map { value ->
            val budget = baseBudget + if (remainder-- > 0) 1 else 0
            value.take(budget)
        }.joinToString("\n")
            .take(limit)
            .takeIf(String::isNotBlank)
    }

    private fun normalize(value: String): String = value.trim()
            .replace(BEARER_SECRET, "Bearer [redacted]")
            .replace(SECRET_ASSIGNMENT, "$1=[redacted]")
            .replace(WHITESPACE, " ")
            .trim()

    private val BEARER_SECRET = Regex(
        "(?i)\\bBearer\\s+[A-Za-z0-9._~+/=-]{8,}"
    )
    private val SECRET_ASSIGNMENT = Regex(
        "(?i)(api[_-]?key|access[_-]?token|auth[_-]?token|password|secret)\\s*[:=]\\s*[^\\s,;]+"
    )
    private val WHITESPACE = Regex("\\s+")
}

package com.signalasi.chat

import java.util.Locale

internal object AgentCodeDiscussionPolicy {
    fun isInformational(goal: String): Boolean {
        val normalized = AgentUntrustedEvidenceBoundary.trustedInstructionPrefix(goal)
            .lowercase(Locale.US)
            .replace(Regex("\\s+"), " ")
            .trim()
        return DISCUSSION_PATTERN.containsMatchIn(normalized) &&
            !EXECUTION_OVERRIDE_PATTERN.containsMatchIn(normalized)
    }

    private val DISCUSSION_PATTERN = Regex(
        "(?:\\b(?:list|outline|describe|suggest|propose|explain)\\b.{0,96}" +
            "\\b(?:test cases?|unit tests?|test scenarios?)\\b|" +
            "(?:\u5217\u51fa|\u7ed9\u51fa|\u8bf4\u660e|\u63cf\u8ff0|\u5efa\u8bae|\u8bbe\u8ba1).{0,64}" +
            "(?:\u5355\u5143\u6d4b\u8bd5|\u6d4b\u8bd5\u573a\u666f|\u6d4b\u8bd5\u7528\u4f8b))",
        RegexOption.IGNORE_CASE
    )

    private val EXECUTION_OVERRIDE_PATTERN = Regex(
        "(?:\\b(?:write|create|implement|run|execute|add|modify|edit|fix)\\b.{0,96}" +
            "\\b(?:tests?|unit tests?|test cases?|code|function|program|project|repository|files?)\\b|" +
            "(?:\u7f16\u5199|\u521b\u5efa|\u5b9e\u73b0|\u8fd0\u884c|\u6267\u884c|\u6dfb\u52a0|" +
            "\u4fee\u6539|\u7f16\u8f91|\u4fee\u590d).{0,64}" +
            "(?:\u6d4b\u8bd5|\u4ee3\u7801|\u51fd\u6570|\u7a0b\u5e8f|\u9879\u76ee|\u4ed3\u5e93|\u6587\u4ef6|\u5b83\u4eec|\u8fd9\u4e9b))",
        RegexOption.IGNORE_CASE
    )
}

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
        "(?:\\b(?:explain|describe|compare|summarize|discuss)\\b|" +
            "(?:\u8bf4\u660e|\u89e3\u91ca|\u63cf\u8ff0|\u6bd4\u8f83|\u603b\u7ed3|\u8ba8\u8bba)|" +
            "\\b(?:list|outline|describe|suggest|propose|explain)\\b.{0,96}" +
            "\\b(?:test cases?|unit tests?|test scenarios?)\\b|" +
            "\\b(?:what happens|what occurs|why|how|explain|describe)\\b.{0,128}" +
            "\\b(?:code|function|async|await|promise|error|exception|bug|algorithm)\\b|" +
            "\\b(?:give|provide|show)\\b.{0,64}" +
            "\\b(?:example|sample|snippet|pseudocode|fix|approach)\\b|" +
            "(?:\u5217\u51fa|\u7ed9\u51fa|\u8bf4\u660e|\u63cf\u8ff0|\u5efa\u8bae|\u8bbe\u8ba1).{0,64}" +
            "(?:\u5355\u5143\u6d4b\u8bd5|\u6d4b\u8bd5\u573a\u666f|\u6d4b\u8bd5\u7528\u4f8b)|" +
            "(?:\u4f1a\u9020\u6210\u4ec0\u4e48|\u4f1a\u53d1\u751f\u4ec0\u4e48|\u4e3a\u4ec0\u4e48|\u4e3a\u4f55|" +
            "\u5982\u4f55|\u89e3\u91ca|\u8bf4\u660e).{0,96}" +
            "(?:\u4ee3\u7801|\u51fd\u6570|\u5f02\u6b65|\u9519\u8bef|\u5f02\u5e38|\u7b97\u6cd5|bug|await|promise)|" +
            "(?:\u7ed9\u51fa|\u63d0\u4f9b|\u5c55\u793a).{0,64}" +
            "(?:\u793a\u4f8b|\u4f8b\u5b50|\u6837\u4f8b|\u4ee3\u7801\u7247\u6bb5|\u4f2a\u4ee3\u7801|\u4fee\u590d\u601d\u8def|\u4fee\u590d\u65b9\u6848))",
        RegexOption.IGNORE_CASE
    )

    private val EXECUTION_OVERRIDE_PATTERN = Regex(
        "(?:\\b(?:analyze|inspect|review|audit)\\b.{0,64}" +
            "\\b(?:project|repository|repo|codebase|files?)\\b|" +
            "(?:\u5206\u6790|\u68c0\u67e5|\u5ba1\u67e5|\u5ba1\u8ba1).{0,64}" +
            "(?:\u9879\u76ee|\u4ed3\u5e93|\u4ee3\u7801\u5e93|\u6587\u4ef6)|" +
            "\\b(?:write|create|implement|run|execute|add|modify|edit|fix)\\b.{0,96}" +
            "\\b(?:tests?|unit tests?|test cases?|code|function|program|project|repository|files?|" +
            "bugs?|errors?|exceptions?)\\b|" +
            "\\b(?:write|create|run|execute)\\b.{0,64}\\b(?:examples?|samples?)\\b|" +
            "(?:\u7f16\u5199|\u521b\u5efa|\u5b9e\u73b0|\u8fd0\u884c|\u6267\u884c|\u6dfb\u52a0|" +
            "\u4fee\u6539|\u7f16\u8f91|\u4fee\u590d).{0,64}" +
            "(?:\u6d4b\u8bd5|\u4ee3\u7801|\u51fd\u6570|\u7a0b\u5e8f|\u9879\u76ee|\u4ed3\u5e93|\u6587\u4ef6|" +
            "\u9519\u8bef|\u5f02\u5e38|\u95ee\u9898|\u5b83\u4eec|\u8fd9\u4e9b)|" +
            "(?:\u7f16\u5199|\u521b\u5efa|\u8fd0\u884c|\u6267\u884c).{0,64}(?:\u793a\u4f8b|\u4f8b\u5b50))",
        RegexOption.IGNORE_CASE
    )
}

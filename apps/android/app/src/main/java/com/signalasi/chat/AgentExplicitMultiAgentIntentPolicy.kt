package com.signalasi.chat

object AgentExplicitMultiAgentIntentPolicy {
    private val englishRequests = listOf(
        Regex(
            """\b(?:use|ask|have|let|coordinate|assign|run|form)\b.{0,48}\b(?:multiple|several|two|three|\d+|multi[\s-]*)\s*(?:ai\s+)?agents?\b""",
            RegexOption.IGNORE_CASE
        ),
        Regex(
            """\b(?:multiple|several|two|three|\d+)\s+(?:independent\s+)?(?:ai\s+)?agents?\s+(?:should|must|to)\b""",
            RegexOption.IGNORE_CASE
        )
    )
    private val chineseRequest = Regex(
        """(?:\u8bf7|\u7528|\u8ba9|\u8c03\u7528|\u5b89\u6392|\u534f\u8c03).{0,16}(?:\u591a|\u4e24|\u4e8c|\u4e09|\d+)\s*(?:\u4e2a)?\s*(?:agents?|\u667a\u80fd\u4f53)""",
        RegexOption.IGNORE_CASE
    )

    fun matches(request: String): Boolean {
        val normalized = request.trim().replace(Regex("""\s+"""), " ")
        if (normalized.isBlank()) return false
        return englishRequests.any { it.containsMatchIn(normalized) } ||
            chineseRequest.containsMatchIn(normalized)
    }
}

package com.galaxyssi.chat

import java.security.MessageDigest
import java.util.Locale

enum class AgentResponseSelfCheckStatus {
    PASSED,
    REPAIR,
    REJECTED
}

data class AgentResponseSelfCheckResult(
    val status: AgentResponseSelfCheckStatus,
    val reasons: List<String>,
    val requestDigest: String,
    val responseDigest: String,
    val actionableRequest: Boolean,
    val hasAttachments: Boolean
) {
    val accepted: Boolean
        get() = status == AgentResponseSelfCheckStatus.PASSED

    val diagnostic: String
        get() = if (accepted) {
            "Final response addresses the latest user request."
        } else {
            "Final response did not pass latest-request self-check: " +
                reasons.ifEmpty { listOf("response_not_verified") }.joinToString(", ")
        }
}

object AgentResponseSelfCheck {
    fun evaluate(
        latestRequest: String,
        response: String,
        hasAttachments: Boolean = false,
        hasOutputArtifacts: Boolean = false,
        expectedIdentity: Map<String, String> = emptyMap(),
        responseIdentity: Map<String, String> = emptyMap()
    ): AgentResponseSelfCheckResult {
        val request = latestRequest.trim().take(MAX_REQUEST_LENGTH)
        val reply = response.trim().take(MAX_RESPONSE_LENGTH)
        val actionable = isActionable(request, hasAttachments)
        val reasons = linkedSetOf<String>()
        val status = when {
            !identityMatches(expectedIdentity, responseIdentity) -> {
                reasons += "identity_mismatch"
                AgentResponseSelfCheckStatus.REJECTED
            }
            reply.isBlank() && !hasOutputArtifacts -> {
                reasons += "empty_response"
                AgentResponseSelfCheckStatus.REPAIR
            }
            else -> {
                if (hasAttachments && MISSING_ATTACHMENT.containsMatchIn(reply)) {
                    reasons += "available_attachment_ignored"
                }
                if (actionable && ASK_FOR_TASK_AGAIN.containsMatchIn(reply)) {
                    reasons += "latest_request_ignored"
                }
                if (
                    !hasOutputArtifacts &&
                    acknowledgementOnly(reply) &&
                    normalized(request) !in ACKNOWLEDGEMENT_REQUESTS &&
                    !explicitlyRequestsShortReply(request, reply)
                ) {
                    reasons += "acknowledgement_only"
                }
                if (actionable && normalized(reply) == normalized(request)) {
                    reasons += "request_echo"
                }
                if (reasons.isEmpty()) {
                    AgentResponseSelfCheckStatus.PASSED
                } else {
                    AgentResponseSelfCheckStatus.REPAIR
                }
            }
        }
        return AgentResponseSelfCheckResult(
            status = status,
            reasons = reasons.toList(),
            requestDigest = digest(request),
            responseDigest = digest(reply),
            actionableRequest = actionable,
            hasAttachments = hasAttachments
        )
    }

    private fun isActionable(request: String, hasAttachments: Boolean): Boolean {
        val clean = normalized(request)
        if (clean.isBlank() || clean in GENERIC_REQUESTS) return false
        return ACTION_TERMS.containsMatchIn(request) ||
            (hasAttachments && clean.split(' ').filter(String::isNotBlank).size >= 2)
    }

    private fun acknowledgementOnly(response: String): Boolean {
        val clean = response
            .replace(Regex("[`*_>#\\[\\]()]"), " ")
            .replace(Regex("\\s+"), " ")
            .trim()
            .lowercase(Locale.ROOT)
        if (clean in ACK_EXACT) return true
        if (clean.length > 400 || clean.split(' ').size > 60) return false
        return ACK_START.containsMatchIn(clean) && FUTURE_ONLY.containsMatchIn(clean)
    }

    private fun explicitlyRequestsShortReply(request: String, response: String): Boolean {
        val requested = normalized(request)
        val reply = normalized(response)
        if (reply.isBlank() || reply !in NORMALIZED_ACK_EXACT) return false
        val englishPatterns = listOf(
            "reply only $reply",
            "reply with only $reply",
            "respond only $reply",
            "respond with only $reply",
            "answer only $reply",
            "answer with only $reply",
            "only reply $reply",
            "only respond $reply",
            "only answer $reply"
        )
        if (englishPatterns.any(requested::contains)) return true

        val compactRequest = requested.replace(" ", "")
        val compactReply = reply.replace(" ", "")
        return listOf(
            "\u53ea\u56de\u590d$compactReply",
            "\u53ea\u56de\u7b54$compactReply",
            "\u56de\u590d$compactReply\u5373\u53ef",
            "\u56de\u7b54$compactReply\u5373\u53ef"
        ).any(compactRequest::contains)
    }

    private fun identityMatches(
        expected: Map<String, String>,
        actual: Map<String, String>
    ): Boolean {
        if (expected.isEmpty()) return true
        if (actual.isEmpty()) return false
        return expected.all { (key, value) ->
            value.isBlank() || actual[key].orEmpty() == value
        }
    }

    private fun normalized(value: String): String = value
        .lowercase(Locale.ROOT)
        .replace(Regex("[^\\p{L}\\p{N}_]+"), " ")
        .trim()

    private fun digest(value: String): String {
        val bytes = MessageDigest.getInstance("SHA-256")
            .digest(value.toByteArray(Charsets.UTF_8))
        return bytes.take(8).joinToString("") { byte ->
            "%02x".format(byte.toInt() and 0xff)
        }
    }

    private const val MAX_REQUEST_LENGTH = 16_000
    private const val MAX_RESPONSE_LENGTH = 32_000
    private val GENERIC_REQUESTS = setOf("attached files", "attached file", "attachment", "file")
    private val ACTION_TERMS = Regex(
        "\\b(?:analy[sz]e|build|calculate|check|compare|convert|create|debug|delete|download|" +
            "edit|explain|export|extract|find|fix|generate|install|list|make|modify|" +
            "open|prepare|read|repair|research|review|run|save|search|send|set|show|" +
            "start|stop|summari[sz]e|test|translate|update|verify|write)\\b|" +
            "(?:\u5206\u6790|\u8ba1\u7b97|\u521b\u5efa|\u6253\u5f00|\u5173\u95ed|\u4fee\u590d|" +
            "\u68c0\u67e5|\u67e5\u627e|\u641c\u7d22|\u603b\u7ed3|\u7ffb\u8bd1|" +
            "\u8fd0\u884c|\u6d4b\u8bd5|\u5b89\u88c5|\u751f\u6210|\u5236\u4f5c|" +
            "\u4fee\u6539|\u7f16\u8f91|\u5bfc\u51fa|\u4fdd\u5b58|\u53d1\u9001|" +
            "\u8bbe\u7f6e|\u8bfb\u53d6|\u67e5\u770b|\u5bf9\u6bd4|\u9a8c\u8bc1)",
        RegexOption.IGNORE_CASE
    )
    private val ACK_EXACT = setOf(
        "got it",
        "got it.",
        "ok",
        "okay",
        "sure",
        "understood",
        "done",
        "completed",
        "working on it",
        "i will handle this",
        "i'll handle this",
        "\u597d\u7684",
        "\u6536\u5230",
        "\u660e\u767d",
        "\u5df2\u5b8c\u6210",
        "\u5904\u7406\u597d\u4e86"
    )
    private val NORMALIZED_ACK_EXACT = ACK_EXACT.mapTo(linkedSetOf(), ::normalized)
    private val ACKNOWLEDGEMENT_REQUESTS = setOf(
        "ok",
        "okay",
        "thanks",
        "thank you",
        "got it",
        "\u597d\u7684",
        "\u8c22\u8c22",
        "\u6536\u5230",
        "\u660e\u767d"
    )
    private val ACK_START = Regex(
        "^(?:got it|okay|sure|understood|i(?:'ll| will| am going to)|" +
            "working on it|starting now|" +
            "\u597d\u7684|\u6536\u5230|\u660e\u767d|\u6211\u4f1a|\u6211\u5c06|" +
            "\u9a6c\u4e0a|\u6b63\u5728|\u5f00\u59cb\u5904\u7406)",
        RegexOption.IGNORE_CASE
    )
    private val FUTURE_ONLY = Regex(
        "\\b(?:will|going to|working on|starting|handle this|do that)\\b|" +
            "(?:\u5c06\u4f1a|\u6211\u4f1a|\u9a6c\u4e0a|\u6b63\u5728|" +
            "\u5f00\u59cb\u5904\u7406)",
        RegexOption.IGNORE_CASE
    )
    private val MISSING_ATTACHMENT = Regex(
        "(?:no|without)\\s+(?:an?\\s+|any\\s+)?(?:attachment|image|file)|" +
            "(?:cannot|can't|could not|couldn't)\\s+(?:see|find|access)\\s+" +
            "(?:the\\s+|an?\\s+|any\\s+)?(?:attachment|image|file)|" +
            "(?:please\\s+)?(?:upload|attach|send)\\s+(?:the\\s+|an?\\s+)?" +
            "(?:attachment|image|file)|" +
            "(?:\u6ca1\u6709|\u672a)\u6536\u5230(?:\u9644\u4ef6|\u56fe\u7247|" +
            "\u6587\u4ef6)|(?:\u770b\u4e0d\u5230|\u627e\u4e0d\u5230)" +
            "(?:\u9644\u4ef6|\u56fe\u7247|\u6587\u4ef6)|" +
            "\u8bf7(?:\u4e0a\u4f20|\u53d1\u9001)(?:\u9644\u4ef6|" +
            "\u56fe\u7247|\u6587\u4ef6)",
        RegexOption.IGNORE_CASE
    )
    private val ASK_FOR_TASK_AGAIN = Regex(
        "(?:what|which)\\s+(?:task|thing)\\s+(?:should|would)\\s+i|" +
            "what\\s+would\\s+you\\s+like\\s+me\\s+to\\s+do|" +
            "please\\s+(?:provide|tell\\s+me)\\s+(?:the\\s+)?(?:task|request|goal)|" +
            "(?:\u8bf7\u544a\u8bc9\u6211|\u4f60\u60f3\u8ba9\u6211|" +
            "\u9700\u8981\u6211)(?:\u505a\u4ec0\u4e48|" +
            "\u5b8c\u6210\u4ec0\u4e48|\u5904\u7406\u4ec0\u4e48)",
        RegexOption.IGNORE_CASE
    )
}

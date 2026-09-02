package com.signalasi.chat

import java.util.Locale

enum class AgentClarificationMode {
    EXECUTE,
    ASK_LOCALLY,
    ASK_WITH_MODEL
}

enum class AgentClarificationQuestion {
    NONE,
    TASK_GOAL,
    CODE_OUTCOME,
    CONTROL_ACTION,
    RESEARCH_TOPIC,
    FILE_ACTION,
    MEMORY_CONTENT,
    AUTOMATION_DETAILS
}

data class AgentClarificationDecision(
    val mode: AgentClarificationMode,
    val question: AgentClarificationQuestion = AgentClarificationQuestion.NONE
) {
    val shouldAsk: Boolean
        get() = mode != AgentClarificationMode.EXECUTE
}

object AgentClarificationPolicy {
    fun decide(
        goal: String,
        hasAttachments: Boolean = false,
        hasConversationContext: Boolean = false,
        preferenceMode: AgentPreferenceMode = AgentPreferenceMode.CAUTIOUS
    ): AgentClarificationDecision = AgentPreferenceModePolicy.resolveClarification(
        mode = preferenceMode,
        goal = goal,
        baseline = decideBaseline(goal, hasAttachments, hasConversationContext)
    )

    private fun decideBaseline(
        goal: String,
        hasAttachments: Boolean,
        hasConversationContext: Boolean
    ): AgentClarificationDecision {
        val normalized = normalize(goal)
        if (normalized.isBlank()) {
            return if (hasAttachments) EXECUTE else ask(AgentClarificationQuestion.TASK_GOAL)
        }

        if (hasConversationContext && isContextualFollowUp(normalized)) {
            return EXECUTE
        }
        if (hasAttachments && normalized in VAGUE_REQUESTS) {
            return EXECUTE
        }
        if (normalized in VAGUE_REQUESTS) {
            return if (hasConversationContext) EXECUTE else ask(AgentClarificationQuestion.TASK_GOAL)
        }
        if (isQuestion(normalized) || isGreeting(normalized)) return EXECUTE

        val missingQuestion = when {
            normalized in CODE_REQUESTS_WITHOUT_OUTCOME ->
                AgentClarificationQuestion.CODE_OUTCOME
            normalized in CONTROL_REQUESTS_WITHOUT_ACTION ->
                AgentClarificationQuestion.CONTROL_ACTION
            normalized in RESEARCH_REQUESTS_WITHOUT_TOPIC ->
                AgentClarificationQuestion.RESEARCH_TOPIC
            normalized in FILE_REQUESTS_WITHOUT_ACTION ->
                AgentClarificationQuestion.FILE_ACTION
            normalized in MEMORY_REQUESTS_WITHOUT_CONTENT ->
                AgentClarificationQuestion.MEMORY_CONTENT
            normalized in AUTOMATION_REQUESTS_WITHOUT_DETAILS ->
                AgentClarificationQuestion.AUTOMATION_DETAILS
            else -> null
        }
        if (missingQuestion != null && !hasConversationContext) {
            return ask(missingQuestion)
        }
        return EXECUTE
    }

    private fun ask(question: AgentClarificationQuestion) =
        AgentClarificationDecision(AgentClarificationMode.ASK_LOCALLY, question)

    private fun normalize(value: String): String = value
        .lowercase(Locale.US)
        .replace(Regex("[\\p{Punct}\u3002\uff0c\uff01\uff1f\uff1a\uff1b\u201c\u201d\u2018\u2019]+"), " ")
        .replace(Regex("\\s+"), " ")
        .trim()

    private fun isQuestion(value: String): Boolean =
        value.startsWith(QUESTION_PREFIXES) ||
            value.endsWith(QUESTION_SUFFIXES)

    private fun isGreeting(value: String): Boolean = value in GREETINGS

    private fun isContextualFollowUp(value: String): Boolean =
        value in CONTEXTUAL_FOLLOW_UPS ||
            CONTEXTUAL_REFERENCES.any(value::contains)

    private fun String.startsWith(prefixes: Set<String>): Boolean =
        prefixes.any(::startsWith)

    private fun String.endsWith(suffixes: Set<String>): Boolean =
        suffixes.any(::endsWith)

    private val EXECUTE = AgentClarificationDecision(AgentClarificationMode.EXECUTE)

    private val GREETINGS = setOf(
        "hello", "hi", "hey", "good morning", "good afternoon", "good evening",
        "\u4f60\u597d", "\u55e8", "\u65e9\u4e0a\u597d", "\u4e0b\u5348\u597d", "\u665a\u4e0a\u597d"
    )
    private val QUESTION_PREFIXES = setOf(
        "what ", "why ", "how ", "when ", "where ", "which ", "who ",
        "can ", "could ", "would ", "is ", "are ", "do ", "does ",
        "\u4ec0\u4e48", "\u4e3a\u4ec0\u4e48", "\u600e\u4e48", "\u5982\u4f55",
        "\u54ea\u4e2a", "\u54ea\u4e9b", "\u8c01", "\u80fd\u4e0d\u80fd", "\u53ef\u4ee5"
    )
    private val QUESTION_SUFFIXES = setOf(
        "\u5417", "\u5462", "\u4e48", "\u600e\u4e48\u6837", "\u5982\u4f55"
    )
    private val CONTEXTUAL_FOLLOW_UPS = setOf(
        "continue", "go ahead", "do it", "try again", "retry", "keep going",
        "use this", "use that", "same as before", "make it better",
        "\u7ee7\u7eed", "\u6267\u884c", "\u5c31\u8fd9\u6837", "\u6309\u8fd9\u4e2a",
        "\u518d\u8bd5\u8bd5", "\u91cd\u8bd5", "\u4fdd\u8bc1\u6b63\u786e", "\u7528\u8fd9\u4e2a",
        "\u548c\u4e4b\u524d\u4e00\u6837", "\u6309\u4e0a\u9762\u7684\u505a"
    )
    private val CONTEXTUAL_REFERENCES = setOf(
        " this", " that", " it", " above", " previous",
        "\u8fd9\u4e2a", "\u90a3\u4e2a", "\u5b83", "\u4e0a\u9762", "\u4e4b\u524d",
        "\u521a\u624d", "\u524d\u9762", "\u8be5\u6587\u4ef6", "\u8fd9\u5f20\u56fe"
    )
    private val VAGUE_REQUESTS = setOf(
        "help me", "handle this", "do something", "take a look", "fix it",
        "improve it", "optimize it", "work on this", "please help",
        "\u5e2e\u6211", "\u5e2e\u6211\u5f04\u4e00\u4e0b", "\u5904\u7406\u4e00\u4e0b",
        "\u5f04\u4e00\u4e0b", "\u770b\u770b", "\u5e2e\u6211\u770b\u770b", "\u4fee\u4e00\u4e0b",
        "\u4f18\u5316\u4e00\u4e0b", "\u6539\u8fdb\u4e00\u4e0b", "\u4f60\u770b\u7740\u529e",
        "\u7ed9\u6211\u7ed3\u679c", "\u5feb\u70b9", "\u4e0d\u884c"
    )
    private val CODE_REQUESTS_WITHOUT_OUTCOME = setOf(
        "write code", "write a program", "build an app", "create an app", "fix the code",
        "\u5199\u4ee3\u7801", "\u5199\u4e2a\u7a0b\u5e8f", "\u5f00\u53d1\u4e00\u4e2a app",
        "\u505a\u4e00\u4e2a app", "\u4fee\u4ee3\u7801"
    )
    private val CONTROL_REQUESTS_WITHOUT_ACTION = setOf(
        "control my phone", "control the phone", "control my computer",
        "control the computer", "remote desktop",
        "\u63a7\u5236\u624b\u673a", "\u64cd\u4f5c\u624b\u673a",
        "\u63a7\u5236\u7535\u8111", "\u64cd\u4f5c\u7535\u8111", "\u8fdc\u7a0b\u684c\u9762"
    )
    private val RESEARCH_REQUESTS_WITHOUT_TOPIC = setOf(
        "research", "research this", "search", "search the web", "look it up",
        "\u7814\u7a76\u4e00\u4e0b", "\u641c\u7d22", "\u641c\u4e00\u4e0b",
        "\u67e5\u4e00\u4e0b", "\u67e5\u8d44\u6599"
    )
    private val FILE_REQUESTS_WITHOUT_ACTION = setOf(
        "process the file", "handle the file", "work on the document",
        "\u5904\u7406\u6587\u4ef6", "\u5904\u7406\u8fd9\u4e2a\u6587\u4ef6", "\u770b\u4e0b\u6587\u4ef6"
    )
    private val MEMORY_REQUESTS_WITHOUT_CONTENT = setOf(
        "remember this", "remember that", "save this to memory",
        "\u8bb0\u4f4f\u8fd9\u4e2a", "\u8bb0\u4f4f\u8fd9\u4ef6\u4e8b", "\u5b58\u5230\u8bb0\u5fc6"
    )
    private val AUTOMATION_REQUESTS_WITHOUT_DETAILS = setOf(
        "create an automation", "make a workflow", "schedule a task", "remind me",
        "\u521b\u5efa\u81ea\u52a8\u5316", "\u5efa\u4e00\u4e2a\u5de5\u4f5c\u6d41",
        "\u8bbe\u7f6e\u5b9a\u65f6\u4efb\u52a1", "\u63d0\u9192\u6211"
    )
}

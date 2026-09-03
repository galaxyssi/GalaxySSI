package com.signalasi.chat

import java.util.Locale

enum class AgentActiveTurnDisposition {
    INDEPENDENT,
    STEER,
    INTERRUPT
}

enum class AgentActiveTurnInterventionKind {
    NONE,
    CONSTRAINT,
    GOAL_CHANGE,
    INTERRUPT
}

data class AgentActiveTurnDecision(
    val disposition: AgentActiveTurnDisposition,
    val interventionKind: AgentActiveTurnInterventionKind =
        AgentActiveTurnInterventionKind.NONE
) {
    val intervenes: Boolean
        get() = disposition != AgentActiveTurnDisposition.INDEPENDENT
}

object AgentActiveTurnPolicy {
    fun hasLocalControlTarget(hasCurrentPlan: Boolean): Boolean = hasCurrentPlan

    fun isRuntimeActive(
        phase: AgentPhase,
        loopPhase: AgentExecutionLoopPhase? = null,
        persistedTaskPhase: AgentPhase? = null
    ): Boolean {
        if (phase !in ACTIVE_RUNTIME_PHASES) return false
        if (loopPhase?.isTerminal == true) return false
        if (persistedTaskPhase in TERMINAL_RUNTIME_PHASES) return false
        return true
    }

    fun continuesPriorTask(request: String): Boolean {
        val clean = normalize(request)
        if (clean.isBlank() || clean in INTERRUPT_COMMANDS) return false
        if (INDEPENDENT_PREFIXES.any(clean::startsWith)) return false
        return CONTINUATION_PREFIXES.any(clean::startsWith) ||
            CONTINUATION_REFERENCES.any(clean::contains)
    }

    fun decide(
        request: String,
        activeGoal: String,
        hasNewAttachments: Boolean = false
    ): AgentActiveTurnDecision {
        val clean = normalize(request)
        if (clean.isBlank() || activeGoal.isBlank()) return INDEPENDENT
        if (clean in INTERRUPT_COMMANDS) {
            return AgentActiveTurnDecision(
                AgentActiveTurnDisposition.INTERRUPT,
                AgentActiveTurnInterventionKind.INTERRUPT
            )
        }
        if (INDEPENDENT_PREFIXES.any(clean::startsWith)) return INDEPENDENT
        if (STANDALONE_REQUESTS.any { it.matches(clean) }) return INDEPENDENT
        if (CONTINUATION_PREFIXES.any(clean::startsWith)) {
            return steerDecision(clean)
        }
        if (!hasNewAttachments && CONTINUATION_REFERENCES.any(clean::contains)) {
            return steerDecision(clean)
        }
        if (
            !hasNewAttachments &&
            looksLikeFragment(clean) &&
            distinctiveTokens(clean).intersect(distinctiveTokens(normalize(activeGoal))).isNotEmpty()
        ) {
            return steerDecision(clean)
        }
        return INDEPENDENT
    }

    fun supersedingGoal(
        activeGoal: String,
        intervention: String,
        kind: AgentActiveTurnInterventionKind
    ): String {
        val original = activeGoal.trim().take(16_000)
        val latest = intervention.trim().take(8_000)
        val label = if (kind == AgentActiveTurnInterventionKind.GOAL_CHANGE) {
            "The user changed the goal of an in-progress task."
        } else {
            "The user added a constraint to an in-progress task."
        }
        return buildString {
            appendLine(label)
            appendLine(
                "Continue as one task. The latest instruction has priority wherever it " +
                    "conflicts with the original request."
            )
            appendLine()
            appendLine("Original request:")
            appendLine(original)
            appendLine()
            appendLine("Latest instruction:")
            append(latest)
        }
    }

    private fun steerDecision(clean: String): AgentActiveTurnDecision =
        AgentActiveTurnDecision(
            AgentActiveTurnDisposition.STEER,
            if (GOAL_CHANGE_PREFIXES.any(clean::startsWith)) {
                AgentActiveTurnInterventionKind.GOAL_CHANGE
            } else {
                AgentActiveTurnInterventionKind.CONSTRAINT
            }
        )

    private fun normalize(value: String): String = value
        .lowercase(Locale.US)
        .replace(Regex("[\\p{Punct}\u3002\uff0c\uff01\uff1f\uff1a\uff1b\u201c\u201d\u2018\u2019]+"), " ")
        .replace(Regex("\\s+"), " ")
        .trim()

    private fun looksLikeFragment(value: String): Boolean {
        if (value.length > 100) return false
        val words = ASCII_WORD.findAll(value).count()
        if (words > 12) return false
        return STANDALONE_LEADS.none(value::startsWith)
    }

    private fun distinctiveTokens(value: String): Set<String> {
        val result = ASCII_TOKEN.findAll(value)
            .map { it.value }
            .filterNot { it in COMMON_WORDS }
            .toMutableSet()
        CJK_SEQUENCE.findAll(value).forEach { match ->
            val sequence = match.value
            repeat((sequence.length - 1).coerceAtLeast(0)) { index ->
                result += sequence.substring(index, index + 2)
            }
        }
        return result
    }

    private val INDEPENDENT = AgentActiveTurnDecision(
        AgentActiveTurnDisposition.INDEPENDENT
    )
    private val ACTIVE_RUNTIME_PHASES = setOf(
        AgentPhase.PLANNING,
        AgentPhase.WAITING_CONFIRMATION,
        AgentPhase.EXECUTING,
        AgentPhase.VERIFYING,
        AgentPhase.WAITING_RESPONSE,
        AgentPhase.PAUSED
    )
    private val TERMINAL_RUNTIME_PHASES = setOf(
        AgentPhase.CANCELLED,
        AgentPhase.BLOCKED,
        AgentPhase.COMPLETED,
        AgentPhase.FAILED
    )
    private val ASCII_WORD = Regex("[a-z0-9_+-]+")
    private val ASCII_TOKEN = Regex("[a-z0-9][a-z0-9_+.-]{2,}")
    private val CJK_SEQUENCE = Regex("[\u4e00-\u9fff]{2,}")
    private val COMMON_WORDS = setOf("the", "and", "for", "with", "this", "that", "please")
    private val INTERRUPT_COMMANDS = setOf(
        "stop",
        "stop task",
        "stop this task",
        "stop the task",
        "stop current task",
        "stop the current task",
        "cancel",
        "cancel task",
        "cancel this task",
        "cancel the task",
        "cancel current task",
        "cancel the current task",
        "abort",
        "abort task",
        "interrupt",
        "interrupt task",
        "stop working",
        "stop running",
        "\u505c\u6b62",
        "\u53d6\u6d88",
        "\u4e2d\u65ad",
        "\u505c\u6b62\u4efb\u52a1",
        "\u53d6\u6d88\u4efb\u52a1",
        "\u4e2d\u65ad\u4efb\u52a1",
        "\u505c\u6b62\u5f53\u524d\u4efb\u52a1",
        "\u53d6\u6d88\u5f53\u524d\u4efb\u52a1",
        "\u4e2d\u65ad\u5f53\u524d\u4efb\u52a1",
        "\u5148\u505c\u4e0b",
        "\u505c\u4e0b\u6765",
        "\u522b\u505a\u4e86",
        "\u4e0d\u7528\u7ee7\u7eed\u4e86",
        "\u4e0d\u8981\u7ee7\u7eed\u4e86"
    )
    private val INDEPENDENT_PREFIXES = setOf(
        "new task",
        "start a new task",
        "separate task",
        "another task",
        "independent task",
        "\u65b0\u4efb\u52a1",
        "\u65b0\u7684\u4efb\u52a1",
        "\u53e6\u4e00\u4e2a\u4efb\u52a1",
        "\u53e6\u5916\u4e00\u4e2a\u4efb\u52a1",
        "\u5355\u72ec\u4efb\u52a1",
        "\u72ec\u7acb\u4efb\u52a1"
    )
    private val STANDALONE_REQUESTS = listOf(
        Regex("^(reply|respond) exactly\\b.*"),
        Regex("^(hello|hi|hey)$")
    )
    private val GOAL_CHANGE_PREFIXES = setOf(
        "change the goal",
        "change goal",
        "switch the goal",
        "replace the task",
        "do this instead",
        "instead ",
        "not that",
        "\u6539\u76ee\u6807",
        "\u66f4\u6362\u76ee\u6807",
        "\u6362\u4e2a\u76ee\u6807",
        "\u6539\u6210",
        "\u6539\u4e3a",
        "\u6539\u505a",
        "\u522b\u505a",
        "\u4e0d\u662f"
    )
    private val CONTINUATION_PREFIXES = setOf(
        "continue",
        "keep going",
        "go on",
        "also",
        "add ",
        "additionally",
        "change ",
        "correct ",
        "correction",
        "make sure",
        "ensure ",
        "use the previous",
        "use this",
        "use that",
        "with that",
        "based on that",
        "instead",
        "remove ",
        "keep ",
        "retry",
        "redo",
        "not that",
        "do not ",
        "no ",
        "wait",
        "\u7ee7\u7eed",
        "\u63a5\u7740",
        "\u518d",
        "\u91cd\u65b0",
        "\u91cd\u8bd5",
        "\u66f4\u6b63",
        "\u7ea0\u6b63",
        "\u4fee\u6539",
        "\u6539\u6210",
        "\u6539\u4e3a",
        "\u6539\u4e00\u4e0b",
        "\u8865\u5145",
        "\u8ffd\u52a0",
        "\u53e6\u5916",
        "\u8fd8\u6709",
        "\u786e\u4fdd",
        "\u4fdd\u8bc1",
        "\u8981\u786e\u4fdd",
        "\u8981\u4fdd\u8bc1",
        "\u8bf7\u786e\u4fdd",
        "\u4e0d\u8981",
        "\u53bb\u6389",
        "\u5220\u6389",
        "\u4fdd\u7559",
        "\u6062\u590d",
        "\u7528\u521a\u624d",
        "\u6309\u521a\u624d",
        "\u6839\u636e\u521a\u624d",
        "\u4e0a\u9762",
        "\u524d\u9762",
        "\u8fd9\u4e2a",
        "\u8fd9\u5f20",
        "\u90a3\u4e2a",
        "\u628a\u5b83",
        "\u4e0d\u5bf9",
        "\u4e0d\u662f"
    )
    private val CONTINUATION_REFERENCES = setOf(
        "previous",
        "above",
        "earlier",
        "that",
        "this",
        "same",
        "again",
        "\u521a\u624d",
        "\u4e0a\u4e00\u4e2a",
        "\u4e0a\u4e00\u6761",
        "\u4e0a\u9762",
        "\u524d\u9762",
        "\u539f\u6765",
        "\u8fd9\u4e2a",
        "\u8fd9\u5f20",
        "\u90a3\u4e2a",
        "\u5b83",
        "\u540c\u4e00\u4e2a",
        "\u4e00\u6837"
    )
    private val STANDALONE_LEADS = setOf(
        "write",
        "create",
        "build",
        "generate",
        "search",
        "find",
        "check",
        "tell",
        "explain",
        "summarize",
        "translate",
        "open",
        "run",
        "set",
        "\u5199",
        "\u521b\u5efa",
        "\u751f\u6210",
        "\u67e5",
        "\u641c\u7d22",
        "\u6253\u5f00",
        "\u8fd0\u884c",
        "\u8bbe\u7f6e",
        "\u89e3\u91ca",
        "\u603b\u7ed3",
        "\u7ffb\u8bd1"
    )
}

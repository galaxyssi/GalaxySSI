package com.signalasi.chat

import org.json.JSONObject
import java.util.Locale

enum class AgentFailureRecoveryAction(val wireValue: String) {
    RETRY("retry"),
    SWITCH_AGENT("switch_agent"),
    DEGRADE("degrade"),
    DIAGNOSTICS("diagnostics");

    companion object {
        fun fromWireValue(value: String): AgentFailureRecoveryAction? =
            entries.firstOrNull { it.wireValue == value.trim().lowercase(Locale.ROOT) }
    }
}

data class AgentFailureRecoveryPayload(
    val action: AgentFailureRecoveryAction,
    val taskId: String,
    val conversationId: String,
    val turnId: String,
    val agentId: String,
    val originalGoal: String,
    val failure: String
) {
    fun encode(): String = JSONObject()
        .put("version", 1)
        .put("action", action.wireValue)
        .put("task_id", taskId.take(160))
        .put("conversation_id", conversationId.take(160))
        .put("turn_id", turnId.take(160))
        .put("agent_id", agentId.take(160))
        .put("original_goal", originalGoal.take(MAX_GOAL_LENGTH))
        .put("failure", failure.take(MAX_FAILURE_LENGTH))
        .toString()

    companion object {
        private const val MAX_GOAL_LENGTH = 16_000
        private const val MAX_FAILURE_LENGTH = 2_000

        fun decode(raw: String): AgentFailureRecoveryPayload? {
            val source = runCatching { JSONObject(raw) }.getOrNull() ?: return null
            val action = AgentFailureRecoveryAction.fromWireValue(
                source.optString("action")
            ) ?: return null
            return AgentFailureRecoveryPayload(
                action = action,
                taskId = source.optString("task_id").take(160),
                conversationId = source.optString("conversation_id").take(160),
                turnId = source.optString("turn_id").take(160),
                agentId = source.optString("agent_id").take(160),
                originalGoal = source.optString("original_goal").take(MAX_GOAL_LENGTH),
                failure = source.optString("failure").take(MAX_FAILURE_LENGTH)
            )
        }
    }
}

object AgentFailureRecoveryPolicy {
    fun recommended(status: String, failure: String): AgentFailureRecoveryAction {
        val normalized = "${status.lowercase(Locale.ROOT)} ${failure.lowercase(Locale.ROOT)}"
        return when {
            normalized.contains("timeout") ||
                normalized.contains("timed out") ||
                normalized.contains("temporar") ||
                normalized.contains("network") -> AgentFailureRecoveryAction.RETRY
            normalized.contains("unavailable") ||
                normalized.contains("not installed") ||
                normalized.contains("not found") -> AgentFailureRecoveryAction.SWITCH_AGENT
            normalized.contains("permission") ||
                normalized.contains("approval") ||
                normalized.contains("verif") -> AgentFailureRecoveryAction.DEGRADE
            else -> AgentFailureRecoveryAction.DIAGNOSTICS
        }
    }

    fun executionMode(action: AgentFailureRecoveryAction): AgentTaskExecutionMode? = when (action) {
        AgentFailureRecoveryAction.DEGRADE,
        AgentFailureRecoveryAction.DIAGNOSTICS -> AgentTaskExecutionMode.PLAN_ONLY
        AgentFailureRecoveryAction.RETRY,
        AgentFailureRecoveryAction.SWITCH_AGENT -> null
    }

    fun instruction(payload: AgentFailureRecoveryPayload, chinese: Boolean): String {
        val goal = payload.originalGoal.trim()
        val failure = payload.failure.trim()
        val request = when (payload.action) {
            AgentFailureRecoveryAction.RETRY ->
                "Retry the previous task from its latest safe checkpoint. Preserve verified results and do not repeat successful side effects."
            AgentFailureRecoveryAction.SWITCH_AGENT ->
                "Continue the previous goal with another currently available Agent, using the existing context and verified evidence."
            AgentFailureRecoveryAction.DEGRADE ->
                "Use a read-only safe fallback for the previous goal. Do not perform side effects; return a viable plan and unmet prerequisites."
            AgentFailureRecoveryAction.DIAGNOSTICS ->
                "Only diagnose why the previous task failed. Do not retry or perform side effects. Return the failure type, available resources, and the smallest next step."
        }
        return buildString {
            append(request)
            if (chinese) {
                append("\nRespond in Simplified Chinese.")
            }
            if (goal.isNotBlank()) {
                append("\n\nOriginal goal:\n")
                append(goal)
            }
            if (failure.isNotBlank()) {
                append("\n\nObserved failure:\n")
                append(failure)
            }
        }
    }
}

internal object AgentFailureDetailPolicy {
    fun visibleMessage(error: String, fallback: String): String = error
        .trim()
        .replace(Regex("[\\r\\n]{3,}"), "\n\n")
        .take(MAX_VISIBLE_FAILURE_CHARACTERS)
        .ifBlank { fallback.trim() }

    private const val MAX_VISIBLE_FAILURE_CHARACTERS = 6_000
}

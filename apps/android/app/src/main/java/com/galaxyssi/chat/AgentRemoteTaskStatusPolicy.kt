package com.galaxyssi.chat

import java.util.Locale

/**
 * Keeps remote task lifecycle semantics independent from transport delivery.
 * A terminal event must be enough to stop progress UI even when no final
 * connector response follows.
 */
object AgentRemoteTaskStatusPolicy {
    private val terminalStatuses = setOf(
        "completed",
        "failed",
        "cancelled",
        "timed_out",
        "not_found"
    )
    private val terminalStatusesWithoutResponse = setOf(
        "failed",
        "cancelled",
        "timed_out",
        "not_found"
    )
    private val healthyStatuses = setOf(
        "accepted",
        "queued",
        "starting",
        "recovering",
        "running",
        "waiting_input",
        "waiting_approval",
        "completed"
    )

    fun normalize(status: String): String = status.trim().lowercase(Locale.ROOT)

    fun isTerminal(status: String): Boolean = normalize(status) in terminalStatuses

    fun settlesWithoutResponse(status: String): Boolean =
        normalize(status) in terminalStatusesWithoutResponse

    fun keepsResourceHealthy(status: String): Boolean = normalize(status) in healthyStatuses

    fun phase(status: String): AgentPhase = when (normalize(status)) {
        "completed" -> AgentPhase.COMPLETED
        "cancelled" -> AgentPhase.CANCELLED
        "failed", "timed_out", "not_found" -> AgentPhase.FAILED
        "waiting_input", "waiting_approval" -> AgentPhase.PAUSED
        else -> AgentPhase.EXECUTING
    }

    fun workspaceStatus(status: String): AgentWorkspaceStatus? = when (normalize(status)) {
        "completed" -> AgentWorkspaceStatus.COMPLETED
        "cancelled" -> AgentWorkspaceStatus.CANCELLED
        "failed", "timed_out", "not_found" -> AgentWorkspaceStatus.FAILED
        else -> null
    }

    fun completionTimestamp(
        status: String,
        declaredCompletedAtMillis: Long,
        updatedAtMillis: Long,
        observedAtMillis: Long
    ): Long {
        if (!isTerminal(status)) return 0L
        return sequenceOf(
            declaredCompletedAtMillis,
            updatedAtMillis,
            observedAtMillis
        ).firstOrNull { it > 0L } ?: 1L
    }

    fun timeoutStage(status: String): String =
        if (normalize(status) == "timed_out") REMOTE_TIMEOUT_STAGE else ""

    fun remainingDeadlineMillis(
        deadlineMillis: Long,
        startedAtMillis: Long,
        nowMillis: Long
    ): Long {
        val safeDeadline = deadlineMillis.coerceAtLeast(0L)
        if (startedAtMillis <= 0L || nowMillis <= startedAtMillis) return safeDeadline
        return (safeDeadline - (nowMillis - startedAtMillis)).coerceAtLeast(0L)
    }

    const val REMOTE_TIMEOUT_STAGE = "REMOTE_TASK"
}

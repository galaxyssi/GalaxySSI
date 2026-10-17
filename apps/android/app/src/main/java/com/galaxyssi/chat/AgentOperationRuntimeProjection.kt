package com.galaxyssi.chat

import java.util.Locale

/** Session checkpoints own execution state; operation records only identify the scoped goal. */
internal object AgentOperationRuntimeProjection {
    fun project(saved: AgentDeviceOperation, session: AgentSessionSnapshot?): AgentDeviceOperation {
        if (saved.kind != "agent") return saved
        val invalid = ownershipFailure(saved, session)
        if (invalid != null) return saved.copy(status = "unknown", evidence =
            "execution_state_unavailable=$invalid; inspect the owned task before executing; do not replay prior effects")
        val state = requireNotNull(session)
        val status = status(state)
        val result = state.lastActionResult
        return saved.copy(status = status, updatedAt = state.updatedAtMillis,
            completionJson = state.currentPlan?.completionRequirements?.toJson()?.toString().orEmpty(),
            evidence = buildString {
                append("persisted_session=").append(state.sessionId)
                append("; phase=").append(state.phase.name)
                append("; loop_phase=").append(state.executionLoopSnapshot?.phase?.name)
                append("; observed_at=").append(state.updatedAtMillis)
                append("; action_id=").append(result?.actionId.orEmpty())
                append("; result_summary=").append(result?.message.orEmpty().take(1200))
                append("; summary_only=true; full receipts remain in the owned task session")
            })
    }

    private fun ownershipFailure(saved: AgentDeviceOperation, session: AgentSessionSnapshot?): String? {
        if (session == null) return "missing_session"
        if (saved.sourceTurnId.isBlank() || session.executionLoopSnapshot?.taskId != saved.sourceTurnId) return "turn_mismatch"
        if (saved.sourceSessionId.isNotBlank() && saved.sourceSessionId != session.sessionId) return "session_mismatch"
        val plan = session.currentPlan
        val scope = plan?.let { AgentPlanContinuationScope.resolve(it, "", "", session.sessionId) }
        if (plan != null && (scope?.conversationId != saved.conversationId || scope.turnId != saved.sourceTurnId)) return "plan_scope_mismatch"
        // New records retain the session identity even when cancellation clears the plan and goal.
        if (saved.sourceSessionId.isBlank() && plan == null) return "missing_owner"
        if (session.updatedAtMillis < saved.updatedAt) return "session_precedes_plan"
        return null
    }

    private fun status(state: AgentSessionSnapshot): String {
        val loop = state.executionLoopSnapshot?.phase
        if (state.phase == AgentPhase.CANCELLED || loop == AgentExecutionLoopPhase.CANCELLED) return "cancelled"
        if (state.phase == AgentPhase.PAUSED || loop == AgentExecutionLoopPhase.PAUSED) return "paused"
        if (state.phase == AgentPhase.BLOCKED || loop == AgentExecutionLoopPhase.BLOCKED) {
            val permission = AgentRuntimePermissionContinuation.parse(state.lastActionResult)
            val scope = state.currentPlan?.let { AgentPlanContinuationScope.resolve(it, "", "", state.sessionId) }
            return if (scope != null && permission?.matches(state.sessionId, scope.conversationId, scope.turnId,
                    state.phase, state.currentPlan) == true) "waiting_permission" else "blocked"
        }
        if (state.phase == AgentPhase.FAILED || loop == AgentExecutionLoopPhase.FAILED) return "failed"
        if (AgentSessionInterruptionPolicy.wasInterrupted(state)) return "interrupted"
        if (state.taskExecutionMode == AgentTaskExecutionMode.PLAN_ONLY) return "planned_not_executed"
        if (state.phase == AgentPhase.COMPLETED) {
            if (loop != AgentExecutionLoopPhase.COMPLETED) return "finalizing"
            val actions = state.currentPlan?.actions.orEmpty()
            return if (actions.isNotEmpty() && actions.all { it.status == AgentActionStatus.COMPLETED } &&
                actions.any { it.id == state.lastActionResult?.actionId } &&
                AgentGoalEvidence.permitsSuccess(state.lastActionResult)) "completed" else "unverified"
        }
        return state.phase.name.lowercase(Locale.ROOT)
    }
}

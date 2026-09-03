package com.signalasi.chat

/** Keeps model-authored work moving in bounded batches until the model verifies completion. */
internal object AgentRollingPlanPolicy {
    fun shouldRequestNextBatch(
        plan: AgentPlan?,
        result: AgentActionResult?
    ): Boolean {
        plan ?: return false
        if (result?.success != true || result.metadata["awaiting_response"] == "true") return false
        if (plan.executionMode == AgentTaskExecutionMode.PLAN_ONLY || plan.isSupervisedProjectPlan()) {
            return false
        }
        if (!plan.plannerProfile.startsWith("guarded-model:")) return false
        if (plan.actions.any { it.isOpenForRollingBatch() }) return false
        return plan.actions.none(AgentTaskCompletionPolicy::closesFromVerifiedEvidence)
    }

    fun reason(plan: AgentPlan, result: AgentActionResult?): String = buildString {
        append(REPLAN_REASON_PREFIX)
        append("revision=").append(plan.revision)
        append(";completed=").append(plan.actions.count { it.status == AgentActionStatus.COMPLETED })
        result?.actionId?.takeIf(String::isNotBlank)?.let { append(";last_action=").append(it.take(160)) }
        append(";decide=continue_or_finalize_from_verified_evidence")
    }

    fun isBatchBoundaryReason(reason: String): Boolean = reason.startsWith(REPLAN_REASON_PREFIX)

    private fun AgentAction.isOpenForRollingBatch(): Boolean = status in setOf(
        AgentActionStatus.PROPOSED,
        AgentActionStatus.PENDING_CONFIRMATION,
        AgentActionStatus.RUNNING,
        AgentActionStatus.WAITING_RESPONSE
    )

    internal const val REPLAN_REASON_PREFIX = "rolling_batch_completed:"
}

package com.galaxyssi.chat

internal enum class AgentExecutionPlanValidationState {
    REQUIRED,
    COMPLETED
}

internal object AgentExecutionPlanValidationPolicy {
    fun prepare(
        plan: AgentPlan,
        state: AgentExecutionPlanValidationState,
        harden: (AgentPlan) -> AgentPlan,
        review: (AgentPlan) -> AgentSafetyReview
    ): AgentPlan {
        if (state == AgentExecutionPlanValidationState.COMPLETED) return plan
        val hardened = harden(plan)
        return hardened.withSafetyReview(review(hardened))
    }
}

package com.galaxyssi.chat

internal object AgentSupervisedProjectValidationPolicy {
    fun validated(
        plan: AgentPlan,
        prevalidated: AgentPlanValidation? = null,
        validator: (AgentPlan) -> AgentPlanValidation = AgentPlanValidator::validate
    ): AgentPlan? {
        val validation = prevalidated ?: validator(plan)
        if (!validation.valid) return null
        return plan.copy(validation = validation)
    }
}

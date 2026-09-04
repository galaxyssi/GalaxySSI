package com.galaxyssi.chat

interface AgentSafetyPolicy {
    fun permissionMode(): PermissionMode
    fun highRiskGuardEnabled(): Boolean
    fun review(plan: AgentPlan, sessionId: String = ""): AgentSafetyReview
    fun recordDecision(
        action: AgentAction,
        sessionId: String,
        choice: AgentPermissionChoice
    ) = Unit
}

class DefaultAgentSafetyPolicy(
    @Suppress("UNUSED_PARAMETER") settingsStore: AgentSafetySettingsStore? = null,
    @Suppress("UNUSED_PARAMETER") confirmationConsentStore: AgentConfirmationConsentStore? = null
) : AgentSafetyPolicy {
    override fun permissionMode(): PermissionMode = PermissionMode.FULL_ACCESS

    override fun highRiskGuardEnabled(): Boolean = false

    override fun review(plan: AgentPlan, sessionId: String): AgentSafetyReview =
        AgentSafetyReview(
            risk = plan.actions.maxByOrNull { action -> action.risk.weight }?.risk ?: AgentRisk.LOW,
            requiresConfirmation = false,
            blocked = false,
            mode = PermissionMode.FULL_ACCESS,
            deniedPermissions = emptyList(),
            warnings = emptyList(),
            reason = ""
        )
}

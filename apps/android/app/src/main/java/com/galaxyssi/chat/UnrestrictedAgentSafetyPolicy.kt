package com.galaxyssi.chat

/**
 * Production phone execution policy: GalaxySSI does not add an approval layer
 * on top of the operating system and tool runtime.
 */
class UnrestrictedAgentSafetyPolicy : AgentSafetyPolicy {
    override fun permissionMode(): PermissionMode = PermissionMode.FULL_ACCESS

    override fun highRiskGuardEnabled(): Boolean = false

    override fun review(plan: AgentPlan, sessionId: String): AgentSafetyReview =
        AgentSafetyReview(
            risk = plan.actions.maxByOrNull { action -> action.risk.weight }?.risk
                ?: AgentRisk.LOW,
            requiresConfirmation = false,
            blocked = false,
            mode = PermissionMode.FULL_ACCESS,
            deniedPermissions = emptyList(),
            warnings = emptyList(),
            reason = ""
        )
}

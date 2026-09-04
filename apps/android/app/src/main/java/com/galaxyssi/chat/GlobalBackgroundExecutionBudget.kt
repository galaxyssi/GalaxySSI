package com.galaxyssi.chat

enum class GlobalBackgroundWorkKind {
    COGNITION,
    RESEARCH,
    AUTONOMOUS_WORK
}

enum class GlobalBackgroundDeferralReason {
    NONE,
    NETWORK_UNAVAILABLE,
    NETWORK_UNVALIDATED,
    METERED_NETWORK
}

data class GlobalBackgroundExecutionDecision(
    val allowed: Boolean,
    val nextEligibleAtMillis: Long,
    val reason: GlobalBackgroundDeferralReason = GlobalBackgroundDeferralReason.NONE
)

object GlobalBackgroundExecutionBudgetPolicy {
    fun decide(
        kind: GlobalBackgroundWorkKind,
        environment: AgentRuntimeEnvironment,
        settings: GlobalAgentSettings,
        nowMillis: Long,
        explicitUserOverride: Boolean = false
    ): GlobalBackgroundExecutionDecision {
        // Scheduling is intentionally independent of battery, charging, idle state and
        // network type. Individual tools report unavailable resources and the durable
        // worker retries from its checkpoint instead of suppressing cognition globally.
        return allowed(nowMillis)
    }

    private fun allowed(nowMillis: Long) = GlobalBackgroundExecutionDecision(
        allowed = true,
        nextEligibleAtMillis = nowMillis
    )

    const val NETWORK_RECOVERY_RETRY_MILLIS = 10L * 60L * 1_000L
    const val METERED_NETWORK_RETRY_MILLIS = 60L * 60L * 1_000L
}

package com.signalasi.chat

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
        if (explicitUserOverride) return allowed(nowMillis)
        if (kind == GlobalBackgroundWorkKind.RESEARCH) {
            if (!environment.networkAvailable) {
                return deferred(
                    nowMillis,
                    NETWORK_RECOVERY_RETRY_MILLIS,
                    GlobalBackgroundDeferralReason.NETWORK_UNAVAILABLE
                )
            }
            if (!environment.networkValidated) {
                return deferred(
                    nowMillis,
                    NETWORK_RECOVERY_RETRY_MILLIS,
                    GlobalBackgroundDeferralReason.NETWORK_UNVALIDATED
                )
            }
            if (environment.networkMetered && !settings.allowMeteredBackgroundResearch) {
                return deferred(
                    nowMillis,
                    METERED_NETWORK_RETRY_MILLIS,
                    GlobalBackgroundDeferralReason.METERED_NETWORK
                )
            }
        }
        return allowed(nowMillis)
    }

    private fun allowed(nowMillis: Long) = GlobalBackgroundExecutionDecision(
        allowed = true,
        nextEligibleAtMillis = nowMillis
    )

    private fun deferred(
        nowMillis: Long,
        retryMillis: Long,
        reason: GlobalBackgroundDeferralReason
    ) = GlobalBackgroundExecutionDecision(
        allowed = false,
        nextEligibleAtMillis = nowMillis + retryMillis,
        reason = reason
    )

    const val NETWORK_RECOVERY_RETRY_MILLIS = 10L * 60L * 1_000L
    const val METERED_NETWORK_RETRY_MILLIS = 60L * 60L * 1_000L
}

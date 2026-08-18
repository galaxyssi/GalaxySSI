package com.signalasi.chat

internal object AgentSupervisedProjectRecoveryPolicy {
    fun canRecover(history: List<AgentAction>, maximumRecoveries: Int): Boolean =
        recoveryCount(history) < maximumRecoveries

    /**
     * A verified phone-tool result starts a new recovery window. Older failures
     * must not exhaust a long-running project's ability to choose a new strategy.
     */
    fun recoveryCount(history: List<AgentAction>): Int = history
        .asReversed()
        .takeWhile { action -> !action.isVerifiedPhoneToolProgress() }
        .count { action ->
            action.isSupervisedProjectConnector() &&
                action.id.startsWith(RECOVERY_ACTION_PREFIX)
        }

    private fun AgentAction.isVerifiedPhoneToolProgress(): Boolean =
        kind == AgentActionKind.CALL_NATIVE_TOOL &&
            status == AgentActionStatus.COMPLETED &&
            evidence.isNotBlank()

    private const val RECOVERY_ACTION_PREFIX = "supervise-phone-project-recovery-"
}

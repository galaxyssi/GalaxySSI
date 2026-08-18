package com.signalasi.chat

internal object AgentSupervisedProjectRecoveryPolicy {
    /**
     * A verified phone-tool result starts a new recovery window. Older failures
     * remain useful diagnostics but never exhaust recovery for a foreground task.
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

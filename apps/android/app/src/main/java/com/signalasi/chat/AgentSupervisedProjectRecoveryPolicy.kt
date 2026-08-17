package com.signalasi.chat

internal object AgentSupervisedProjectRecoveryPolicy {
    fun canRecover(history: List<AgentAction>, maximumRecoveries: Int): Boolean =
        recoveryCount(history) < maximumRecoveries

    fun recoveryCount(history: List<AgentAction>): Int = history.count { action ->
        action.isSupervisedProjectConnector() &&
            action.id.startsWith(RECOVERY_ACTION_PREFIX)
    }

    private const val RECOVERY_ACTION_PREFIX = "supervise-phone-project-recovery-"
}

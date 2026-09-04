package com.galaxyssi.chat

import org.json.JSONObject

internal object AgentSupervisedProjectRecoveryPolicy {
    const val OUTCOME_STATE_METADATA = "outcome_state"
    const val UNKNOWN_OUTCOME = "unknown"

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

    fun hasUnknownOutcome(action: AgentAction): Boolean =
        runCatching { JSONObject(action.evidence).optString(OUTCOME_STATE_METADATA) }
            .getOrDefault("") == UNKNOWN_OUTCOME

    private fun AgentAction.isVerifiedPhoneToolProgress(): Boolean =
        kind == AgentActionKind.CALL_NATIVE_TOOL &&
            status == AgentActionStatus.COMPLETED &&
            evidence.isNotBlank()

    private const val RECOVERY_ACTION_PREFIX = "supervise-phone-project-recovery-"
}

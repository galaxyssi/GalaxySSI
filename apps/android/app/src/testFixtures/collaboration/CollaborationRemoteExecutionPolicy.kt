package com.galaxyssi.chat

/** Shared test-only dispatch controls, not production routing defaults. */
internal interface CollaborationRemoteExecutionPolicy {
    val targetId: String
    val selection: CollaborationLiveModelSelection
    fun prompt(context: AgentTeamMemberExecutionContext): String

    fun requireAppSelection(current: AgentModelSelection) {
        require(current.mode == AgentModelSelectionMode.MANUAL && current.targetId == targetId &&
            current.modelId == selection.modelId && current.reasoningEffort == selection.reasoningEffort) {
            "Select the protocol target, model and effort in the App conversation before running; no default or substitution allowed"
        }
    }
}

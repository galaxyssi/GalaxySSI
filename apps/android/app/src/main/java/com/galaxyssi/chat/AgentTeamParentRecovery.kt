package com.galaxyssi.chat

internal object AgentTeamParentRecoveryPolicy {
    const val PAUSED = "team_recovery_paused"

    fun shouldPause(team: AgentTeamExecutionSnapshot?, conversation: String, turn: String): Boolean =
        team == null || team.state == AgentTeamExecutionState.INTERRUPTED ||
            team.conversationId != conversation || team.taskId != turn

    fun isTeamWait(phase: AgentPhase, metadata: Map<String, String>): Boolean =
        phase == AgentPhase.WAITING_RESPONSE && metadata["resource_location"] == "distributed" &&
            metadata["team_run_id"].orEmpty().isNotBlank() &&
            metadata["source_message_id"]?.toLongOrNull()?.let { it > 0L } == true

    fun acceptsLateResult(phase: AgentPhase, metadata: Map<String, String>, source: Long): Boolean =
        phase == AgentPhase.PAUSED && metadata[PAUSED] == "true" && source > 0L &&
            metadata["resource_location"] == "distributed" &&
            metadata["team_run_id"].orEmpty().isNotBlank() &&
            metadata["source_message_id"]?.toLongOrNull() == source &&
            AgentTeamDispatchIds.sourceMessageId(metadata.getValue("team_run_id")) == source
}

/** Reconcile the original team; never create a new team as a transport retry. */
internal fun MobileNativeAgent.reconcileSavedAgentTeam(): AgentUiState? = synchronized(this) {
    val pending = lastActionResult ?: return@synchronized null
    if (!AgentTeamParentRecoveryPolicy.isTeamWait(phase, pending.metadata)) return@synchronized null
    val action = currentPlan?.actions?.firstOrNull { it.id == pending.actionId &&
        it.kind == AgentActionKind.CALL_CONNECTOR && it.parameters[AGENT_TEAM_SPEC_PARAMETER].orEmpty().isNotBlank() }
        ?: return@synchronized null
    val runId = pending.metadata.getValue("team_run_id")
    val team = GlobalSuperAgentRuntime.get(appContext).agentTeamSnapshot(runId)
    val conversation = action.parameters[INTERNAL_CONVERSATION_ID].orEmpty()
        .ifBlank { activeConversationContext.conversationId }
    val turn = action.parameters[INTERNAL_TURN_ID].orEmpty().ifBlank { activeConversationTurnId }
    if (AgentTeamParentRecoveryPolicy.shouldPause(team, conversation, turn)) {
        phase = AgentPhase.PAUSED
        lastActionResult = pending.copy(success = false,
            message = appContext.getString(R.string.agent_team_recovery_paused),
            metadata = pending.metadata + mapOf(AgentTeamParentRecoveryPolicy.PAUSED to "true",
                "team_state" to (team?.state?.name?.lowercase() ?: "missing")))
        recordAudit(AgentAuditEvent.TASK_PAUSED, "Saved Agent team unavailable; awaiting original outcome")
        saveTaskRecord()
        return@synchronized reconcileExecutionLoop(snapshot())
    }
    if (team == null || !team.state.isTerminal) return@synchronized snapshot()
    val success = team.finalOutput.isNotBlank() && team.state in setOf(
        AgentTeamExecutionState.SUCCEEDED, AgentTeamExecutionState.COMPLETED_WITH_FAILURES)
    acceptConnectorResponse(pending.metadata.getValue("source_message_id").toLong(),
        pending.metadata["contact_id"].orEmpty(),
        team.finalOutput.takeIf { success } ?: appContext.getString(R.string.agent_team_failed_response),
        success = success, conversationId = team.conversationId, turnId = team.taskId, taskId = team.taskId)
        ?: snapshot()
}

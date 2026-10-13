package com.galaxyssi.chat

/** File workspaces and supervised Runs have different identities; never substitute one for the other. */
internal object AgentBrowserRunRecoveryPolicy {
    fun bind(record: AgentBrowserUserRequest, candidates: List<AgentWorkspace>,
        session: (String) -> AgentSessionSnapshot?): AgentBrowserUserRequest {
        if (record.modelLoopId.isBlank() && record.actionPlanBinding.isBlank()) return record
        val owners = candidates.mapNotNull { workspace ->
            if (workspace.taskId != record.taskId || workspace.conversationId != record.conversationId ||
                workspace.status.isTerminal || workspace.cancellationRequested) return@mapNotNull null
            val saved = session(workspace.workspaceId) ?: return@mapNotNull null
            if (matchesRuntime(record, workspace, saved)) workspace to saved else null
        }
        val (owner, saved) = owners.singleOrNull() ?: return record
        return record.copy(runWorkspaceId = owner.workspaceId, runSessionId = owner.sessionId,
            runPlanningBinding = saved.pendingPlanning?.let(::planningBinding).orEmpty())
    }

    fun matches(record: AgentBrowserUserRequest, workspace: AgentWorkspace, session: AgentSessionSnapshot?): Boolean =
        record.runWorkspaceId.isNotBlank() && workspace.workspaceId == record.runWorkspaceId &&
            workspace.sessionId == record.runSessionId && session != null && matchesRuntime(record, workspace, session) &&
            (if (record.actionPlanBinding.isNotBlank()) AgentBrowserActionPlanPolicy.action(record, session) != null
             else record.modelLoopId.isNotBlank() && record.runPlanningBinding.isNotBlank() &&
                 record.runPlanningBinding == session.pendingPlanning?.let(::planningBinding))

    private fun planningBinding(reference: AgentPlanningReference): String = AgentNativeJsonCodec.sha256(listOf(
        reference.sessionId, reference.conversationId, reference.turnId, reference.inputSha256,
        reference.basePlanId, reference.baseRevision))

    private fun matchesRuntime(record: AgentBrowserUserRequest, workspace: AgentWorkspace,
        session: AgentSessionSnapshot): Boolean =
        record.sessionId == session.sessionId && record.taskId == workspace.taskId &&
            record.turnId == workspace.taskId && record.conversationId == workspace.conversationId &&
            record.workspaceId == AgentWorkspaceScope.id(workspace.conversationId, session.sessionId) &&
            (if (record.actionPlanBinding.isNotBlank()) AgentBrowserActionPlanPolicy.action(record, session) != null
             else session.pendingPlanning?.let { reference ->
                reference.sessionId == record.sessionId && reference.turnId == record.turnId &&
                    reference.conversationId == record.conversationId
            } == true) && session.executionLoopSnapshot?.taskId == record.taskId

    fun decision(record: AgentBrowserUserRequest, workspace: AgentWorkspace, session: AgentSessionSnapshot?,
        activeWorkspaceIds: Set<String>): AgentLongTaskRecoveryDecision? {
        if (!record.pendingRunWake || !matches(record, workspace, session) ||
            workspace.workspaceId in activeWorkspaceIds || workspace.status.isTerminal || workspace.cancellationRequested ||
            session == null || session.phase in setOf(AgentPhase.COMPLETED, AgentPhase.CANCELLED, AgentPhase.FAILED) ||
            session.lastActionResult?.actionId == "agent-paused" || session.executionLoopSnapshot?.phase?.isTerminal == true) return null
        val mode = when {
            record.actionPlanBinding.isNotBlank() -> AgentLongTaskRecoveryMode.BROWSER_ACTION_EVENT
            AgentReplanningRecoveryPolicy.belongsTo(workspace, session) -> AgentLongTaskRecoveryMode.REPLANNING
            AgentInitialPlanningRecoveryPolicy.belongsTo(workspace, session) -> AgentLongTaskRecoveryMode.INITIAL_PLANNING
            else -> return null
        }
        return AgentLongTaskRecoveryDecision(mode,
            if (record.state == "interrupted")
                AgentBrowserInterruptionPolicy.message(record.interruptionCode)
            else "User returned browser control; resume the original checkpoint, observe the current page and verify the goal")
    }
}

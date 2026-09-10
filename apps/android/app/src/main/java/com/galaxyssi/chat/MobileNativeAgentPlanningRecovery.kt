package com.galaxyssi.chat

internal fun MobileNativeAgent.beginInitialPlanning(startedAt: Long): AgentUiState {
    phase = AgentPhase.PLANNING
    currentPlan = null
    lastActionResult = null
    val selected = taskScopedPlanner()
    val spec = selected.recoverySpec() ?: return executeInitialPlanning(selected, startedAt)
    activeConversationTurnId = activeConversationTurnId.ifBlank { sessionId }
    activeConversationContext = activeConversationContext.copy(
        conversationId = activeConversationContext.conversationId.ifBlank { sessionId })
    val input = AgentPlanningInput(currentGoal, activeConversationContext, activeConversationTurnId,
        activeRequestedMembers, activeTaskExecutionMode, spec)
    return planningPersistence.begin(sessionId, input) { reference ->
        pendingPlanning = reference
        persistSession()
        check(sessionStore.load()?.pendingPlanning == reference) { "Initial planning reference was not committed" }
        executeInitialPlanning(selected, startedAt)
    }
}

internal fun MobileNativeAgent.resumeInitialPlanning(): AgentUiState {
    val reference = pendingPlanning ?: return snapshot()
    if (currentPlan != null || phase !in setOf(AgentPhase.PAUSED, AgentPhase.PLANNING) ||
        executionLoop.snapshot?.phase?.isTerminal == true || PhoneExecutionAuthority.isCancelled(sessionId)) return snapshot()
    if (reference.sessionId != sessionId || executionLoop.snapshot?.taskId != reference.turnId) {
        throw AgentModelLoopRecoveryException("initial_planning_session_mismatch")
    }
    return planningPersistence.restore(reference) { input ->
        check(input.replan == null) { "Replanning must restore its original base plan" }
        if (taskPlannerSpec != null && taskPlannerSpec != input.planner) {
            throw AgentModelLoopRecoveryException("task_planner_reference_changed")
        }
        taskPlannerSpec = input.planner.takeIf { it.modelSnapshot != null }
        val selected = planner.takeIf { it.recoverySpec() == input.planner }
            ?: input.planner.restore(appContext) { nativeToolRegistry }
        activeConversationContext = input.conversation
        activeConversationTurnId = input.turnId
        activeRequestedMembers = input.members
        activeTaskExecutionMode = input.mode
        currentGoal = input.goal
        invalidateRuntimeContext()
        phase = AgentPhase.PLANNING
        lastActionResult = null
        executionLoop.snapshot?.takeIf { it.phase == AgentExecutionLoopPhase.PAUSED }?.let {
            persistExecutionLoopEvent(executionLoop.resume("Resuming the original planning input and observations"))
        }
        persistSession()
        reconcileExecutionLoop(executeInitialPlanning(selected))
    }
}

internal object AgentInitialPlanningRecoveryPolicy {
    fun belongsTo(workspace: AgentWorkspace, session: AgentSessionSnapshot): Boolean {
        val reference = session.pendingPlanning ?: return false
        return !reference.isReplanning && session.currentPlan == null && reference.sessionId == session.sessionId &&
            reference.conversationId == workspace.conversationId && reference.turnId == workspace.taskId &&
            session.executionLoopSnapshot?.taskId == reference.turnId &&
            session.executionLoopSnapshot.phase.isTerminal.not() &&
            session.phase in setOf(AgentPhase.PLANNING, AgentPhase.PAUSED)
    }
}

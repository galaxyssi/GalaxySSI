package com.galaxyssi.chat

internal fun MobileNativeAgent.planningWasStopped(): Boolean =
    phase in setOf(AgentPhase.PAUSED, AgentPhase.CANCELLED) || PhoneExecutionAuthority.isCancelled(sessionId)

/** The base graph is model input, not a graph to normalize or dispatch before replanning finishes. */
internal fun MobileNativeAgent.restorePendingReplanningSession(session: AgentSessionSnapshot): Boolean {
    if (session.pendingPlanning?.isReplanning != true) return false
    val interrupted = AgentSessionInterruptionPolicy.wasInterrupted(session)
    sessionId = session.sessionId
    pendingPlanning = session.pendingPlanning
    activeTaskExecutionMode = session.taskExecutionMode
    phase = if (interrupted) AgentPhase.PAUSED else session.phase
    currentGoal = session.currentGoal
    currentScreen = session.currentScreen
    currentPlan = session.currentPlan
    lastActionResult = session.lastActionResult
    activeWorkflowExecutionId = session.activeWorkflowExecutionId.takeIf { it.isNotBlank() }
    auditTrail.clear()
    auditTrail.addAll(session.auditTrail.takeLast(MAX_AUDIT_ITEMS))
    if (interrupted) {
        executionLoop.recoverInterrupted()
        lastActionResult = AgentActionResult("agent-interrupted", false, "Model replanning was interrupted")
        recordAudit(AgentAuditEvent.TASK_INTERRUPTED, "restored_pending_model_replanning")
    }
    return true
}

internal fun MobileNativeAgent.executeDurableReplanning(plan: AgentPlan, reason: String): AgentPlan? {
    val spec = planner.recoverySpec() ?: return buildReplannedPlan(plan, reason, planner)
    check(pendingPlanning?.isReplanning != true) { "Resume the saved replanning operation before starting another" }
    val scope = AgentPlanContinuationScope.resolve(plan, activeConversationContext.conversationId,
        activeConversationTurnId, sessionId) ?: return null
    val intent = AgentReplanningIntent(plan.planId, plan.revision,
        planningPersistence.planFingerprint(plan, currentGoal), reason)
    val input = AgentPlanningInput(currentGoal, scope.context(activeConversationContext), scope.turnId,
        activeRequestedMembers, activeTaskExecutionMode, spec, intent)
    val priorPhase = phase
    return planningPersistence.begin(sessionId, input) { reference ->
        currentPlan = plan
        pendingPlanning = reference
        phase = AgentPhase.PLANNING
        persistSession()
        check(sessionStore.load()?.pendingPlanning == reference) { "Replanning reference was not committed" }
        val revised = buildReplannedPlan(plan, reason, planner)
        publishReplannedPlan(reference, revised, priorPhase)
    }
}

private fun MobileNativeAgent.publishReplannedPlan(reference: AgentPlanningReference, revised: AgentPlan?,
    priorPhase: AgentPhase): AgentPlan? {
    if (pendingPlanning != reference || phase in setOf(AgentPhase.PAUSED, AgentPhase.CANCELLED, AgentPhase.FAILED) ||
        PhoneExecutionAuthority.isCancelled(sessionId)) return null
    pendingPlanning = null
    if (revised != null) currentPlan = revised
    phase = when {
        revised == null -> priorPhase
        revised.safetyReview.blocked -> AgentPhase.BLOCKED
        revised.safetyReview.requiresConfirmation -> AgentPhase.WAITING_CONFIRMATION
        else -> AgentPhase.PLANNING
    }
    persistSession()
    return revised
}

internal fun MobileNativeAgent.resumePendingReplanning(): AgentUiState {
    val reference = pendingPlanning?.takeIf { it.isReplanning } ?: return snapshot()
    if (phase != AgentPhase.PAUSED || executionLoop.snapshot?.phase?.isTerminal == true ||
        PhoneExecutionAuthority.isCancelled(sessionId)) return snapshot()
    if (reference.sessionId != sessionId || executionLoop.snapshot?.taskId != reference.turnId) {
        throw AgentModelLoopRecoveryException("replanning_session_mismatch")
    }
    val revised = planningPersistence.restore(reference) { input ->
        val intent = requireNotNull(input.replan)
        val base = currentPlan ?: throw AgentModelLoopRecoveryException("replanning_base_plan_missing")
        if (base.planId != intent.planId || base.revision != intent.revision ||
            planningPersistence.planFingerprint(base, input.goal) != intent.planSha256) {
            throw AgentModelLoopRecoveryException("replanning_base_plan_changed")
        }
        val selected = planner.takeIf { it.recoverySpec() == input.planner }
            ?: input.planner.restore(appContext) { nativeToolRegistry }
        activeConversationContext = input.conversation
        activeConversationTurnId = input.turnId
        activeRequestedMembers = input.members
        activeTaskExecutionMode = input.mode
        currentGoal = input.goal
        invalidateRuntimeContext()
        phase = AgentPhase.PLANNING
        executionLoop.snapshot?.takeIf { it.phase == AgentExecutionLoopPhase.PAUSED }?.let {
            persistExecutionLoopEvent(executionLoop.resume("Resuming the original model replanning operation"))
        }
        persistSession()
        publishReplannedPlan(reference, buildReplannedPlan(base, intent.reason, selected), AgentPhase.WAITING_RESPONSE)
    }
    if (phase in setOf(AgentPhase.PAUSED, AgentPhase.CANCELLED, AgentPhase.FAILED)) return snapshot()
    lastActionResult = if (revised != null) AgentActionResult("agent-replanned", true,
        "Restored plan revision ${revised.revision}") else AgentActionResult("agent-replan-unavailable", false,
        "The restored planner did not return a valid model plan")
    saveTaskRecord()
    return reconcileExecutionLoop(if (phase == AgentPhase.PLANNING) executeFirstPendingAction() else snapshot())
}

internal object AgentReplanningRecoveryPolicy {
    fun belongsTo(workspace: AgentWorkspace, session: AgentSessionSnapshot): Boolean {
        val reference = session.pendingPlanning?.takeIf { it.isReplanning } ?: return false
        val plan = session.currentPlan ?: return false
        val loop = session.executionLoopSnapshot ?: return false
        return reference.sessionId == session.sessionId && reference.conversationId == workspace.conversationId &&
            reference.turnId == workspace.taskId && reference.turnId == loop.taskId && !loop.phase.isTerminal &&
            reference.basePlanId == plan.planId && reference.baseRevision == plan.revision &&
            session.phase in setOf(AgentPhase.PLANNING, AgentPhase.PAUSED)
    }
}

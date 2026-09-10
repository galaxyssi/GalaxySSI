package com.galaxyssi.chat

internal fun MobileNativeAgent.executeJournaledPlanAction(
    key: AgentPlanNodeKey,
    execute: () -> AgentActionResult
): AgentActionResult {
    planNodeJournal.start(key)
    val result = execute()
    planNodeJournal.record(key, AgentPlanNodeObservation(result, verified = false))
    return result
}

/** Recovery observes completed dispatches; it never invokes or retries their executors. */
internal fun MobileNativeAgent.resumePersistedPlanObservations(): Boolean {
    val plan = currentPlan ?: return false
    var changed = false
    var lastRecovered: Pair<AgentAction, AgentActionResult>? = null
    plan.actions.filter { it.evidence == AGENT_NODE_OBSERVATION_PENDING }.forEach { action ->
        val key = requireNotNull(AgentPlanNodeKey.from(sessionId, plan, action))
        val saved = requireNotNull(planNodeJournal.read(key)) { "Persisted node observation is missing" }
        val observed = if (saved.verified) saved else {
            val screen = captureVerificationScreen(action, currentScreen, saved.result)
            val result = requireNotNull(applyObservationResult(action, saved.result, screen))
            currentScreen = screen.screen
            AgentPlanNodeObservation(result, verified = true, evidence = screen.evidence).also {
                planNodeJournal.record(key, it)
            }
        }
        currentPlan = AgentPlanNodeRecovery.applyVerified(requireNotNull(currentPlan), action, observed)
        lastActionResult = observed.result
        lastRecovered = action to observed.result
        changed = true
        persistSession()
    }
    lastRecovered?.let { (action, result) ->
        currentPlan = ensureSupervisedProjectContinuation(requireNotNull(currentPlan), action, result)
        saveTaskRecord()
        persistSession()
    }
    return changed
}

internal fun MobileNativeAgent.assessRecoveredPlanNodes(plan: AgentPlan): AgentUiState {
    val rolling = AgentRollingPlanPolicy.shouldRequestNextBatch(plan, lastActionResult)
    val reason = if (rolling) AgentRollingPlanPolicy.reason(plan, lastActionResult) else
        "Recovered node observations contain failed or uncertain actions. Preserve completed nodes, " +
            "inspect the recorded outcomes and decide the next plan revision. " +
            plan.actions.filter { it.status == AgentActionStatus.FAILED }
                .joinToString("; ") { "${it.id}: ${it.result}" }
    if (!advanceExecutionLoop(AgentExecutionLoopPhase.REPLAN, reason)) return reconcileExecutionLoop(snapshot())
    val next = replanFromCurrentState(plan, reason, force = true)
    if (planningWasStopped()) return snapshot()
    if (next == null) {
        phase = AgentPhase.WAITING_RESPONSE
        lastActionResult = lastActionResult?.copy(metadata = lastActionResult!!.metadata + mapOf(
            (if (rolling) "rolling_plan_assessment_pending" else "node_recovery_assessment_pending") to "true",
            "rolling_plan_revision" to plan.revision.toString()))
        saveTaskRecord()
        return reconcileExecutionLoop(snapshot())
    }
    currentPlan = next
    phase = AgentPhase.PLANNING
    saveTaskRecord()
    return reconcileExecutionLoop(executeFirstPendingAction())
}

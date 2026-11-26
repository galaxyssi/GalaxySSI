package com.galaxyssi.chat

/** Pre-fix sessions can already be waiting for a remote review of a verified timer. */
@Synchronized
internal fun MobileNativeAgent.finishWaitingTimerReview(source: Long): AgentUiState? {
    val waiting = lastActionResult ?: return null
    if (phase != AgentPhase.WAITING_RESPONSE || waiting.metadata["source_message_id"]?.toLongOrNull() != source)
        return null
    val plan = currentPlan ?: return null
    val timer = AgentVerifiedTimerStart.waitingStart(plan.actions, waiting.actionId) ?: return null
    val key = AgentPlanNodeKey.from(sessionId, plan, timer) ?: return null
    val receipt = try { planNodeJournal.read(key) } catch (e: Exception) {
        if (e is java.util.concurrent.CancellationException) throw e
        return null
    }?.takeIf { it.verified }?.result ?: return null
    val completion = AgentSupervisedProjectCompletionPolicy.verifiedTerminalOutcome(
        currentGoal, plan.actionHistory + plan.actions, timer, receipt, plan.completionRequirements, plan.actions
    ) { nativeToolRegistry.lookup(it)?.descriptor } ?: return null
    return reconcileExecutionLoop(completeVerifiedProjectOutcome(plan, timer, receipt, completion))
}

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
    val recovered = mutableListOf<Pair<AgentAction, AgentActionResult>>()
    plan.actions.filter { it.evidence == AGENT_NODE_OBSERVATION_PENDING }.forEach { action ->
        val key = requireNotNull(AgentPlanNodeKey.from(sessionId, plan, action))
        val saved = requireNotNull(planNodeJournal.read(key)) { "Persisted node observation is missing" }
        if (waitForBrowserAction(action, saved.result)) return true
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
        recovered += action to observed.result
        changed = true
        persistSession()
    }
    if (recovered.isNotEmpty()) {
        val observedPlan = requireNotNull(currentPlan)
        recovered.singleOrNull()?.let { (action, result) ->
            if (action.parameters["tool_id"] == AgentVerifiedTimerStart.toolId) {
                val completion = AgentSupervisedProjectCompletionPolicy.verifiedTerminalOutcome(
                    currentGoal, observedPlan.actionHistory + observedPlan.actions, action, result,
                    observedPlan.completionRequirements, observedPlan.actions
                ) { nativeToolRegistry.lookup(it)?.descriptor }
                if (completion != null) {
                    completeVerifiedProjectOutcome(observedPlan, action, result, completion)
                    persistSession()
                    return true
                }
            }
        }
        currentPlan = continueObservedOutcomes(observedPlan, recovered, resumingPausedTask = true)
        saveTaskRecord()
        persistSession()
    }
    return changed
}

internal fun MobileNativeAgent.assessRecoveredPlanNodes(plan: AgentPlan): AgentUiState {
    if (phase == AgentPhase.CANCELLED || PhoneExecutionAuthority.isCancelled(sessionId)) return snapshot()
    val rolling = AgentRollingPlanPolicy.shouldRequestNextBatch(plan, lastActionResult)
    val reason = if (rolling) AgentRollingPlanPolicy.reason(plan, lastActionResult) else
        "Recovered node observations contain failed or uncertain actions. Preserve completed nodes, " +
            "inspect the recorded outcomes and decide the next plan revision. " +
            plan.actions.filter { it.status == AgentActionStatus.FAILED }
                .joinToString("; ") { "${it.id}: ${it.result}" }
    if (!advanceExecutionLoop(AgentExecutionLoopPhase.REPLAN, reason)) return reconcileExecutionLoop(snapshot())
    // A restored pause is the entry state, not a new pause requested during model assessment.
    phase = AgentPhase.PLANNING
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

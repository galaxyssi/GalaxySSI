package com.galaxyssi.chat

/** The native receipt is immutable. User return is a separate, durable observation for the original provider. */
internal fun MobileNativeAgent.waitForBrowserAction(action: AgentAction, result: AgentActionResult?): Boolean {
    val store = AgentBrowserUserRequestStore(appContext)
    val record = AgentBrowserActionPlanPolicy.receiptRecord(result, store::load) ?: return false
    val plan = currentPlan ?: return false
    val saved = sessionStore.load()?.copy(currentPlan = plan) ?: return false
    if (AgentBrowserActionPlanPolicy.action(record, saved)?.id != action.id) return false
    if (phase in setOf(AgentPhase.CANCELLED, AgentPhase.FAILED) || PhoneExecutionAuthority.isCancelled(sessionId) ||
        lastActionResult?.actionId == "agent-paused") return true
    currentPlan = plan.markAction(action.id, AgentActionStatus.COMPLETED, result)
    phase = AgentPhase.PAUSED
    lastActionResult = AgentActionResult("agent-event-wait", true,
        appContext.getString(R.string.browser_user_control_waiting),
        metadata = result!!.metadata + mapOf("browser_action_wait_event" to AgentBrowserActionPlanPolicy.eventId(record)))
    if (executionLoop.snapshot?.phase?.isTerminal == false && executionLoop.snapshot?.phase != AgentExecutionLoopPhase.PAUSED)
        persistExecutionLoopEvent(executionLoop.pause(lastActionResult!!.message))
    persistSession()
    saveTaskRecord()
    return true
}

internal fun MobileNativeAgent.resumeBrowserActionPlan(record: AgentBrowserUserRequest): AgentUiState {
    if (safetySettingsStore.load().executionPaused || phase == AgentPhase.CANCELLED ||
        PhoneExecutionAuthority.isCancelled(sessionId) || lastActionResult?.actionId == "agent-paused") return snapshot()
    val store = AgentBrowserUserRequestStore(appContext)
    val latest = store.current(record.key, record.generation)
    check(latest.copy(modelObservationCommitted = record.modelObservationCommitted) == record && latest.settled)
    val plan = checkNotNull(currentPlan)
    val saved = checkNotNull(sessionStore.load()).copy(currentPlan = plan)
    val original = checkNotNull(AgentBrowserActionPlanPolicy.action(latest, saved)) { "Browser action binding changed" }
    activeConversationTurnId = record.turnId
    if (activeConversationContext.conversationId != record.conversationId) {
        val conversation = AgentTranscriptStore(appContext).conversation(record.conversationId)
        activeConversationContext = AgentConversationContext(record.conversationId, "", emptyList(),
            conversation?.privateMode ?: true, trackingPaused = conversation?.trackingPaused ?: true)
    }
    if (!AgentBrowserActionPlanPolicy.observed(latest, original)) {
        val observed = AgentBrowserActionPlanPolicy.observe(latest, original)
        val next = AgentBrowserActionPlanPolicy.continuation(plan, latest, observed,
            supervisedProjectRequest(plan, continuation = true))
        currentPlan = next.withSafetyReview(safetyPolicy.review(next, sessionId))
        phase = AgentPhase.PAUSED
        lastActionResult = AgentActionResult("agent-browser-event", true, observed.result,
            metadata = mapOf("browser_external_event" to AgentBrowserActionPlanPolicy.eventId(latest)))
        // Keep the journal's tool result unchanged; only the plan receives the external observation.
        persistSession()
    }
    store.markObservationCommitted(store.current(record.key, record.generation))
    if (phase !in setOf(AgentPhase.PAUSED, AgentPhase.PLANNING)) return snapshot()
    executionLoop.snapshot?.takeIf { it.phase == AgentExecutionLoopPhase.PAUSED }?.let {
        persistExecutionLoopEvent(executionLoop.resume("Browser event observed; continuing the original provider"))
    }
    if (executionLoop.snapshot?.phase in setOf(AgentExecutionLoopPhase.ACT, AgentExecutionLoopPhase.WAITING_RESPONSE) &&
        !advanceExecutionLoop(AgentExecutionLoopPhase.OBSERVE, "Observing the host-owned browser control event", record.actionId))
        return snapshot()
    if (!advanceExecutionLoop(AgentExecutionLoopPhase.REPLAN,
            "Observe the browser after its host-owned control event before deciding the next action")) return snapshot()
    phase = AgentPhase.PLANNING
    persistSession()
    return reconcileExecutionLoop(executeFirstPendingAction())
}

package com.galaxyssi.chat

internal fun MobileNativeAgent.recoverCodexSilence(
    plan: AgentPlan,
    action: AgentAction,
    failed: AgentActionResult,
    targets: List<AgentCallableTarget>,
    available: List<String>
): AgentUiState? {
    val current = failed.metadata["resource_id"].orEmpty().ifBlank { action.parameters["connector_id"].orEmpty() }
    val target = targets.firstOrNull { it.id == current }
    val codex = AgentCodexSilenceRecovery.isCodex(
        target?.adapterType ?: action.parameters["connector_adapter_type"].orEmpty(), current)
    val state = AgentConnectorFallbackAction.forDispatch(action).parameters +
        failed.metadata.filterKeys { it.startsWith(AgentCodexSilenceRecovery.PREFIX) }
    // A reasoning-only request is replayable. An unknown external mutation is not.
    if (!action.isSupervisedProjectConnector() &&
        !AgentRemoteSilencePolicy.permitsReplay(action, currentGoal)) return null
    val alternatives = available.filter { id ->
        val candidate = targets.firstOrNull { it.id == id } ?: return@filter false
        !AgentCodexSilenceRecovery.isCodex(candidate.adapterType, id) &&
            AgentConnectorFailureScope.permitsFallback(failed.metadata, connectorFailureDomain(id))
    }
    val decision = AgentCodexSilenceRecovery.next(state, current, codex,
        AgentCodexSilenceRecovery.isTimeout(failed.metadata, failed.message), alternatives) ?: return null
    if (codex && (decision.state[AgentCodexSilenceRecovery.TIMEOUTS]?.toIntOrNull() ?: 0) >= 2) {
        AgentResourceHealthStore(appContext).markTemporarilyUnavailable("target:$current", 5 * 60_000L)
    }
    val source = failed.metadata["source_message_id"]?.toLongOrNull() ?: 0L
    if (source > 0) {
        AgentPendingDeliveryStore.find(appContext, source)?.let {
            AgentTerminalDeliveryStore.mark(appContext, it, failed.message)
        }
        AgentPendingDeliveryStore.remove(appContext, source)
        AgentGlobalRunSlotStore(appContext).releaseBySourceMessageId(source)
        GalaxySSILinkDeliveryStore.discardClientSourceMessages(appContext, setOf(source))
        AndroidAgentRemoteSilence.retire(appContext, source)
    }
    if (decision.resourceId == null) {
        val terminal = failed.copy(message = appContext.getString(R.string.agent_codex_recovery_exhausted, failed.message),
            metadata = failed.metadata + decision.state + mapOf(
            "awaiting_response" to "false", "non_retriable" to "true", "recovery_exhausted" to "true"))
        currentPlan = plan.markAction(action.id, AgentActionStatus.FAILED, terminal)
        lastActionResult = terminal
        phase = AgentPhase.FAILED
        persistSession()
        saveTaskRecord(result = terminal.message)
        return reconcileExecutionLoop(snapshot())
    }
    val selected = targets.firstOrNull { it.id == decision.resourceId }
    val selection = AgentConnectorFallbackSelection(decision.resourceId, emptyList(), emptyList(), emptySet(),
        AgentConnectorFallbackTrail.parse(decision.state[AgentCodexSilenceRecovery.TRIED].orEmpty()).toSet())
    var retry = AgentConnectorFallbackAction.prepare(action.copy(parameters = action.parameters - "manual_target_locked"),
        selection, selected)
    val originalSettings = if (state[AgentCodexSilenceRecovery.ORIGIN].isNullOrBlank()) {
        action.parameters.filterKeys { it in setOf("manual_model_id", "agent_model_id", "agent_reasoning_effort") }
            .mapKeys { AgentCodexSilenceRecovery.PREFIX + it.key }
    } else state.filterKeys { it in setOf("bounded_codex_manual_model_id", "bounded_codex_agent_model_id", "bounded_codex_agent_reasoning_effort") }
    val restored = if (decision.resourceId == decision.state[AgentCodexSilenceRecovery.ORIGIN])
        originalSettings.mapKeys { it.key.removePrefix(AgentCodexSilenceRecovery.PREFIX) } else emptyMap()
    val handoff = AgentResearchCheckpoint.scope(
        action.parameters[INTERNAL_CONVERSATION_ID].orEmpty(), action.parameters[INTERNAL_TURN_ID].orEmpty())
    retry = retry.copy(parameters = retry.parameters + decision.state + originalSettings + restored +
        (AgentResearchCheckpoint.RECOVERY to handoff))
    val retryPlan = plan.copy(actions = plan.actions.map { if (it.id == action.id) retry else it },
        selectedAgentOrModel = retry.target, route = AgentRouteResolver.resolve(retry, targets))
    currentPlan = retryPlan
    lastActionResult = failed
    phase = AgentPhase.PLANNING
    advanceExecutionLoop(AgentExecutionLoopPhase.REPLAN, "Bounded Codex silence recovery", action.id)
    persistSession()
    saveTaskRecord()
    return reconcileExecutionLoop(executePlannedAction(retryPlan, retry, userConfirmed = false, retrying = true))
}

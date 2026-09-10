package com.galaxyssi.chat

import android.os.SystemClock
import android.util.Log

internal fun MobileNativeAgent.executeInitialPlanning(planningPlanner: AgentPlanner, planningStartedAt: Long = SystemClock.elapsedRealtime()): AgentUiState {
    var stageStartedAt = planningStartedAt
    val planningInputs = AgentPlanningContextLoader.load(
        connectorsProvider = connectorRegistry::planningSnapshot,
        memoriesProvider = {
            if (activeConversationContext.privateMode) emptyList() else memoryStore.recall(currentGoal)
        },
        knowledgeProvider = { knowledgeStore.querySnapshot(currentGoal) },
        settingsProvider = ::modelPlannerSettings,
        runtimeProvider = ::planningRuntimeSnapshot
    )
    val targets = planningInputs.targets
    val memories = planningInputs.memories
    val knowledge = planningInputs.knowledge
    val knowledgeItems = knowledge.items
    Log.i(
        "GalaxySSILatency",
        "agent_planning stage=context_sources_parallel " +
            "stage_ms=${planningInputs.timing.totalMillis} " +
            "connectors_ms=${planningInputs.timing.connectorsMillis} " +
            "memory_ms=${planningInputs.timing.memoriesMillis} " +
            "knowledge_ms=${planningInputs.timing.knowledgeMillis} " +
            "settings_ms=${planningInputs.timing.settingsMillis} " +
            "runtime_ms=${planningInputs.timing.runtimeMillis} " +
            "total_ms=${SystemClock.elapsedRealtime() - planningStartedAt}"
    )
    stageStartedAt = SystemClock.elapsedRealtime()
    val context = buildRuntimeContext(
        goal = currentGoal,
        screen = currentScreen,
        targets = targets,
        memories = memories,
        knowledgeItems = knowledgeItems,
        knowledgeStats = knowledge.stats,
        planningRuntime = planningInputs.runtime
    ).also(::cacheRuntimeContext)
    logPlanningLatency("context", stageStartedAt, planningStartedAt)
    stageStartedAt = SystemClock.elapsedRealtime()
    val planned = com.galaxyssi.chat.metrics.AgentLatencyTelemetry.planning(appContext, sessionId) {
        planningPlanner.plan(
            request = AgentRequest(
                goal = currentGoal,
                screen = currentScreen,
                targets = targets,
                registrations = planningInputs.registrations,
                requestedMembers = activeRequestedMembers,
                memories = memories,
                runtimeContext = context,
                conversationContext = activeConversationContext,
                executionTurnId = activeConversationTurnId
            )
        )
    }
    if (phase in setOf(AgentPhase.PAUSED, AgentPhase.CANCELLED, AgentPhase.FAILED)) return snapshot()
    logPlanningLatency("planner", stageStartedAt, planningStartedAt)
    stageStartedAt = SystemClock.elapsedRealtime()
    val conversationPrompt = activeConversationContext.asAgentTransportBlock(currentGoal)
    val memoryPrompt = memories.take(5).joinToString("\n") { "- ${it.value.take(600)}" }
    val cloudKnowledgePrompt = knowledgeItems
        .filter { it.cloudAccess != AgentKnowledgeCloudAccess.DENY }
        .take(5)
        .joinToString("\n") { item ->
            val value = if (item.cloudAccess == AgentKnowledgeCloudAccess.FULL) item.content else item.summary
            "- ${item.title}: ${value.take(1_200)}"
        }
    val agentKnowledgePrompt = knowledgeItems
        .filter { it.agentAccess == AgentKnowledgeAgentAccess.ANY_PAIRED_AGENT }
        .take(5)
        .joinToString("\n") { "- ${it.title}: ${it.summary.ifBlank { it.content }.take(1_200)}" }
    val screenPrompt = if (
        planningInputs.settings.shareScreenText && currentScreen.sensitiveFlagCount == 0
    ) {
        buildString {
            append("App: ").append(currentScreen.foregroundApp).append('\n')
            append("Page: ").append(currentScreen.pageTitle).append('\n')
            append(currentScreen.visibleTexts.take(20).joinToString("\n") { "- ${it.take(300)}" })
        }.take(6_000)
    } else ""
    val contextualPlan = planned.copy(
        executionMode = activeTaskExecutionMode,
        actions = planned.actions.map { action ->
            val targetIds = setOf(
                action.parameters["connector_id"].orEmpty(),
                action.parameters["contact_id"].orEmpty(),
                action.target
            ).filter(String::isNotBlank)
            val selectedKnowledgePrompt = knowledgeItems
                .filter { item ->
                    item.agentAccess == AgentKnowledgeAgentAccess.SELECTED_AGENTS &&
                        item.allowedAgentIds.any { allowed ->
                            targetIds.any { target -> target.equals(allowed, ignoreCase = true) }
                        }
                }
                .take(5)
                .joinToString("\n") { "- ${it.title}: ${it.summary.ifBlank { it.content }.take(1_200)}" }
            action.copy(parameters = action.parameters + mapOf(
                INTERNAL_CONVERSATION_ID to activeConversationContext.conversationId,
                INTERNAL_CONVERSATION_CONTEXT to conversationPrompt,
                INTERNAL_CONVERSATION_HAS_ATTACHMENTS to activeConversationContext.hasAttachments.toString(),
                INTERNAL_TURN_ID to activeConversationTurnId,
                INTERNAL_MEMORY_CONTEXT to memoryPrompt,
                INTERNAL_CLOUD_KNOWLEDGE_CONTEXT to cloudKnowledgePrompt,
                INTERNAL_AGENT_KNOWLEDGE_CONTEXT to listOf(agentKnowledgePrompt, selectedKnowledgePrompt)
                    .filter(String::isNotBlank).joinToString("\n"),
                INTERNAL_SCREEN_CONTEXT to screenPrompt,
                INTERNAL_LONG_TERM_WRITE_ALLOWED to (!activeConversationContext.privateMode).toString(),
                INTERNAL_TASK_EXECUTION_MODE to action.executionModeWireValue(activeTaskExecutionMode)
            )).enforceSupervisedPlanningBoundary()
        }
    )
    val draftPlan = AgentTeamPlanCompiler.compile(
        plan = contextualPlan,
        targets = targets,
        enabled = planningInputs.settings.multiAgentCoordination,
        registrations = planningInputs.registrations,
        requestedMembers = activeRequestedMembers,
        reputation = reputationLedger
    )
    val safetyReview = safetyPolicy.review(draftPlan, sessionId)
    logPlanningLatency("team_and_safety", stageStartedAt, planningStartedAt)
    if (activeTaskExecutionMode == AgentTaskExecutionMode.PLAN_ONLY) {
        val proposedPlan = draftPlan.copy(
            executionMode = AgentTaskExecutionMode.PLAN_ONLY,
            actions = draftPlan.actions.map { action ->
                action.copy(
                    status = AgentActionStatus.PROPOSED,
                    requiresConfirmation = false,
                    result = "",
                    evidence = ""
                )
            },
            safetyReview = AgentSafetyReview(
                risk = safetyReview.risk,
                requiresConfirmation = false,
                blocked = false,
                reason = appContext.getString(R.string.agent_plan_only_not_executed),
                mode = safetyPolicy.permissionMode()
            ),
            confirmationRequired = false
        )
        currentPlan = proposedPlan.copy(
            validation = AgentPlanValidator.validate(proposedPlan)
        )
        pendingPlanning = null
        phase = AgentPhase.COMPLETED
        lastActionResult = AgentActionResult(
            actionId = "plan-only",
            success = true,
            message = renderPlanOnlyResult(currentPlan!!)
        )
        persistSession()
        recordAudits(
            AgentAuditRecord(
                AgentAuditEvent.REASONING_SUMMARY,
                "execution_mode=plan_only; actions=${currentPlan!!.actions.size}; " +
                    "risk=${currentPlan!!.safetyReview.risk.name}"
            ),
            AgentAuditRecord(AgentAuditEvent.GOAL_RECEIVED, goalAuditDetail(currentGoal))
        )
        saveTaskRecord()
        return snapshot()
    }
    currentPlan = draftPlan.withSafetyReview(safetyReview)
    pendingPlanning = null
    phase = when {
        safetyReview.blocked -> AgentPhase.BLOCKED
        safetyReview.requiresConfirmation -> AgentPhase.WAITING_CONFIRMATION
        else -> AgentPhase.PLANNING
    }
    lastActionResult = null
    persistSession()
    val memoryBlockReason = if (activeConversationContext.privateMode) {
        "Private session is excluded from long-term memory"
    } else if (isPrivateCommunicationGoal(currentGoal)) {
        "Private communication is excluded from long-term memory"
    } else {
        memoryBlockReason(currentGoal, currentScreen, planningInputs.runtime.memoryCapture)
    }
    val planningAudits = mutableListOf(
        AgentAuditRecord(
            AgentAuditEvent.INVOCATION_AUDIT,
            "planner=${draftPlan.plannerProfile}; actions=${draftPlan.actions.size}; valid=${draftPlan.validation.valid}"
        ),
        AgentAuditRecord(
            AgentAuditEvent.REASONING_SUMMARY,
            "route=${draftPlan.selectedAgentOrModel.take(160)}; actions=${draftPlan.actions.size}; profile=${draftPlan.plannerProfile.take(120)}"
        ),
        AgentAuditRecord(
            AgentAuditEvent.MEMORY_SKIPPED,
            memoryBlockReason ?: "Task context remains session-scoped until the user explicitly saves it"
        ),
        AgentAuditRecord(AgentAuditEvent.GOAL_RECEIVED, goalAuditDetail(currentGoal))
    )
    if (safetyReview.blocked) {
        planningAudits += AgentAuditRecord(
            AgentAuditEvent.ACTION_BLOCKED,
            safetyReview.reason.ifBlank { "blocked" }
        )
    }
    recordAudits(*planningAudits.toTypedArray())
    if (!safetyReview.blocked && !safetyReview.requiresConfirmation) {
        return executeFirstPendingAction()
    }
    saveTaskRecord()
    return snapshot()
}

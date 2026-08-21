package com.signalasi.chat

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.os.BatteryManager
import android.os.Build
import android.os.Environment
import android.os.PowerManager
import android.os.StatFs
import android.os.SystemClock
import android.provider.AlarmClock
import android.provider.CalendarContract
import android.provider.ContactsContract
import android.util.Log
import com.signalasi.chat.voice.VoiceFeatureFlags
import com.signalasi.chat.voice.agent.VoiceAgentRunBridge
import com.signalasi.chat.voice.agent.VoiceAgentRunRequest
import com.signalasi.chat.voice.metrics.VoiceLatencyTraceContext
import com.signalasi.chat.voice.modelstream.ModelStreamEvent
import com.signalasi.chat.voice.modelstream.ModelStreamUiMerger
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.runBlocking
import org.json.JSONArray
import org.json.JSONObject
import java.security.MessageDigest
import java.util.Locale
import java.util.Date
import java.text.SimpleDateFormat
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.FutureTask
import java.util.concurrent.TimeUnit

internal fun MobileNativeAgent.submitGoal(
    goal: String,
    conversationContext: AgentConversationContext = AgentConversationContext("", "", emptyList(), false),
    turnId: String = "",
    executionMode: AgentTaskExecutionMode? = null
): AgentUiState {
    val submitStartedAt = SystemClock.elapsedRealtime()
    PhoneExecutionAuthority.clearCancellation(sessionId)
    val requestedGoal = goal.trim()
    activeConversationContext = conversationContext
    activeConversationTurnId = turnId
    when {
        retryTaskCommand(requestedGoal) -> return retryFailedAction()
        approveTaskCommand(requestedGoal) -> return approveNextAction()
        pauseTaskCommand(requestedGoal) -> return pauseCurrentTask()
        resumeTaskCommand(requestedGoal) -> return continueCurrentTask()
        replanTaskCommand(requestedGoal) -> return replanCurrentTask()
        rollbackTaskCommand(requestedGoal) -> return rollbackLastAction()
        cancelTaskCommand(requestedGoal) -> return cancelCurrentTask()
    }
    currentGoal = requestedGoal
    invalidateRuntimeContext()
    if (currentGoal.isBlank()) {
        return observeCurrentScreen()
    }
    activeTaskExecutionMode = executionMode ?: AgentTaskExecutionModePolicy.resolve(
        requestedGoal,
        safetySettingsStore.load().taskExecutionMode
    ).mode

    return try {
        if (!startExecutionLoop(turnId)) return snapshot()
        Log.i(
            "SignalASILatency",
            "agent_execute stage=loop_started turn=${turnId.take(8)} " +
                "elapsed_ms=${SystemClock.elapsedRealtime() - submitStartedAt}"
        )
        reconcileExecutionLoop(executeSubmittedGoal())
    } catch (failure: CancellationException) {
        runCatching {
            advanceExecutionLoop(
                AgentExecutionLoopPhase.CANCELLED,
                "Task cancellation requested"
            )
        }
        throw failure
    } catch (failure: Throwable) {
        advanceExecutionLoop(
            AgentExecutionLoopPhase.FAILED,
            failure.message.orEmpty().ifBlank { "Agent execution failed" }
        )
        throw failure
    }
}

internal fun MobileNativeAgent.executeSubmittedGoal(): AgentUiState {
    val planningStartedAt = SystemClock.elapsedRealtime()
    var stageStartedAt = planningStartedAt
    currentScreen = if (
        screenObservationOverride ?: AgentScreenObservationPolicy.requiresObservation(currentGoal)
    ) {
        captureScreen()
    } else {
        ScreenContext(foregroundApp = "", pageTitle = "")
    }
    logPlanningLatency("screen", stageStartedAt, planningStartedAt)
    stageStartedAt = SystemClock.elapsedRealtime()
    permissionModeCommandValue(currentGoal)?.let { mode ->
        return setPermissionModeCommand(mode)
    }
    highRiskGuardCommandValue(currentGoal)?.let { enabled ->
        return setHighRiskGuardCommand(enabled)
    }
    if (activeTaskExecutionMode != AgentTaskExecutionMode.PLAN_ONLY) {
    callableInventoryCommand(currentGoal)?.let { filter ->
        return showCallableInventoryCommand(filter)
    }
    callableSearchCommandValue(currentGoal)?.let { query ->
        return searchCallableInventoryCommand(query)
    }
    if (screenOverviewCommand(currentGoal)) {
        return showScreenOverviewCommand()
    }
    screenSearchCommandValue(currentGoal)?.let { query ->
        return searchCurrentScreenCommand(query)
    }
    if (homeAssistantStatusCommand(currentGoal)) {
        return showHomeAssistantStatusCommand()
    }
    if (homeAssistantEntitiesCommand(currentGoal)) {
        return showHomeAssistantEntitiesCommand()
    }
    homeAssistantCollectionCommand(currentGoal)?.let { collection ->
        return showHomeAssistantCollectionCommand(collection)
    }
    homeAssistantEntitySearchCommandValue(currentGoal)?.let { query ->
        return searchHomeAssistantEntitiesCommand(query)
    }
    homeAssistantEntityReadCommandValue(currentGoal)?.let { entityId ->
        return readHomeAssistantEntityCommand(entityId)
    }
    if (notificationInboxCommand(currentGoal)) {
        return showNotificationInboxCommand()
    }
    notificationSearchCommandValue(currentGoal)?.let { query ->
        return searchNotificationsCommand(query)
    }
    if (permissionChecklistCommand(currentGoal)) {
        return showPermissionChecklistCommand()
    }
    if (securityStatusCommand(currentGoal)) {
        return showSecurityStatusCommand()
    }
    if (auditTrailCommand(currentGoal)) {
        return showAuditTrailCommand()
    }
    if (clearTaskHistoryCommand(currentGoal)) {
        return clearTaskHistoryCommand()
    }
    if (recentTasksCommand(currentGoal)) {
        return showRecentTasksCommand()
    }
    taskSearchCommandValue(currentGoal)?.let { query ->
        return searchTasksCommand(query)
    }
    workflowSaveCommandValue(currentGoal)?.let { (name, workflowGoal) ->
        return saveWorkflowCommand(name, workflowGoal)
    }
    if (workflowSaveSyntaxCommand(currentGoal)) {
        return completeWorkflowManagementCommand(
            actionId = "save-workflow-syntax",
            description = "Show workflow save syntax",
            result = "Use: save workflow Name :: goal",
            risk = AgentRisk.LOW,
            parameters = emptyMap()
        )
    }
    if (workflowListCommand(currentGoal)) {
        return showWorkflowsCommand()
    }
    if (workflowHistoryListCommand(currentGoal)) {
        return showWorkflowHistoryCommand()
    }
    workflowTriggerConditionCommandValue(currentGoal)?.let { request ->
        return attachWorkflowTriggerConditionCommand(request)
    }
    workflowTriggerConditionsClearCommandValue(currentGoal)?.let { triggerId ->
        return clearWorkflowTriggerConditionsCommand(triggerId)
    }
    if (workflowTriggerConditionSyntaxCommand(currentGoal)) {
        return completeWorkflowManagementCommand(
            actionId = "workflow-trigger-condition-syntax",
            description = "Show workflow trigger condition syntax",
            result = "Use: add trigger condition TRIGGER_ID :: charging, battery at least 50%, network available, or time 09:00-17:00",
            risk = AgentRisk.LOW,
            parameters = emptyMap()
        )
    }
    workflowTriggerCreateCommandValue(currentGoal)?.let { request ->
        return createWorkflowTriggerCommand(request)
    }
    if (workflowTriggerCreateSyntaxCommand(currentGoal)) {
        return completeWorkflowManagementCommand(
            actionId = "create-workflow-trigger-syntax",
            description = "Show workflow trigger syntax",
            result = "Use: trigger workflow Name when notification package com.example, notification text contains words, charging, or battery low",
            risk = AgentRisk.LOW,
            parameters = emptyMap()
        )
    }
    if (workflowTriggerListCommand(currentGoal)) {
        return showWorkflowTriggersCommand()
    }
    workflowTriggerDeleteCommandValue(currentGoal)?.let { triggerId ->
        return deleteWorkflowTriggerCommand(triggerId)
    }
    workflowDeleteCommandValue(currentGoal)?.let { name ->
        return deleteWorkflowCommand(name)
    }
    workflowRunCommandValue(currentGoal)?.let { name ->
        return runWorkflowCommand(name)
    }
    workflowScheduleCommandValue(currentGoal)?.let { request ->
        return scheduleWorkflowCommand(request)
    }
    if (workflowScheduleSyntaxCommand(currentGoal)) {
        return completeWorkflowManagementCommand(
            actionId = "schedule-workflow-syntax",
            description = "Show workflow schedule syntax",
            result = "Use: schedule workflow Name at HH:mm, or schedule workflow Name every 30 minutes",
            risk = AgentRisk.LOW,
            parameters = emptyMap()
        )
    }
    if (workflowScheduleListCommand(currentGoal)) {
        return showWorkflowSchedulesCommand()
    }
    workflowScheduleCancelCommandValue(currentGoal)?.let { name ->
        return cancelWorkflowScheduleCommand(name)
    }
    if (templateListCommand(currentGoal)) {
        return showTemplatesCommand()
    }
    templateRunCommandValue(currentGoal)?.let { name ->
        return runTemplateCommand(name)
    }
    if (memoryOverviewCommand(currentGoal)) {
        return showMemoryOverviewCommand()
    }
    if (knowledgeOverviewCommand(currentGoal)) {
        return showKnowledgeOverviewCommand()
    }
    knowledgeAnswerCommandValue(currentGoal)?.let { query ->
        return prepareKnowledgeAnswerCommand(query)
    }
    memoryCaptureCommandValue(currentGoal)?.let { enabled ->
        return setMemoryCaptureCommand(enabled)
    }
    memoryCommandValue(currentGoal)?.let { memoryValue ->
        return saveMemoryCommand(memoryValue)
    }
    forgetMemoryCommandValue(currentGoal)?.let { query ->
        return forgetMemoryCommand(query)
    }
    forgetKnowledgeCommandValue(currentGoal)?.let { query ->
        return forgetKnowledgeCommand(query)
    }
    knowledgeSearchCommandValue(currentGoal)?.let { query ->
        return searchKnowledgeCommand(query)
    }
    }
    logPlanningLatency("commands", stageStartedAt, planningStartedAt)
    stageStartedAt = SystemClock.elapsedRealtime()
    val targets = connectorRegistry.availableTargets()
    logPlanningLatency("targets", stageStartedAt, planningStartedAt)
    stageStartedAt = SystemClock.elapsedRealtime()
    val memories = if (activeConversationContext.privateMode) emptyList() else memoryStore.recall(currentGoal)
    logPlanningLatency("memory", stageStartedAt, planningStartedAt)
    stageStartedAt = SystemClock.elapsedRealtime()
    val knowledge = knowledgeStore.querySnapshot(currentGoal)
    val knowledgeItems = knowledge.items
    logPlanningLatency("knowledge", stageStartedAt, planningStartedAt)
    stageStartedAt = SystemClock.elapsedRealtime()
    val context = buildRuntimeContext(
        goal = currentGoal,
        screen = currentScreen,
        targets = targets,
        memories = memories,
        knowledgeItems = knowledgeItems,
        knowledgeStats = knowledge.stats
    ).also(::cacheRuntimeContext)
    logPlanningLatency("context", stageStartedAt, planningStartedAt)
    stageStartedAt = SystemClock.elapsedRealtime()
    val planned = planner.plan(
        request = AgentRequest(
            goal = currentGoal,
            screen = currentScreen,
            targets = targets,
            memories = memories,
            runtimeContext = context,
            conversationContext = activeConversationContext
        )
    )
    logPlanningLatency("planner", stageStartedAt, planningStartedAt)
    stageStartedAt = SystemClock.elapsedRealtime()
    val conversationPrompt = activeConversationContext.asTransportBlock(maximumTokens = 10_000)
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
        modelPlannerSettings().shareScreenText && currentScreen.sensitiveFlagCount == 0
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
        enabled = modelPlannerSettings().multiAgentCoordination,
        registrations = connectorRegistry.registrations(),
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
        phase = AgentPhase.COMPLETED
        lastActionResult = AgentActionResult(
            actionId = "plan-only",
            success = true,
            message = renderPlanOnlyResult(currentPlan!!)
        )
        recordAudit(
            AgentAuditEvent.REASONING_SUMMARY,
            "execution_mode=plan_only; actions=${currentPlan!!.actions.size}; " +
                "risk=${currentPlan!!.safetyReview.risk.name}"
        )
        recordAudit(AgentAuditEvent.GOAL_RECEIVED, goalAuditDetail(currentGoal))
        saveTaskRecord()
        persistSession()
        return snapshot()
    }
    currentPlan = draftPlan.withSafetyReview(safetyReview)
    recordAudit(
        AgentAuditEvent.INVOCATION_AUDIT,
        "planner=${draftPlan.plannerProfile}; actions=${draftPlan.actions.size}; valid=${draftPlan.validation.valid}"
    )
    recordAudit(
        AgentAuditEvent.REASONING_SUMMARY,
        "route=${draftPlan.selectedAgentOrModel.take(160)}; actions=${draftPlan.actions.size}; profile=${draftPlan.plannerProfile.take(120)}"
    )
    phase = when {
        safetyReview.blocked -> AgentPhase.BLOCKED
        safetyReview.requiresConfirmation -> AgentPhase.WAITING_CONFIRMATION
        else -> AgentPhase.PLANNING
    }
    lastActionResult = null
    val memoryBlockReason = if (activeConversationContext.privateMode) {
        "Private session is excluded from long-term memory"
    } else if (isPrivateCommunicationGoal(currentGoal)) {
        "Private communication is excluded from long-term memory"
    } else {
        memoryBlockReason(currentGoal, currentScreen)
    }
    if (memoryBlockReason != null) {
        recordAudit(AgentAuditEvent.MEMORY_SKIPPED, memoryBlockReason)
    } else {
        recordAudit(
            AgentAuditEvent.MEMORY_SKIPPED,
            "Task context remains session-scoped until the user explicitly saves it"
        )
    }
    recordAudit(AgentAuditEvent.GOAL_RECEIVED, goalAuditDetail(currentGoal))
    if (safetyReview.blocked) {
        recordAudit(AgentAuditEvent.ACTION_BLOCKED, safetyReview.reason.ifBlank { "blocked" })
    }
    if (!safetyReview.blocked && !safetyReview.requiresConfirmation) {
        return executeFirstPendingAction()
    }
    saveTaskRecord()
    return snapshot()
}

internal fun MobileNativeAgent.approveNextAction(
    highRiskConfirmed: Boolean = false,
    permissionChoice: AgentPermissionChoice = AgentPermissionChoice.ALLOW_ONCE
): AgentUiState = reconcileExecutionLoop(
    approveNextActionInternal(highRiskConfirmed, permissionChoice)
)

internal fun MobileNativeAgent.approveNextActionInternal(
    @Suppress("UNUSED_PARAMETER") highRiskConfirmed: Boolean,
    @Suppress("UNUSED_PARAMETER") permissionChoice: AgentPermissionChoice
): AgentUiState {
    val plan = currentPlan ?: return snapshot()
    if (phase == AgentPhase.PAUSED) return snapshot()
    val hardenedPlan = AgentActionRiskHardener.enforce(appContext, plan)
    val preparedPlan = hardenedPlan
        .blockActionsWithFailedDependencies()
        .let { it.withSafetyReview(safetyPolicy.review(it, sessionId)) }
    currentPlan = preparedPlan
    if (preparedPlan.safetyReview.blocked) {
        phase = AgentPhase.BLOCKED
        lastActionResult = AgentActionResult(
            actionId = "safety-policy",
            success = false,
            message = preparedPlan.safetyReview.reason.ifBlank { "Action blocked by safety policy" }
        )
        recordAudit(AgentAuditEvent.ACTION_BLOCKED, preparedPlan.safetyReview.reason.ifBlank { "blocked" })
        saveTaskRecord()
        return snapshot()
    }
    val nextAction = preparedPlan.nextRunnableAction() ?: return noRunnableActionState(preparedPlan)
    return executePlannedAction(preparedPlan, nextAction, userConfirmed = false)
}

internal fun MobileNativeAgent.executeFirstPendingAction(): AgentUiState {
    val originalPlan = currentPlan ?: return snapshot()
    val normalization = AgentPlanLifecyclePolicy.normalize(originalPlan)
    val plan = normalization.plan
    if (normalization.changed) {
        currentPlan = plan
        lastActionResult = normalization.recoverResult(lastActionResult)
        recordAudit(
            AgentAuditEvent.INVOCATION_AUDIT,
            "removed_trailing_draft_actions=${normalization.removedActions.joinToString(",", transform = AgentAction::id)}"
        )
        if (plan.actions.none {
                it.status == AgentActionStatus.PENDING_CONFIRMATION ||
                    it.status == AgentActionStatus.PROPOSED ||
                    it.status == AgentActionStatus.RUNNING ||
                    it.status == AgentActionStatus.WAITING_RESPONSE
            }
        ) {
            phase = AgentPhase.COMPLETED
            saveTaskRecord(result = lastActionResult?.message.orEmpty())
            return snapshot()
        }
    }
    val hardenedPlan = AgentActionRiskHardener.enforce(appContext, plan)
    val preparedPlan = hardenedPlan
        .blockActionsWithFailedDependencies()
        .let { it.withSafetyReview(safetyPolicy.review(it, sessionId)) }
    currentPlan = preparedPlan
    if (preparedPlan.safetyReview.blocked || preparedPlan.safetyReview.requiresConfirmation) {
        phase = if (preparedPlan.safetyReview.blocked) AgentPhase.BLOCKED else AgentPhase.WAITING_CONFIRMATION
        persistSession()
        return snapshot()
    }
    val nextAction = preparedPlan.nextRunnableAction() ?: return noRunnableActionState(preparedPlan)
    return executePlannedAction(preparedPlan, nextAction, userConfirmed = false)
}

internal fun MobileNativeAgent.noRunnableActionState(plan: AgentPlan): AgentUiState {
    val hasPending = plan.actions.any {
        it.status == AgentActionStatus.PENDING_CONFIRMATION || it.status == AgentActionStatus.PROPOSED
    }
    if (hasPending) {
        phase = AgentPhase.BLOCKED
        lastActionResult = AgentActionResult(
            actionId = "agent-tool-graph-blocked",
            success = false,
            message = "No task-graph node has satisfied dependencies"
        )
        recordAudit(AgentAuditEvent.TOOL_GRAPH_BLOCKED, "revision=${plan.revision}")
    }
    persistSession()
    return snapshot()
}

internal fun MobileNativeAgent.executePlannedAction(
    plan: AgentPlan,
    nextAction: AgentAction,
    userConfirmed: Boolean,
    retrying: Boolean = false,
    trustedHandoffReplay: Boolean = false
): AgentUiState {
    val executionStartedAt = SystemClock.elapsedRealtime()
    // A handoff replay sends the exact connector action that already crossed policy checks.
    // Re-running those checks can turn a transport recovery into a new blocked user action.
    val hardenedPlan = if (trustedHandoffReplay) plan else AgentActionRiskHardener.enforce(appContext, plan)
    val hardenedAction = hardenedPlan.actions.firstOrNull { it.id == nextAction.id } ?: nextAction
    val reviewedPlan = if (trustedHandoffReplay) {
        hardenedPlan.copy(
            safetyReview = hardenedPlan.safetyReview.copy(
                requiresConfirmation = false,
                blocked = false,
                mode = PermissionMode.FULL_ACCESS,
                deniedPermissions = emptyList(),
                warnings = emptyList(),
                reason = ""
            )
        )
    } else {
        hardenedPlan.withSafetyReview(safetyPolicy.review(hardenedPlan, sessionId))
    }
    currentPlan = reviewedPlan
    if (reviewedPlan.safetyReview.blocked) {
        phase = if (safetySettingsStore.load().executionPaused) AgentPhase.PAUSED else AgentPhase.BLOCKED
        val reason = reviewedPlan.safetyReview.reason.ifBlank { "Action blocked by current capability settings" }
        lastActionResult = AgentActionResult(hardenedAction.id, false, reason)
        recordAudit(AgentAuditEvent.ACTION_BLOCKED, "execution_recheck:${hardenedAction.id}:$reason")
        saveTaskRecord()
        return snapshot()
    }
    val autonomySettings = AgentModelPlannerSettingsStore(appContext).load()
    val autonomyDecision = if (trustedHandoffReplay) {
        AgentAutonomyDecision(allowed = true)
    } else {
        AgentAutonomyGuard.review(reviewedPlan, hardenedAction, autonomySettings)
    }
    if (!autonomyDecision.allowed) {
        phase = AgentPhase.BLOCKED
        lastActionResult = AgentActionResult(hardenedAction.id, false, autonomyDecision.reason)
        currentPlan = reviewedPlan.markAction(hardenedAction.id, AgentActionStatus.BLOCKED, lastActionResult)
        recordAudit(
            AgentAuditEvent.AUTONOMY_GUARD_BLOCKED,
            "action=${hardenedAction.id}; calls=${autonomyDecision.completedToolCalls}; repeated=${autonomyDecision.repeatedCalls}"
        )
        saveTaskRecord()
        return snapshot()
    }
    if (!advanceExecutionLoop(
            nextPhase = AgentExecutionLoopPhase.ACT,
            reason = hardenedAction.description.ifBlank { hardenedAction.kind.name },
            actionId = hardenedAction.id,
            toolCall = hardenedAction.kind in setOf(
                AgentActionKind.CALL_NATIVE_TOOL,
                AgentActionKind.CALL_CONNECTOR,
                AgentActionKind.CONTROL_DEVICE
            ),
            retry = retrying
        )
    ) {
        return snapshot()
    }
    Log.i(
        "SignalASILatency",
        "agent_execute stage=act_recorded action=${hardenedAction.id.take(24)} " +
            "elapsed_ms=${SystemClock.elapsedRealtime() - executionStartedAt}"
    )
    phase = AgentPhase.EXECUTING
    currentPlan = reviewedPlan.markAction(hardenedAction.id, AgentActionStatus.RUNNING)
    if (AgentScreenObservationPolicy.requiresObservation(currentGoal, hardenedAction)) {
        currentScreen = captureScreen()
    }
    val executionScreen = currentScreen
    val checkpoint = AgentExecutionContinuity.checkpointBefore(
        action = hardenedAction,
        screen = executionScreen,
        planRevision = reviewedPlan.revision
    )
    currentPlan = currentPlan?.addCheckpoint(checkpoint)
    recordAudit(
        AgentAuditEvent.CHECKPOINT_SAVED,
        "checkpoint=${checkpoint.id}; action=${hardenedAction.id}; rollback=${checkpoint.rollbackAction != null}"
    )
    Log.i(
        "SignalASILatency",
        "agent_execute stage=checkpoint_recorded action=${hardenedAction.id.take(24)} " +
            "elapsed_ms=${SystemClock.elapsedRealtime() - executionStartedAt}"
    )
    val materializedAction = currentPlan?.materializeToolInput(
        action = hardenedAction,
        allowOutputHandoff = AgentModelPlannerSettingsStore(appContext).load().multiAgentCoordination ||
            hardenedAction.isSupervisedProjectConnector()
    ) ?: hardenedAction
    val routedAction = refreshAutomaticConnectorRoute(materializedAction)
    val executionAction = routedAction.copy(
        parameters = routedAction.parameters + mapOf(
            "original_goal" to currentGoal,
            "_signalasi_task_id" to sessionId
        )
    ).enforceSupervisedPlanningBoundary()
    val displayCommand = executionAction.phoneDevelopmentDisplayCommand()
    if (executionAction.parameters["prompt"] != hardenedAction.parameters["prompt"]) {
        recordAudit(
            AgentAuditEvent.TOOL_OUTPUT_HANDOFF,
            "action=${hardenedAction.id}; sources=${hardenedAction.outputSourceIds().size}; target=${hardenedAction.target}"
        )
    }
    val toolStartedAt = System.currentTimeMillis()
    recordAudit(
        AgentAuditEvent.TOOL_STARTED,
        "action=${hardenedAction.id}; kind=${hardenedAction.kind}; target=${hardenedAction.target.take(160)}" +
            (if (executionAction.isSupervisedProjectConnector()) "; planning_only=true" else "") +
            displayCommand.takeIf(String::isNotBlank)?.let { "; command=${it.take(200)}" }.orEmpty()
    )
    Log.i(
        "SignalASILatency",
        "agent_execute stage=dispatch_start action=${hardenedAction.id.take(24)} " +
            "elapsed_ms=${SystemClock.elapsedRealtime() - executionStartedAt}"
    )
    lastActionResult = executeAction(executionAction, currentScreen, userConfirmed)
    Log.i(
        "SignalASILatency",
        "agent_execute stage=dispatch_return action=${hardenedAction.id.take(24)} " +
            "success=${lastActionResult?.success == true} " +
            "elapsed_ms=${SystemClock.elapsedRealtime() - executionStartedAt}"
    )
    val dispatchAwaitingResponse = lastActionResult?.metadata?.get("awaiting_response") == "true"
    recordAudit(
        AgentAuditEvent.TOOL_COMPLETED,
        "action=${hardenedAction.id}; kind=${hardenedAction.kind}; " +
            "awaiting_response=$dispatchAwaitingResponse; success=${lastActionResult?.success == true}; " +
            "duration_ms=${System.currentTimeMillis() - toolStartedAt}; target=${hardenedAction.target.take(160)}"
    )
    Log.i(
        "SignalASILatency",
        "agent_execute stage=dispatch_persisted action=${hardenedAction.id.take(24)} " +
            "elapsed_ms=${SystemClock.elapsedRealtime() - executionStartedAt}"
    )
    if (AgentTaskCompletionPolicy.closesFromVerifiedEvidence(executionAction) &&
        lastActionResult?.success == true
    ) {
        return completeVerifiedTaskMarker(hardenedAction)
    }
    if (!advanceExecutionLoop(
            nextPhase = AgentExecutionLoopPhase.OBSERVE,
            reason = "Observing action outcome",
            actionId = hardenedAction.id
        )
    ) {
        Log.w(
            "SignalASIAgentLifecycle",
            "Stopped before observation action=${hardenedAction.id.take(32)} " +
                "loop=${executionLoopSnapshot()?.phase} phase=$phase"
        )
        return snapshot()
    }
    Log.i(
        "SignalASILatency",
        "agent_execute stage=observe_started action=${hardenedAction.id.take(24)} " +
            "elapsed_ms=${SystemClock.elapsedRealtime() - executionStartedAt}"
    )
    phase = AgentPhase.VERIFYING
    val observation = captureVerificationScreen(
        action = hardenedAction,
        beforeAction = executionScreen,
        actionResult = lastActionResult
    )
    currentScreen = observation.screen
    lastActionResult = applyObservationResult(hardenedAction, lastActionResult, observation)
    Log.i(
        "SignalASILatency",
        "agent_execute stage=observe_completed action=${hardenedAction.id.take(24)} " +
            "decision=${observation.decision} elapsed_ms=${SystemClock.elapsedRealtime() - executionStartedAt}"
    )
    val recovery = recoverActionIfSafe(hardenedAction, lastActionResult, observation)
    currentScreen = recovery.observation.screen
    lastActionResult = applyRecoveryMetadata(recovery.result, recovery)
    val awaitingResponse = lastActionResult?.metadata?.get("awaiting_response") == "true"
    val finalStatus = when {
        lastActionResult?.success != true -> AgentActionStatus.FAILED
        awaitingResponse -> AgentActionStatus.WAITING_RESPONSE
        else -> AgentActionStatus.COMPLETED
    }
    val observedPlan = currentPlan
        ?.addArtifactRichOutput(lastActionResult?.metadata?.get("rich_output").orEmpty())
        ?.markAction(hardenedAction.id, finalStatus, lastActionResult)
        ?.addVerification(AgentVerificationResult.from(hardenedAction.id, lastActionResult, recovery))
    if (observedPlan != null) {
        val observedResult = lastActionResult
        if (observedResult != null) {
            val verifiedCompletion = AgentSupervisedProjectCompletionPolicy.verifiedTerminalOutcome(
                goal = currentGoal,
                history = observedPlan.actionHistory + observedPlan.actions,
                completedAction = hardenedAction,
                result = observedResult
            )
            if (verifiedCompletion != null) {
                return completeVerifiedProjectOutcome(
                    plan = observedPlan,
                    action = hardenedAction,
                    result = observedResult,
                    completion = verifiedCompletion
                )
            }
        }
    }
    val updatedPlan = observedPlan?.let { candidate ->
        ensureSupervisedProjectContinuation(candidate, hardenedAction, lastActionResult)
    }
    Log.i(
        "SignalASIAgentLifecycle",
        "Observed action=${hardenedAction.id.take(32)} success=${lastActionResult?.success == true} " +
            "next=${updatedPlan?.nextRunnableAction()?.id.orEmpty().take(32)} " +
            "supervised=${updatedPlan?.isSupervisedProjectPlan() == true}"
    )
    val hasPendingBeforeReplan = updatedPlan?.actions?.any {
        it.status == AgentActionStatus.PENDING_CONFIRMATION || it.status == AgentActionStatus.PROPOSED
    } == true
    val preservesToolGraph = updatedPlan?.hasOutputHandoffFrom(hardenedAction.id) == true
    val specializedContinuation = updatedPlan?.plannerProfile?.startsWith("specialized-adapter:") == true &&
        hardenedAction.requiresSpecializedContinuation()
    val replanReason = when {
        lastActionResult?.success != true &&
            lastActionResult?.metadata?.get("non_retriable") == "true" -> ""
        lastActionResult?.success != true && updatedPlan?.isSupervisedProjectPlan() == true ->
            PHONE_SUPERVISED_PROJECT_REPLAN_REASON
        lastActionResult?.success != true && hardenedAction.isPhoneDevelopmentRuntimeHandoff() ->
            PHONE_DEVELOPMENT_REPLAN_REASON
        lastActionResult?.success != true -> "action_failed:${hardenedAction.kind.name}"
        specializedContinuation -> "specialized_step_completed:${hardenedAction.id}"
        hasPendingBeforeReplan && hardenedAction.kind.mayChangeScreen() && !preservesToolGraph ->
            "screen_updated_after:${hardenedAction.kind.name}"
        else -> ""
    }
    if (lastActionResult?.success != true && replanReason.isNotBlank()) {
        val failureReason = lastActionResult?.message.orEmpty().ifBlank { replanReason }
        if (!recordExecutionFailure(
                failureClass = AgentActionFailureIdentity.failureClass(hardenedAction),
                reason = failureReason,
                actionId = hardenedAction.id
            )
        ) {
            return snapshot()
        }
    }
    val continuedPlan = if (updatedPlan != null && replanReason.isNotBlank()) {
        if (!advanceExecutionLoop(
                nextPhase = AgentExecutionLoopPhase.REPLAN,
                reason = replanReason,
                actionId = hardenedAction.id
            )
        ) {
            return snapshot()
        }
        replanFromCurrentState(updatedPlan, replanReason) ?: updatedPlan
    } else {
        updatedPlan
    }
    currentPlan = continuedPlan
    recordAudit(AgentAuditEvent.SCREEN_VERIFIED, recovery.observation.evidence)
    val hasNextAction = continuedPlan?.actions?.any {
        it.status == AgentActionStatus.PENDING_CONFIRMATION || it.status == AgentActionStatus.PROPOSED
    } == true
    phase = when {
        safetySettingsStore.load().executionPaused -> AgentPhase.PAUSED
        continuedPlan?.safetyReview?.blocked == true -> AgentPhase.BLOCKED
        lastActionResult?.success != true && continuedPlan === updatedPlan -> AgentPhase.FAILED
        awaitingResponse -> AgentPhase.WAITING_RESPONSE
        hasNextAction && continuedPlan?.safetyReview?.requiresConfirmation == false -> {
            recordAudit(AgentAuditEvent.INVOCATION_AUDIT, invocationAuditDetail(continuedPlan, hardenedAction, lastActionResult, userConfirmed))
            recordAudit(AgentAuditEvent.ACTION_EXECUTED, "action:${hardenedAction.kind}:${finalStatus}")
            saveTaskRecord()
            return executeFirstPendingAction()
        }
        hasNextAction -> AgentPhase.WAITING_CONFIRMATION
        else -> AgentPhase.COMPLETED
    }
    continuedPlan?.let { recordAudit(AgentAuditEvent.INVOCATION_AUDIT, invocationAuditDetail(it, hardenedAction, lastActionResult, userConfirmed)) }
    recordAudit(AgentAuditEvent.ACTION_EXECUTED, "action:${hardenedAction.kind}:${finalStatus}")
    saveTaskRecord()
    return snapshot()
}

internal fun MobileNativeAgent.refreshAutomaticConnectorRoute(action: AgentAction): AgentAction {
    if (action.kind != AgentActionKind.CALL_CONNECTOR ||
        action.parameters["manual_target_locked"] == "true" ||
        action.parameters[AGENT_TEAM_SPEC_PARAMETER].orEmpty().isNotBlank()
    ) {
        return action
    }
    val targets = connectorRegistry.availableTargets()
    val routing = AgentResourceRouter(appContext).route(
        goal = currentGoal,
        targets = targets,
        tools = emptyList()
    )
    val selection = AgentConnectorRouteSelector.select(
        targets = targets,
        decision = routing
    ) ?: return action
    val selected = selection.target
    val fallbackIds = selection.decision?.fallbacks.orEmpty()
        .map { candidate -> candidate.resource.targetId }
        .filter(String::isNotBlank)
        .distinct()
    Log.i(
        "SignalASIAgentRoute",
        "dispatch_refresh action=${action.id.take(32)} selected=${selected.id} " +
            "fallbacks=${fallbackIds.joinToString(",")}"
    )
    return action.copy(
        target = selected.title,
        parameters = action.parameters + mapOf(
            "connector_id" to selected.id,
            "connector_kind" to selected.kind.name.lowercase(Locale.ROOT),
            "connector_adapter_type" to selected.adapterType,
            "connector_failure_domain" to selected.failureDomain,
            "routing_fallback_ids" to fallbackIds.joinToString(","),
            "manual_target_locked" to "false"
        )
    )
}

internal fun MobileNativeAgent.ensureSupervisedProjectContinuation(
    plan: AgentPlan,
    completedAction: AgentAction,
    result: AgentActionResult?
): AgentPlan {
    if (!plan.isSupervisedProjectPlan() ||
        completedAction.kind != AgentActionKind.CALL_NATIVE_TOOL ||
        result?.success != true ||
        result.metadata["awaiting_response"] == "true" ||
        !AgentSupervisedProjectLoop.needsRunnableReviewer(plan)
    ) {
        return plan
    }
    val connector = (plan.actionHistory + plan.actions)
        .lastOrNull(AgentAction::isSupervisedProjectConnector)
        ?: return plan
    val request = supervisedProjectRequest(plan, continuation = true)
    val routing = AgentResourceRouter(appContext).route(
        goal = currentGoal,
        targets = request.targets,
        tools = emptyList()
    )
    val routeSelection = AgentConnectorRouteSelector.select(
        targets = request.targets,
        decision = routing
    )
    val selectedTarget = routeSelection?.target
    val fallbackIds = routeSelection?.decision?.fallbacks.orEmpty()
        .map { candidate -> candidate.resource.targetId }
        .filter(String::isNotBlank)
        .distinct()
    val routedConnector = connector.copy(
        target = selectedTarget?.title ?: connector.target,
        parameters = connector.parameters + mapOf(
            "connector_id" to (selectedTarget?.id
                ?: connector.parameters["connector_id"].orEmpty()),
            "connector_kind" to (selectedTarget?.kind?.name?.lowercase(Locale.ROOT)
                ?: connector.parameters["connector_kind"].orEmpty()),
            "connector_adapter_type" to (selectedTarget?.adapterType
                ?: connector.parameters["connector_adapter_type"].orEmpty()),
            "connector_failure_domain" to (selectedTarget?.failureDomain
                ?: connector.parameters["connector_failure_domain"].orEmpty()),
            "routing_fallback_ids" to fallbackIds.joinToString(","),
            "manual_target_locked" to "false"
        )
    )
    val appended = AgentSupervisedProjectLoop.appendReviewer(
        plan = plan,
        connector = routedConnector,
        request = request,
        idSuffix = "recovered-${plan.revision + 1}-${completedAction.id.take(24)}"
    )
    if (appended.actions.size <= plan.actions.size) return plan
    val recovered = appended.copy(
        revision = plan.revision + 1,
        replanCount = plan.replanCount + 1
    ).let { candidate ->
        candidate.copy(validation = AgentPlanValidator.validate(candidate))
    }
    val reviewed = AgentActionRiskHardener.enforce(appContext, recovered).let { hardened ->
        hardened.withSafetyReview(safetyPolicy.review(hardened, sessionId))
    }
    recordAudit(
        AgentAuditEvent.INVOCATION_AUDIT,
        "restored_missing_supervised_reviewer:after=${completedAction.id}; revision=${reviewed.revision}"
    )
    Log.i(
        "SignalASIAgentLifecycle",
        "Restored runnable supervised reviewer after=${completedAction.id.take(32)} " +
            "revision=${reviewed.revision}"
    )
    return reviewed
}

internal fun MobileNativeAgent.completeVerifiedTaskMarker(action: AgentAction): AgentUiState {
    val result = lastActionResult ?: AgentActionResult(
        actionId = action.id,
        success = true,
        message = action.description.ifBlank { "Task completed" }
    )
    currentPlan = currentPlan?.markAction(action.id, AgentActionStatus.COMPLETED, result)
    if (!advanceExecutionLoop(
            nextPhase = AgentExecutionLoopPhase.OBSERVE,
            reason = "Completion marker accepted after the verified tool observation",
            actionId = action.id
        )
    ) {
        return snapshot()
    }
    if (!advanceExecutionLoop(
            nextPhase = AgentExecutionLoopPhase.VERIFY,
            reason = "Verified execution evidence supports the final result",
            actionId = action.id
        )
    ) {
        return snapshot()
    }
    phase = AgentPhase.COMPLETED
    lastActionResult = result
    recordAudit(AgentAuditEvent.ACTION_EXECUTED, "action:${action.kind}:${AgentActionStatus.COMPLETED}")
    saveTaskRecord(result = result.message)
    Log.i(
        "SignalASILatency",
        "agent_execute stage=completion_marker_closed action=${action.id.take(24)}"
    )
    return snapshot()
}

internal fun MobileNativeAgent.completeVerifiedProjectOutcome(
    plan: AgentPlan,
    action: AgentAction,
    result: AgentActionResult,
    completion: AgentVerifiedProjectCompletion
): AgentUiState {
    val finalResult = result.copy(
        message = completion.message,
        metadata = result.metadata + mapOf(
            "verified_terminal_outcome" to "true",
            "terminal_tool_id" to completion.terminalToolId,
            "terminal_evidence" to completion.evidence
        )
    )
    currentPlan = plan.markAction(action.id, AgentActionStatus.COMPLETED, finalResult)
    lastActionResult = finalResult
    if (!advanceExecutionLoop(
            nextPhase = AgentExecutionLoopPhase.VERIFY,
            reason = "Authoritative phone tool evidence proves the model-selected outcome",
            actionId = action.id
        )
    ) {
        return snapshot()
    }
    phase = AgentPhase.COMPLETED
    recordAudit(
        AgentAuditEvent.SCREEN_VERIFIED,
        "verified_terminal_outcome:tool=${completion.terminalToolId}; evidence=${completion.evidence.take(2_000)}"
    )
    recordAudit(AgentAuditEvent.ACTION_EXECUTED, "action:${action.kind}:${AgentActionStatus.COMPLETED}")
    saveTaskRecord(result = finalResult.message)
    Log.i(
        "SignalASILatency",
        "agent_execute stage=verified_terminal_outcome tool=${completion.terminalToolId.take(48)}"
    )
    return snapshot()
}

internal fun MobileNativeAgent.acceptConnectorResponseInternal(
    sourceMessageId: Long,
    contactId: String,
    content: String,
    success: Boolean,
    richOutputJson: String,
    conversationId: String,
    turnId: String,
    taskId: String,
    inputTokens: Long,
    outputTokens: Long,
    costMicros: Long,
    networkBytes: Long,
    expectedSourceMessageId: Long = sourceMessageId
): AgentUiState? {
    if (sourceMessageId <= 0L) return null
    val pendingResult = lastActionResult ?: return null
    val expectedSource = expectedSourceMessageId.takeIf { it > 0L } ?: sourceMessageId
    val recoveringTimeout = success && isRecoverableConnectorTimeout(pendingResult, expectedSource)
    if (phase != AgentPhase.WAITING_RESPONSE && !recoveringTimeout) return null
    if (pendingResult.metadata["source_message_id"]?.toLongOrNull() != expectedSource) return null
    val expectedContactId = pendingResult.metadata["contact_id"].orEmpty()
    if (expectedContactId.isNotBlank() && contactId.isNotBlank() && expectedContactId != contactId) return null
    if (!AgentTaskIdentityPolicy.matchesDesktopResponse(
            pendingResult.metadata,
            conversationId,
            taskId,
            turnId
        )
    ) return null
    if (!recordTaskBudgetUsage(
            inputTokens = inputTokens,
            outputTokens = outputTokens,
            costMicros = costMicros,
            networkBytes = networkBytes
        )
    ) {
        return snapshot()
    }
    val plan = currentPlan ?: return null
    val actionId = pendingResult.actionId
    val completedAction = plan.actions.firstOrNull { it.id == actionId }
    val supervisedProjectResponse = completedAction?.isSupervisedProjectConnector() == true
    if (!advanceExecutionLoop(
            nextPhase = AgentExecutionLoopPhase.OBSERVE,
            reason = "Remote response received",
            actionId = actionId
        )
    ) {
        return snapshot()
    }
    val rawResponse = content.trim().take(MAX_CONNECTOR_RESPONSE_CHARACTERS)
    val normalizedRichOutput = AgentRichContentCodec.normalize(richOutputJson)
    val responseSelfCheck = if (success && !supervisedProjectResponse) {
        AgentResponseSelfCheck.evaluate(
            latestRequest = currentGoal,
            response = rawResponse,
            hasAttachments = pendingResult.metadata["has_attachments"] == "true",
            hasOutputArtifacts = normalizedRichOutput.isNotBlank()
        )
    } else {
        null
    }
    val effectiveSuccess = success && responseSelfCheck?.accepted != false
    val connectorProviderFailure = if (effectiveSuccess) {
        null
    } else {
        AgentProviderFailurePolicy.classify(content)
    }
    val response = when {
        effectiveSuccess -> rawResponse
        success -> appContext.getString(R.string.agent_response_self_check_failed)
        else -> rawResponse.ifBlank { "The selected resource did not return a usable response." }
    }
    responseSelfCheck?.let { review ->
        recordAudit(
            if (review.accepted) {
                AgentAuditEvent.RESPONSE_SELF_CHECK_PASSED
            } else {
                AgentAuditEvent.RESPONSE_SELF_CHECK_FAILED
            },
            "request_digest=${review.requestDigest}; response_digest=${review.responseDigest}; " +
                "reasons=${review.reasons.joinToString(",")}"
        )
    }
    val resourceStartedAt = pendingResult.metadata["resource_started_at"]?.toLongOrNull()
        ?: System.currentTimeMillis()
    if (!supervisedProjectResponse || !effectiveSuccess) {
        recordConnectorResponseHealth(
            pendingResult = pendingResult,
            contactId = contactId,
            resourceStartedAt = resourceStartedAt,
            success = effectiveSuccess
        )
    }
    if (!effectiveSuccess) {
        val failureReason = responseSelfCheck?.diagnostic
            ?: content.trim().ifBlank { "Connector returned no usable result" }
        val providerFailure = requireNotNull(connectorProviderFailure)
        if (!recordExecutionFailure(
                failureClass = "connector:${pendingResult.metadata["resource_id"].orEmpty().ifBlank { contactId }}",
                reason = failureReason,
                actionId = actionId
            )
        ) {
            return snapshot()
        }
        val failedResult = pendingResult.copy(
            success = false,
            message = response,
            metadata = pendingResult.metadata + mapOf(
                "response_self_check" to (responseSelfCheck?.status?.name?.lowercase(Locale.ROOT) ?: "not_run"),
                "response_self_check_reasons" to responseSelfCheck?.reasons.orEmpty().joinToString(","),
                "provider_failure_class" to providerFailure.failureClass.name.lowercase(Locale.ROOT),
                "non_retriable" to providerFailure.permanent.toString()
            )
        )
        continueWithConnectorFallback(plan, failedResult)?.let { return it }
    }
    val completedMetadata = pendingResult.metadata - setOf(
        "timeout_stage",
        "timeout_elapsed_ms"
    ) + mapOf(
        "awaiting_response" to "false",
        "response_received_at" to System.currentTimeMillis().toString(),
        "rich_output" to if (effectiveSuccess) normalizedRichOutput else "",
        "response_self_check" to (responseSelfCheck?.status?.name?.lowercase(Locale.ROOT) ?: "not_run"),
        "response_self_check_reasons" to responseSelfCheck?.reasons.orEmpty().joinToString(","),
        "response_request_digest" to responseSelfCheck?.requestDigest.orEmpty(),
        "response_digest" to responseSelfCheck?.responseDigest.orEmpty(),
        "recovered_after_timeout" to recoveringTimeout.toString(),
        "provider_failure_class" to connectorProviderFailure?.failureClass
            ?.name?.lowercase(Locale.ROOT).orEmpty(),
        "non_retriable" to (connectorProviderFailure?.permanent == true).toString()
    )
    val completedResult = AgentActionResult(
        actionId = actionId,
        success = effectiveSuccess,
        message = response,
        metadata = completedMetadata
    )
    val responseStatus = if (effectiveSuccess) AgentActionStatus.COMPLETED else AgentActionStatus.FAILED
    var responsePlan = plan.markAction(actionId, responseStatus, completedResult)
    if (effectiveSuccess && supervisedProjectResponse) {
        val supervisor = requireNotNull(completedAction)
        val supervisedPlan = acceptSupervisedProjectPlan(responsePlan, supervisor, response)
        val semanticallyExecutable = AgentSupervisedProjectLoop.isExecutableResponsePlan(supervisedPlan)
        recordConnectorResponseHealth(
            pendingResult = pendingResult,
            contactId = contactId,
            resourceStartedAt = resourceStartedAt,
            success = semanticallyExecutable,
            force = !semanticallyExecutable
        )
        if (supervisedPlan == null) {
            val repairAttempts = supervisor.parameters["supervised_parse_attempt"]
                ?.toIntOrNull()
                ?.coerceAtLeast(0)
                ?: 0
            val failureMessage = "The supervising model returned an invalid executable project plan " +
                "after $repairAttempts structured repair attempt(s)."
            val failure = completedResult.copy(
                success = false,
                message = failureMessage,
                metadata = completedResult.metadata + mapOf(
                    "native_tool_output" to response.take(6_000),
                    "failure_kind" to "invalid_supervised_project_plan",
                    "structured_repair_attempts" to repairAttempts.toString()
                )
            )
            val failedPlan = responsePlan.markAction(actionId, AgentActionStatus.FAILED, failure)
            val recoveredPlan = supervisedProjectRecoveryPlan(failedPlan, failureMessage)
            currentPlan = recoveredPlan ?: failedPlan
            lastActionResult = failure
            recordAudit(
                AgentAuditEvent.ACTION_BLOCKED,
                "supervised_project_plan_invalid; action=$actionId; " +
                    "repair_attempts=$repairAttempts; recovery_scheduled=${recoveredPlan != null}"
            )
            if (recoveredPlan != null) {
                if (!advanceExecutionLoop(
                        nextPhase = AgentExecutionLoopPhase.REPLAN,
                        reason = failureMessage,
                        actionId = actionId
                    )
                ) {
                    saveTaskRecord(result = failure.message)
                    return snapshot()
                }
                phase = AgentPhase.PLANNING
                saveTaskRecord()
                return executeFirstPendingAction()
            }
            phase = AgentPhase.FAILED
            saveTaskRecord(result = failure.message)
            return reconcileExecutionLoop(snapshot())
        }
        currentPlan = supervisedPlan
        lastActionResult = completedResult.copy(
            message = "The next verified project step is ready.",
            metadata = completedResult.metadata + mapOf("reasoning_recorded_separately" to "true")
        )
        supervisedPlan.routeRationale.takeIf(String::isNotBlank)?.let { summary ->
            recordAudit(
                AgentAuditEvent.REASONING_SUMMARY,
                "summary=${summary.replace(';', ',').take(600)}"
            )
        }
        recordAudit(
            AgentAuditEvent.CONNECTOR_RESPONSE_RECEIVED,
            "source_message_id=$sourceMessageId; contact=$contactId; success=true; structured_project_plan=true"
        )
        phase = when {
            safetySettingsStore.load().executionPaused -> AgentPhase.PAUSED
            supervisedPlan.safetyReview.blocked -> AgentPhase.BLOCKED
            supervisedPlan.safetyReview.requiresConfirmation -> AgentPhase.WAITING_CONFIRMATION
            else -> AgentPhase.PLANNING
        }
        saveTaskRecord()
        return if (
            !supervisedPlan.safetyReview.blocked &&
            !supervisedPlan.safetyReview.requiresConfirmation
        ) {
            executeFirstPendingAction()
        } else {
            snapshot()
        }
    }
    if (effectiveSuccess && completedAction?.parameters?.get("connector_task_mode") == PHONE_DEVELOPMENT_CONNECTOR_MODE) {
        AgentPhoneDevelopmentManifestCodec.parse(response).getOrNull()?.decisionSummary
            ?.takeIf(String::isNotBlank)
            ?.let { summary ->
                recordAudit(
                    AgentAuditEvent.REASONING_SUMMARY,
                    "summary=${summary.replace(';', ',').take(600)}"
                )
            }
        val installedPackIds = AgentOnDeviceRuntimeManager(appContext).packStatuses()
            .filter { it.state == AgentRuntimePackState.READY }
            .mapTo(linkedSetOf(), AgentRuntimePackStatus::id)
        responsePlan = responsePlan.withPhoneDevelopmentPackInstalls(
            authorActionId = actionId,
            sourceResult = response,
            installedPackIds = installedPackIds
        )
    }
    responsePlan = AgentPlanLifecyclePolicy.normalize(responsePlan).plan
    currentPlan = responsePlan
    lastActionResult = completedResult
    val hasPendingActions = responsePlan.actions.any {
        it.status == AgentActionStatus.PENDING_CONFIRMATION || it.status == AgentActionStatus.PROPOSED
    }
    val preservesToolGraph = effectiveSuccess && responsePlan.hasOutputHandoffFrom(actionId)
    val nonRetriableFailure = !effectiveSuccess && completedResult.metadata["non_retriable"] == "true"
    val shouldReplan = (hasPendingActions && !preservesToolGraph) ||
        (!effectiveSuccess && !nonRetriableFailure)
    val continuedPlan = if (shouldReplan) {
        if (!advanceExecutionLoop(
                nextPhase = AgentExecutionLoopPhase.REPLAN,
                reason = if (effectiveSuccess) {
                    "Planning the next step after the connector response"
                } else {
                    "Planning recovery after the connector response failed"
                },
                actionId = actionId
            )
        ) {
            return snapshot()
        }
        currentScreen = captureScreen()
        replanFromCurrentState(
            responsePlan,
            if (effectiveSuccess) "connector_response_received" else "connector_response_failed"
        ) ?: responsePlan
    } else {
        responsePlan
    }
    currentPlan = continuedPlan
    phase = if (safetySettingsStore.load().executionPaused) {
        AgentPhase.PAUSED
    } else if (continuedPlan.safetyReview.blocked) {
        AgentPhase.BLOCKED
    } else if (!effectiveSuccess && continuedPlan === responsePlan) {
        AgentPhase.FAILED
    } else if (continuedPlan.actions.any {
            it.status == AgentActionStatus.PENDING_CONFIRMATION || it.status == AgentActionStatus.PROPOSED
        }
    ) {
        AgentPhase.WAITING_CONFIRMATION
    } else {
        AgentPhase.COMPLETED
    }
    recordAudit(
        AgentAuditEvent.CONNECTOR_RESPONSE_RECEIVED,
        "source_message_id=$sourceMessageId; contact=$contactId; success=$effectiveSuccess; chars=${response.length}"
    )
    saveTaskRecord(result = response)
    return if (
        !continuedPlan.safetyReview.blocked &&
        !continuedPlan.safetyReview.requiresConfirmation &&
        continuedPlan.actions.any {
            it.status == AgentActionStatus.PENDING_CONFIRMATION || it.status == AgentActionStatus.PROPOSED
        }
    ) {
        executeFirstPendingAction()
    } else {
        snapshot()
    }
}

private fun MobileNativeAgent.recordConnectorResponseHealth(
    pendingResult: AgentActionResult,
    contactId: String,
    resourceStartedAt: Long,
    success: Boolean,
    force: Boolean = false
) {
    if (!force && pendingResult.metadata["cloud_health_recorded"] == "true") return
    val elapsed = (System.currentTimeMillis() - resourceStartedAt).coerceAtLeast(0L)
    val resourceId = pendingResult.metadata["resource_id"].orEmpty().ifBlank { contactId }
    val health = AgentResourceHealthStore(appContext)
    if (resourceId.isNotBlank()) health.record("target:$resourceId", success, elapsed)
    pendingResult.metadata["failure_domain"].orEmpty().takeIf(String::isNotBlank)?.let { domain ->
        health.record("domain:$domain", success, elapsed)
    }
}

internal fun MobileNativeAgent.continueWithConnectorFallback(
    plan: AgentPlan,
    failedResult: AgentActionResult
): AgentUiState? {
    val failedDomain = failedResult.metadata["failure_domain"].orEmpty()
    val timeoutFailure = failedResult.metadata["timeout_stage"].orEmpty().isNotBlank()
    val fallbackIds = failedResult.metadata["remaining_fallback_ids"].orEmpty()
        .split(',')
        .map(String::trim)
        .filter(String::isNotBlank)
        .distinct()
        .filterNot { connectorId ->
            timeoutFailure && failedDomain.isNotBlank() &&
                connectorFailureDomain(connectorId) == failedDomain
        }
    if (fallbackIds.isEmpty()) return null
    val action = plan.actions.firstOrNull { it.id == failedResult.actionId } ?: return null
    val retryAction = action.copy(
        parameters = action.parameters + mapOf(
            "connector_id" to fallbackIds.first(),
            "routing_fallback_ids" to fallbackIds.drop(1).joinToString(",")
        )
    )
    if (!advanceExecutionLoop(
            nextPhase = AgentExecutionLoopPhase.REPLAN,
            reason = "Connector fallback selected",
            actionId = action.id
        )
    ) {
        return snapshot()
    }
    recordAudit(
        AgentAuditEvent.INVOCATION_AUDIT,
        "fallback_after_failure:${failedResult.metadata["resource_id"].orEmpty()}:${fallbackIds.first()}"
    )
    if (!advanceExecutionLoop(
            nextPhase = AgentExecutionLoopPhase.ACT,
            reason = "Dispatching connector fallback",
            actionId = retryAction.id,
            toolCall = true,
            retry = true
        )
    ) {
        return snapshot()
    }
    val fallbackResult = actionExecutor.execute(retryAction, currentScreen)
    if (!advanceExecutionLoop(
            nextPhase = AgentExecutionLoopPhase.OBSERVE,
            reason = "Observing connector fallback dispatch",
            actionId = retryAction.id
        )
    ) {
        return snapshot()
    }
    if (!fallbackResult.success || fallbackResult.metadata["awaiting_response"] != "true") return null
    lastActionResult = fallbackResult
    phase = AgentPhase.WAITING_RESPONSE
    saveTaskRecord()
    return reconcileExecutionLoop(snapshot())
}

internal fun MobileNativeAgent.recoverAfterConnectorDeliveryFailure(
    plan: AgentPlan,
    failedResult: AgentActionResult
): AgentUiState {
    val failedPlan = plan.markAction(
        failedResult.actionId,
        AgentActionStatus.FAILED,
        failedResult
    ).markConnectorDeliveryFailed(
        failedResult.actionId,
        failedResult.metadata["source_message_id"]?.toLongOrNull() ?: 0L
    )
    currentPlan = failedPlan
    lastActionResult = failedResult
    if (!advanceExecutionLoop(
            nextPhase = AgentExecutionLoopPhase.OBSERVE,
            reason = "The connector transport did not deliver the request",
            actionId = failedResult.actionId
        )
    ) {
        return snapshot()
    }
    val resourceId = failedResult.metadata["resource_id"].orEmpty()
        .ifBlank { failedResult.metadata["contact_id"].orEmpty() }
    val failureDomain = failedResult.metadata["failure_domain"].orEmpty()
    val elapsed = (System.currentTimeMillis() -
        (failedResult.metadata["resource_started_at"]?.toLongOrNull() ?: System.currentTimeMillis()))
        .coerceAtLeast(0L)
    AgentResourceHealthStore(appContext).also { health ->
        if (resourceId.isNotBlank()) health.record("target:$resourceId", false, elapsed)
        if (failureDomain.isNotBlank()) health.record("domain:$failureDomain", false, elapsed)
    }
    if (!recordExecutionFailure(
            failureClass = "connector-delivery:${failureDomain.ifBlank { resourceId }}",
            reason = failedResult.message,
            actionId = failedResult.actionId
        )
    ) {
        phase = AgentPhase.FAILED
        saveTaskRecord(result = lastActionResult?.message.orEmpty().ifBlank { failedResult.message })
        return reconcileExecutionLoop(snapshot())
    }
    continueWithConnectorFallback(failedPlan, failedResult)?.let { return it }
    val replanned = replanFromCurrentState(
        failedPlan,
        "connector_delivery_failed:${failureDomain.ifBlank { resourceId }}",
        force = true
    )
    if (replanned == null) {
        currentPlan = failedPlan
        lastActionResult = failedResult
        phase = AgentPhase.FAILED
        saveTaskRecord(result = failedResult.message)
        return reconcileExecutionLoop(snapshot())
    }
    currentPlan = replanned
    phase = when {
        replanned.safetyReview.blocked -> AgentPhase.BLOCKED
        replanned.safetyReview.requiresConfirmation -> AgentPhase.WAITING_CONFIRMATION
        else -> AgentPhase.PLANNING
    }
    saveTaskRecord()
    return if (!replanned.safetyReview.blocked && !replanned.safetyReview.requiresConfirmation) {
        reconcileExecutionLoop(executeFirstPendingAction())
    } else {
        reconcileExecutionLoop(snapshot())
    }
}

@Synchronized
internal fun MobileNativeAgent.resumeFailedConnectorDeliveryRecovery(): AgentUiState? {
    if (phase != AgentPhase.FAILED) return null
    val plan = currentPlan ?: return null
    val persistedSourceMessageId = plan.connectorDeliveryFailureSourceMessageId()
        ?: lastActionResult
            ?.takeIf { it.metadata["delivery_failed"] == "true" }
            ?.metadata
            ?.get("source_message_id")
            ?.toLongOrNull()
            ?.takeIf { it > 0L }
        ?: return null
    val failedResult = (lastActionResult ?: AgentActionResult(
        actionId = plan.actions.lastOrNull {
            it.evidence == "$AGENT_CONNECTOR_DELIVERY_FAILED_EVIDENCE_PREFIX$persistedSourceMessageId"
        }?.id.orEmpty().ifBlank { "connector-delivery" },
        success = false,
        message = "The connector request was not delivered"
    )).copy(
        success = false,
        metadata = lastActionResult?.metadata.orEmpty() + mapOf(
            "delivery_failed" to "true",
            "source_message_id" to persistedSourceMessageId.toString()
        )
    )
    lastActionResult = failedResult
    if (!advanceExecutionLoop(
            nextPhase = AgentExecutionLoopPhase.REPLAN,
            reason = "Resuming recovery from a persisted connector delivery failure",
            actionId = failedResult.actionId,
            retry = true
        )
    ) {
        return snapshot()
    }
    val resourceId = failedResult.metadata["resource_id"].orEmpty()
        .ifBlank { failedResult.metadata["contact_id"].orEmpty() }
    val failureDomain = failedResult.metadata["failure_domain"].orEmpty()
    val replanned = replanFromCurrentState(
        plan,
        "connector_delivery_failed:${failureDomain.ifBlank { resourceId }}",
        force = true
    ) ?: return snapshot()
    currentPlan = replanned
    phase = when {
        replanned.safetyReview.blocked -> AgentPhase.BLOCKED
        replanned.safetyReview.requiresConfirmation -> AgentPhase.WAITING_CONFIRMATION
        else -> AgentPhase.PLANNING
    }
    recordAudit(
        AgentAuditEvent.TASK_RESUMED,
        "connector_delivery_recovery:revision=${replanned.revision}"
    )
    saveTaskRecord()
    return if (!replanned.safetyReview.blocked && !replanned.safetyReview.requiresConfirmation) {
        reconcileExecutionLoop(executeFirstPendingAction())
    } else {
        reconcileExecutionLoop(snapshot())
    }
}

internal fun MobileNativeAgent.connectorFailureDomain(connectorId: String): String {
    if (connectorId == "cloud-models" || connectorId.startsWith("cloud-model:") ||
        AppStore.isCloudApiContact(appContext, connectorId)
    ) {
        return "cloud:$connectorId"
    }
    val direct = AppStore.contactById(appContext, connectorId)
    val contactId = direct?.optString("id").orEmpty().ifBlank {
        val contacts = AppStore.contacts(appContext)
        (0 until contacts.length()).asSequence()
            .mapNotNull(contacts::optJSONObject)
            .firstOrNull { contact ->
                contact.optString("agent_id") == connectorId ||
                    contact.optString("signalasi_id") == connectorId ||
                    contact.optString("id").endsWith(":$connectorId")
            }
            ?.optString("id")
            .orEmpty()
    }
    if (contactId.isBlank()) return "resource:$connectorId"
    return AppStore.desktopIdForContact(appContext, contactId).ifBlank { "peer:$contactId" }
}

internal fun MobileNativeAgent.canAcceptConnectorTransport(sourceMessageId: Long, contactId: String): Boolean {
    if (sourceMessageId <= 0L) return false
    val pendingResult = lastActionResult ?: return false
    if (phase != AgentPhase.WAITING_RESPONSE &&
        !isRecoverableConnectorTimeout(pendingResult, sourceMessageId)
    ) return false
    if (pendingResult.metadata["source_message_id"]?.toLongOrNull() != sourceMessageId) {
        return false
    }
    val expectedContactId = pendingResult.metadata["contact_id"].orEmpty()
    return expectedContactId.isBlank() || contactId.isBlank() || expectedContactId == contactId
}

internal fun MobileNativeAgent.canAcceptConnectorResponse(
    sourceMessageId: Long,
    contactId: String,
    conversationId: String = "",
    turnId: String = "",
    taskId: String = ""
): Boolean {
    if (!canAcceptConnectorTransport(sourceMessageId, contactId)) return false
    val pendingResult = lastActionResult ?: return false
    return AgentTaskIdentityPolicy.matchesDesktopResponse(
        pendingResult.metadata,
        conversationId,
        taskId,
        turnId
    )
}

internal fun MobileNativeAgent.isRecoverableConnectorTimeout(
    result: AgentActionResult,
    sourceMessageId: Long
): Boolean = phase == AgentPhase.FAILED &&
    result.success.not() &&
    result.metadata["source_message_id"]?.toLongOrNull() == sourceMessageId &&
    result.metadata["timeout_stage"].orEmpty().isNotBlank()

internal fun MobileNativeAgent.recordConnectorTransportAccepted(sourceMessageId: Long): AgentUiState? {
    if (sourceMessageId <= 0L || phase != AgentPhase.WAITING_RESPONSE) return null
    val pending = lastActionResult ?: return null
    if (pending.metadata["source_message_id"]?.toLongOrNull() != sourceMessageId) return null
    val now = System.currentTimeMillis()
    pending.metadata["failure_domain"].orEmpty().takeIf(String::isNotBlank)?.let { domain ->
        AgentResourceHealthStore(appContext).markAvailable("domain:$domain")
    }
    lastActionResult = pending.copy(
        metadata = pending.metadata + mapOf(
            "remote_task_status" to pending.metadata["remote_task_status"].orEmpty().ifBlank { "accepted" },
            "remote_task_status_updated_at" to now.toString(),
            "transport_accepted_at" to now.toString()
        )
    )
    saveTaskRecord()
    return snapshot()
}

@Synchronized
internal fun MobileNativeAgent.recoverStrandedConnectorHandoff(
    sourceMessageId: Long,
    reason: String
): AgentUiState? {
    if (sourceMessageId <= 0L || phase != AgentPhase.WAITING_RESPONSE) return null
    val pending = lastActionResult ?: return null
    if (pending.metadata["source_message_id"]?.toLongOrNull() != sourceMessageId) return null
    val plan = currentPlan ?: return null
    val action = plan.actions.firstOrNull { candidate ->
        candidate.id == pending.actionId && candidate.kind == AgentActionKind.CALL_CONNECTOR
    } ?: return null
    val attempt = AgentPendingHandoffRecoveryPolicy.recoveryAttempt(pending.metadata) + 1
    if (attempt > AgentPendingHandoffRecoveryPolicy.MAX_RECOVERY_ATTEMPTS) return null
    val recoveryIdempotencyKey = action.parameters["idempotency_key"]
        .orEmpty()
        .ifBlank { "${sessionId}:${action.id}" } + ":handoff-recovery:$attempt"
    val recoveredAction = action.rekeyAgentTeamForRetry().copy(
        status = AgentActionStatus.PENDING_CONFIRMATION,
        result = "",
        evidence = "",
        parameters = action.parameters + mapOf(
            "handoff_recovery_attempt" to attempt.toString(),
            "superseded_source_message_id" to sourceMessageId.toString(),
            "idempotency_key" to recoveryIdempotencyKey
        )
    )
    val recoveredPlan = plan.copy(
        actions = plan.actions.map { candidate ->
            if (candidate.id == action.id) recoveredAction else candidate
        },
        verificationResults = plan.verificationResults.filterNot { it.actionId == action.id }
    )
    currentPlan = recoveredPlan
    lastActionResult = pending.copy(
        success = false,
        message = reason,
        metadata = pending.metadata + mapOf(
            "awaiting_response" to "false",
            "handoff_recovery_attempt" to attempt.toString(),
            "superseded_source_message_id" to sourceMessageId.toString()
        )
    )
    recordAudit(
        AgentAuditEvent.INVOCATION_AUDIT,
        "stranded_connector_handoff:source=$sourceMessageId;attempt=$attempt"
    )
    if (!advanceExecutionLoop(
            nextPhase = AgentExecutionLoopPhase.REPLAN,
            reason = reason,
            actionId = action.id,
            retry = true
        )
    ) {
        return snapshot()
    }
    phase = AgentPhase.PLANNING
    saveTaskRecord()
    val state = executePlannedAction(
        plan = recoveredPlan,
        nextAction = recoveredAction,
        userConfirmed = false,
        retrying = true,
        trustedHandoffReplay = true
    )
    val replacement = state.lastActionResult
    if (state.phase == AgentPhase.WAITING_RESPONSE && replacement != null) {
        lastActionResult = replacement.copy(
            metadata = replacement.metadata + mapOf(
                "handoff_recovery_attempt" to attempt.toString(),
                "superseded_source_message_id" to sourceMessageId.toString()
            )
        )
        saveTaskRecord()
        return snapshot()
    }
    return state
}

@Synchronized
internal fun MobileNativeAgent.resumeInterruptedConnectorHandoffRecovery(): AgentUiState? {
    val plan = currentPlan ?: return null
    val interruptedAction = AgentPendingHandoffRecoveryPolicy.interruptedRecoveryAction(phase, plan)
        ?: return null
    val resumedAction = interruptedAction.copy(
        status = AgentActionStatus.PROPOSED,
        result = "",
        evidence = ""
    )
    val resumedPlan = plan.copy(
        actions = plan.actions.map { action ->
            if (action.id == resumedAction.id) resumedAction else action
        },
        verificationResults = plan.verificationResults.filterNot { it.actionId == resumedAction.id },
        safetyReview = plan.safetyReview.copy(
            requiresConfirmation = false,
            blocked = false,
            mode = PermissionMode.FULL_ACCESS,
            deniedPermissions = emptyList(),
            warnings = emptyList(),
            reason = ""
        )
    )
    currentPlan = resumedPlan
    phase = AgentPhase.PLANNING
    lastActionResult = AgentActionResult(
        actionId = resumedAction.id,
        success = false,
        message = "Resuming the interrupted connector handoff",
        metadata = mapOf(
            "handoff_recovery_attempt" to resumedAction.parameters["handoff_recovery_attempt"].orEmpty(),
            "superseded_source_message_id" to resumedAction.parameters["superseded_source_message_id"].orEmpty()
        )
    )
    recordAudit(
        AgentAuditEvent.INVOCATION_AUDIT,
        "resume_interrupted_connector_handoff:action=${resumedAction.id}"
    )
    saveTaskRecord()
    return executePlannedAction(
        plan = resumedPlan,
        nextAction = resumedAction,
        userConfirmed = false,
        retrying = true,
        trustedHandoffReplay = true
    )
}

internal fun MobileNativeAgent.pendingConnectorMetadata(sourceMessageId: Long): Map<String, String> =
    lastActionResult?.takeIf {
        phase == AgentPhase.WAITING_RESPONSE &&
            it.metadata["source_message_id"]?.toLongOrNull() == sourceMessageId
    }?.metadata.orEmpty()

internal fun MobileNativeAgent.captureVerificationScreen(
    action: AgentAction,
    beforeAction: ScreenContext,
    actionResult: AgentActionResult?
): AgentObservationOutcome {
    if (!action.kind.mayChangeScreen()) {
        return AgentObservationOutcome(
            screen = currentScreen,
            decision = if (actionResult?.success == true) {
                AgentObservationDecision.NO_CHANGE_REQUIRED
            } else {
                AgentObservationDecision.ACTION_FAILED
            },
            sampleCount = 0,
            durationMillis = 0L,
            screenChanged = false,
            screenStable = true,
            evidence = "tool_receipt_only=true; screen_capture_skipped=true"
        )
    }
    return observationController.observe(
        beforeAction = beforeAction,
        actionSucceeded = actionResult?.success == true,
        changeExpected = true,
        capture = { captureScreen() }
    )
}

internal fun MobileNativeAgent.applyObservationResult(
    action: AgentAction,
    result: AgentActionResult?,
    observation: AgentObservationOutcome
): AgentActionResult? {
    result ?: return null
    val metadata = result.metadata + mapOf(
        "observation_decision" to observation.decision.name,
        "observation_samples" to observation.sampleCount.toString(),
        "observation_duration_ms" to observation.durationMillis.toString(),
        "screen_changed" to observation.screenChanged.toString(),
        "screen_stable" to observation.screenStable.toString()
    )
    return if (result.success &&
        action.kind.mayChangeScreen() &&
        observation.decision == AgentObservationDecision.TIMED_OUT
    ) {
        result.copy(
            success = false,
            message = "${result.message}; no screen change was observed",
            metadata = metadata
        )
    } else {
        result.copy(metadata = metadata)
    }
}

internal fun MobileNativeAgent.recoverActionIfSafe(
    action: AgentAction,
    result: AgentActionResult?,
    observation: AgentObservationOutcome
): AgentRecoveryOutcome {
    val recovery = recoveryController.recover(action, result, observation) {
        recordAudit(AgentAuditEvent.ACTION_RECOVERY_STARTED, "action:${action.kind}:${action.id}")
        if (!advanceExecutionLoop(
                nextPhase = AgentExecutionLoopPhase.ACT,
                reason = "Retrying action after observation",
                actionId = action.id,
                toolCall = action.kind in setOf(
                    AgentActionKind.CALL_NATIVE_TOOL,
                    AgentActionKind.CALL_CONNECTOR,
                    AgentActionKind.CONTROL_DEVICE
                ),
                retry = true
            )
        ) {
            return@recover AgentRecoveryAttempt(
                result = lastActionResult,
                observation = observation
            )
        }
        val retryScreen = observation.screen
        val retryResult = executeAction(action, retryScreen, userConfirmed = true)
        val retryObservation = captureVerificationScreen(action, retryScreen, retryResult)
        advanceExecutionLoop(
            nextPhase = AgentExecutionLoopPhase.OBSERVE,
            reason = "Observing retry outcome",
            actionId = action.id
        )
        AgentRecoveryAttempt(
            result = applyObservationResult(action, retryResult, retryObservation),
            observation = retryObservation
        )
    }
    when (recovery.decision) {
        AgentRecoveryDecision.RETRY_SUCCEEDED,
        AgentRecoveryDecision.RETRY_FAILED -> recordAudit(
            AgentAuditEvent.ACTION_RECOVERY_COMPLETED,
            "action:${action.kind}:${recovery.decision}:attempts=${recovery.attemptCount}"
        )
        AgentRecoveryDecision.MANUAL_REQUIRED -> recordAudit(
            AgentAuditEvent.ACTION_RECOVERY_MANUAL_REQUIRED,
            "action:${action.kind}:${action.id}"
        )
        AgentRecoveryDecision.NOT_NEEDED -> Unit
    }
    return recovery
}

internal fun MobileNativeAgent.applyRecoveryMetadata(
    result: AgentActionResult?,
    recovery: AgentRecoveryOutcome
): AgentActionResult? = result?.copy(
    metadata = result.metadata + mapOf(
        "recovery_decision" to recovery.decision.name,
        "recovery_attempt_count" to recovery.attemptCount.toString()
    )
)

internal fun MobileNativeAgent.cancelCurrentTask(): AgentUiState {
    PhoneExecutionAuthority.requestCancellation(sessionId)
    phase = AgentPhase.CANCELLED
    lastActionResult = AgentActionResult(
        actionId = "agent-cancelled",
        success = true,
        message = "Task cancelled"
    )
    saveTaskRecord(result = "Cancelled")
    currentGoal = ""
    currentPlan = null
    recordAudit(AgentAuditEvent.TASK_CANCELLED, "cancelled")
    persistSession()
    return reconcileExecutionLoop(snapshot())
}

internal fun MobileNativeAgent.pauseCurrentTask(): AgentUiState {
    if (currentPlan == null ||
        phase == AgentPhase.OBSERVING ||
        phase == AgentPhase.BLOCKED ||
        phase == AgentPhase.COMPLETED ||
        phase == AgentPhase.FAILED ||
        phase == AgentPhase.CANCELLED
    ) {
        return snapshot()
    }
    phase = AgentPhase.PAUSED
    lastActionResult = AgentActionResult(
        actionId = "agent-paused",
        success = true,
        message = "Task paused"
    )
    recordAudit(AgentAuditEvent.TASK_PAUSED, "paused")
    persistSession()
    return reconcileExecutionLoop(snapshot())
}

internal fun MobileNativeAgent.resumeCurrentTask(): AgentUiState {
    val savedPlan = currentPlan
    val completedDispatch = AgentInterruptedDispatchRecoveryPolicy.completedAction(
        savedPlan,
        lastActionResult
    )
    if (completedDispatch != null && phase in setOf(AgentPhase.EXECUTING, AgentPhase.PAUSED)) {
        return resumeCompletedDispatchObservation(
            requireNotNull(savedPlan),
            completedDispatch,
            requireNotNull(lastActionResult)
        )
    }
    if (phase != AgentPhase.PAUSED) return snapshot()
    if (safetySettingsStore.load().executionPaused) {
        lastActionResult = AgentActionResult(
            actionId = "agent-resume-blocked",
            success = false,
            message = "Disable Pause All Execution before resuming"
        )
        recordAudit(AgentAuditEvent.ACTION_BLOCKED, "resume:execution_paused")
        return snapshot()
    }
    val plan = savedPlan ?: return observeCurrentScreen()
    if (plan.isSupervisedProjectPlan() && plan.hasInterruptedExecutionEvidence()) {
        val recovered = supervisedProjectRecoveryPlan(
            plan,
            "The Android app process ended before the active project action was verified"
        )
        if (recovered == null) {
            phase = AgentPhase.FAILED
            lastActionResult = AgentActionResult(
                actionId = "agent-project-resume-unavailable",
                success = false,
                message = "The saved project is intact, but the supervising model could not create a safe recovery step"
            )
            recordAudit(AgentAuditEvent.ACTION_BLOCKED, "project_resume_replan_unavailable")
            saveTaskRecord(result = lastActionResult?.message.orEmpty())
            return reconcileExecutionLoop(snapshot())
        }
        currentPlan = recovered
        phase = AgentPhase.PLANNING
        lastActionResult = AgentActionResult(
            actionId = "agent-project-resuming",
            success = true,
            message = "Inspecting the saved project before resuming"
        )
        recordAudit(
            AgentAuditEvent.TASK_RESUMED,
            "project_resume_with_model_replan:revision=${recovered.revision}"
        )
        if (!advanceExecutionLoop(
                nextPhase = AgentExecutionLoopPhase.REPLAN,
                reason = "Inspecting durable project evidence after interruption",
                actionId = recovered.actions.firstOrNull()?.id.orEmpty()
            )
        ) {
            return reconcileExecutionLoop(snapshot())
        }
        saveTaskRecord()
        return reconcileExecutionLoop(executeFirstPendingAction())
    }
    val loopResumePhase = executionLoop.snapshot
        ?.takeIf { it.phase == AgentExecutionLoopPhase.PAUSED }
        ?.resumePhase
    phase = when {
        loopResumePhase in setOf(
            AgentExecutionLoopPhase.VERIFY,
            AgentExecutionLoopPhase.FINALIZE,
            AgentExecutionLoopPhase.LEARN
        ) -> AgentPhase.COMPLETED
        plan.actions.any { it.status == AgentActionStatus.WAITING_RESPONSE } -> AgentPhase.WAITING_RESPONSE
        plan.actions.any { it.status == AgentActionStatus.PENDING_CONFIRMATION } -> AgentPhase.WAITING_CONFIRMATION
        else -> AgentPhase.PLANNING
    }
    lastActionResult = AgentActionResult(
        actionId = "agent-resumed",
        success = true,
        message = "Task resumed"
    )
    recordAudit(AgentAuditEvent.TASK_RESUMED, "resumed")
    persistSession()
    executionLoop.snapshot?.takeIf { it.phase == AgentExecutionLoopPhase.PAUSED }?.let {
        persistExecutionLoopEvent(executionLoop.resume("Task resumed"))
    }
    return reconcileExecutionLoop(snapshot())
}

internal fun MobileNativeAgent.resumeCompletedDispatchObservation(
    plan: AgentPlan,
    action: AgentAction,
    result: AgentActionResult
): AgentUiState {
    executionLoop.snapshot
        ?.takeIf { it.phase == AgentExecutionLoopPhase.PAUSED }
        ?.let { persistExecutionLoopEvent(executionLoop.resume("Observing the persisted tool result")) }
    if (!advanceExecutionLoop(
            nextPhase = AgentExecutionLoopPhase.OBSERVE,
            reason = "Observing the persisted tool result",
            actionId = action.id
        )
    ) {
        return reconcileExecutionLoop(snapshot())
    }

    phase = AgentPhase.VERIFYING
    lastActionResult = result
    val evidence = result.metadata["native_tool_output"]
        .orEmpty()
        .ifBlank { "durable_native_receipt:${result.metadata["invocation_id"].orEmpty()}" }
    val observedPlan = plan
        .addArtifactRichOutput(result.metadata["rich_output"].orEmpty())
        .markAction(action.id, AgentActionStatus.COMPLETED, result)
        .addVerification(
            AgentVerificationResult(
                actionId = action.id,
                success = true,
                observedApp = currentScreen.foregroundApp,
                observedTitle = currentScreen.pageTitle,
                visibleTextCount = currentScreen.visibleTexts.size,
                clickableNodeCount = currentScreen.clickableNodeCount,
                evidence = evidence
            )
        )
    val verifiedCompletion = AgentSupervisedProjectCompletionPolicy.verifiedTerminalOutcome(
        goal = currentGoal,
        history = observedPlan.actionHistory + observedPlan.actions,
        completedAction = action,
        result = result
    )
    if (verifiedCompletion != null) {
        return reconcileExecutionLoop(
            completeVerifiedProjectOutcome(observedPlan, action, result, verifiedCompletion)
        )
    }
    val continuedPlan = ensureSupervisedProjectContinuation(observedPlan, action, result)
    currentPlan = continuedPlan
    recordAudit(
        AgentAuditEvent.SCREEN_VERIFIED,
        "Recovered persisted native result; action=${action.id}; invocation=${result.metadata["invocation_id"].orEmpty()}"
    )
    recordAudit(AgentAuditEvent.ACTION_EXECUTED, "action:${action.kind}:COMPLETED:recovered")
    saveTaskRecord()

    val hasNextAction = continuedPlan.actions.any {
        it.status == AgentActionStatus.PENDING_CONFIRMATION || it.status == AgentActionStatus.PROPOSED
    }
    phase = when {
        continuedPlan.safetyReview.blocked -> AgentPhase.BLOCKED
        hasNextAction && continuedPlan.safetyReview.requiresConfirmation -> AgentPhase.WAITING_CONFIRMATION
        hasNextAction -> AgentPhase.PLANNING
        else -> AgentPhase.COMPLETED
    }
    persistSession()
    return if (hasNextAction && !continuedPlan.safetyReview.requiresConfirmation) {
        reconcileExecutionLoop(executeFirstPendingAction())
    } else {
        reconcileExecutionLoop(snapshot())
    }
}

internal fun MobileNativeAgent.continueCurrentTask(): AgentUiState {
    val plan = currentPlan ?: return snapshot()
    return when {
        phase == AgentPhase.PAUSED -> resumeCurrentTask()
        plan.actions.any { it.status == AgentActionStatus.FAILED } -> retryFailedAction()
        phase == AgentPhase.FAILED -> replanCurrentTask()
        plan.actions.any { it.status == AgentActionStatus.PENDING_CONFIRMATION } -> executeFirstPendingAction()
        else -> snapshot()
    }
}

internal fun MobileNativeAgent.retryFailedAction(): AgentUiState {
    val plan = currentPlan ?: return snapshot()
    val failedAction = plan.actions.lastOrNull { it.status == AgentActionStatus.FAILED } ?: return snapshot()
    val resetPlan = plan.resetActionForRetry(failedAction.id)
    val reviewedPlan = resetPlan.withSafetyReview(safetyPolicy.review(resetPlan, sessionId))
    currentPlan = reviewedPlan
    if (reviewedPlan.safetyReview.blocked) {
        phase = AgentPhase.BLOCKED
        val reason = reviewedPlan.safetyReview.reason.ifBlank { "Retry blocked by safety policy" }
        lastActionResult = AgentActionResult(
            actionId = failedAction.id,
            success = false,
            message = reason
        )
        recordAudit(AgentAuditEvent.ACTION_BLOCKED, "retry:${failedAction.id}:$reason")
        saveTaskRecord()
        return reconcileExecutionLoop(snapshot())
    }
    val retryAction = reviewedPlan.actions.first { it.id == failedAction.id }
    lastActionResult = null
    recordAudit(AgentAuditEvent.TASK_RESUMED, "retry:${retryAction.id}")
    return reconcileExecutionLoop(
        executePlannedAction(
            reviewedPlan,
            retryAction,
            userConfirmed = true,
            retrying = true
        )
    )
}

internal fun MobileNativeAgent.replanCurrentTask(): AgentUiState {
    val plan = currentPlan ?: return snapshot()
    currentScreen = captureScreen()
    if (!advanceExecutionLoop(
            nextPhase = AgentExecutionLoopPhase.REPLAN,
            reason = "User requested a new plan",
            retry = executionLoop.snapshot?.phase?.isTerminal == true
        )
    ) {
        return snapshot()
    }
    val replanned = replanFromCurrentState(plan, "user_requested_replan", force = true)
    if (replanned == null) {
        lastActionResult = AgentActionResult(
            actionId = "agent-replan-unavailable",
            success = false,
            message = "A validated model replan is not available"
        )
        persistSession()
        return reconcileExecutionLoop(snapshot())
    }
    currentPlan = replanned
    phase = when {
        replanned.safetyReview.blocked -> AgentPhase.BLOCKED
        replanned.safetyReview.requiresConfirmation -> AgentPhase.WAITING_CONFIRMATION
        else -> AgentPhase.PLANNING
    }
    lastActionResult = AgentActionResult(
        actionId = "agent-replanned",
        success = true,
        message = "Plan revision ${replanned.revision} is ready"
    )
    saveTaskRecord()
    persistSession()
    return if (!replanned.safetyReview.blocked && !replanned.safetyReview.requiresConfirmation) {
        reconcileExecutionLoop(executeFirstPendingAction())
    } else {
        reconcileExecutionLoop(snapshot())
    }
}

internal fun MobileNativeAgent.rollbackLastAction(): AgentUiState {
    val plan = currentPlan ?: return snapshot()
    val allActions = plan.actionHistory + plan.actions
    val latestCompletedAction = allActions.lastOrNull {
        it.status == AgentActionStatus.COMPLETED
    }
    val checkpoint = latestCompletedAction?.let { completedAction ->
        plan.checkpoints.asReversed().firstOrNull { item ->
            item.status == AgentCheckpointStatus.ACTIVE &&
                item.rollbackAction != null &&
                item.actionId == completedAction.id
        }
    } ?: run {
        lastActionResult = AgentActionResult(
            actionId = "agent-rollback-unavailable",
            success = false,
            message = "No reversible completed action is available"
        )
        return snapshot()
    }
    val rollbackAction = checkpoint.rollbackAction ?: return snapshot()
    phase = AgentPhase.EXECUTING
    val beforeRollback = captureScreen()
    lastActionResult = actionExecutor.execute(rollbackAction, beforeRollback)
    phase = AgentPhase.VERIFYING
    val observation = captureVerificationScreen(rollbackAction, beforeRollback, lastActionResult)
    currentScreen = observation.screen
    lastActionResult = applyObservationResult(rollbackAction, lastActionResult, observation)
    val rollbackSucceeded = lastActionResult?.success == true
    val checkpointStatus = if (rollbackSucceeded) {
        AgentCheckpointStatus.RESTORED
    } else {
        AgentCheckpointStatus.INVALIDATED
    }
    val invalidatedMessage = "Invalidated after rollback"
    val rolledPlan = plan.markCheckpoint(checkpoint.id, checkpointStatus).copy(
        actionHistory = plan.actionHistory.map { action ->
            if (rollbackSucceeded && action.id == checkpoint.actionId) {
                action.copy(status = AgentActionStatus.ROLLED_BACK, result = "Rolled back by user")
            } else {
                action
            }
        },
        actions = plan.actions.map { action ->
            when {
                rollbackSucceeded && action.id == checkpoint.actionId ->
                    action.copy(status = AgentActionStatus.ROLLED_BACK, result = "Rolled back by user")
                rollbackSucceeded && action.status in setOf(
                    AgentActionStatus.PENDING_CONFIRMATION,
                    AgentActionStatus.PROPOSED
                ) -> action.copy(status = AgentActionStatus.BLOCKED, result = invalidatedMessage)
                else -> action
            }
        }
    )
    currentPlan = rolledPlan
    recordAudit(
        if (rollbackSucceeded) AgentAuditEvent.CHECKPOINT_RESTORED else AgentAuditEvent.CHECKPOINT_RESTORE_FAILED,
        "checkpoint=${checkpoint.id}; action=${checkpoint.actionId}"
    )
    if (!rollbackSucceeded) {
        phase = AgentPhase.FAILED
        saveTaskRecord()
        persistSession()
        return snapshot()
    }
    val replanned = replanFromCurrentState(rolledPlan, "user_requested_rollback", force = true)
    if (replanned == null) {
        phase = AgentPhase.PAUSED
        lastActionResult = lastActionResult?.copy(
            message = "Rollback completed; submit a new goal or enable model replanning to continue"
        )
        saveTaskRecord()
        persistSession()
        return snapshot()
    }
    currentPlan = replanned
    phase = when {
        replanned.safetyReview.blocked -> AgentPhase.BLOCKED
        replanned.safetyReview.requiresConfirmation -> AgentPhase.WAITING_CONFIRMATION
        else -> AgentPhase.PLANNING
    }
    saveTaskRecord()
    persistSession()
    return if (!replanned.safetyReview.blocked && !replanned.safetyReview.requiresConfirmation) {
        executeFirstPendingAction()
    } else {
        snapshot()
    }
}

internal fun MobileNativeAgent.updatePendingAction(actionId: String, description: String, input: String): AgentUiState {
    val plan = currentPlan ?: return snapshot()
    return applyPlanEdit(
        AgentPlanEditor.updatePendingAction(
            plan,
            actionId,
            description,
            input
        )
    )
}

internal fun MobileNativeAgent.removePendingAction(actionId: String): AgentUiState {
    val plan = currentPlan ?: return snapshot()
    return applyPlanEdit(AgentPlanEditor.removePendingAction(plan, actionId))
}

internal fun MobileNativeAgent.movePendingAction(actionId: String, offset: Int): AgentUiState {
    val plan = currentPlan ?: return snapshot()
    return applyPlanEdit(AgentPlanEditor.movePendingAction(plan, actionId, offset))
}

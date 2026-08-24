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

internal fun MobileNativeAgent.knowledgeHitsSummary(query: String, hits: List<AgentKnowledgeItem>): String =
    if (hits.isEmpty()) {
        "No knowledge hits for \"$query\""
    } else {
        buildString {
            append("Knowledge hits: ").append(hits.size)
            hits.forEachIndexed { index, item ->
                append("\n[").append(index + 1).append("] ")
                append(item.title.replace(Regex("\\s+"), " ").take(100))
                append("\nSource: ").append(knowledgeSourceLabel(item.source))
                append("\nExcerpt: ").append(knowledgeExcerpt(item.content, query))
            }
        }
    }

internal fun MobileNativeAgent.knowledgeSourceLabel(source: String): String = when {
    source.isBlank() -> "local"
    source.startsWith("http://", ignoreCase = true) || source.startsWith("https://", ignoreCase = true) ->
        source.take(180)
    source.startsWith("content://", ignoreCase = true) -> "imported document (${source.hashCode()})"
    else -> source.replace(Regex("\\s+"), " ").take(140)
}

internal fun MobileNativeAgent.knowledgeExcerpt(content: String, query: String): String {
    val normalized = content.replace(Regex("\\s+"), " ").trim()
    if (normalized.isBlank()) return "No excerpt"
    val tokens = query.lowercase(Locale.US)
        .split(Regex("\\s+"))
        .filter { it.length >= 2 }
    val lower = normalized.lowercase(Locale.US)
    val matchIndex = tokens.map { lower.indexOf(it) }.filter { it >= 0 }.minOrNull() ?: 0
    val start = (matchIndex - 100).coerceAtLeast(0)
    val end = (matchIndex + 260).coerceAtMost(normalized.length)
    return buildString {
        if (start > 0) append("...")
        append(normalized.substring(start, end))
        if (end < normalized.length) append("...")
    }
}

internal fun MobileNativeAgent.forgetMemoryCommand(query: String): AgentUiState {
    val deletedCount = memoryStore.delete(query)
    val result = if (deletedCount == 0) {
        "No matching memory for \"$query\""
    } else {
        "Deleted $deletedCount matching memory items"
    }
    val action = AgentAction(
        id = "forget-memory",
        kind = AgentActionKind.DRAFT_PLAN,
        target = "Agent Memory",
        risk = AgentRisk.MEDIUM,
        status = AgentActionStatus.COMPLETED,
        description = "Delete matching Agent memory",
        parameters = mapOf("query" to query),
        result = result
    )
    currentPlan = AgentPlan(
        goal = currentGoal,
        screen = currentScreen,
        steps = completedSteps(),
        actions = listOf(action),
        selectedAgentOrModel = "Agent Memory",
        confirmationRequired = false,
        expectedResult = result,
        route = AgentRoute(
            routeId = "agent-memory",
            kind = AgentRouteKind.KNOWLEDGE,
            targetId = "agent-memory",
            targetTitle = "Agent Memory",
            status = AgentConnectorStatus.AVAILABLE,
            deliveryMode = "local",
            capabilities = listOf(AgentCapability.KNOWLEDGE_SEARCH)
        ),
        safetyReview = AgentSafetyReview(
            risk = AgentRisk.MEDIUM,
            requiresConfirmation = false,
            mode = safetyPolicy.permissionMode()
        )
    )
    phase = AgentPhase.COMPLETED
    lastActionResult = AgentActionResult(action.id, true, result)
    recordAudit(AgentAuditEvent.GOAL_RECEIVED, goalAuditDetail(currentGoal))
    recordAudit(AgentAuditEvent.MEMORY_FORGOTTEN, "query:$query deleted:$deletedCount")
    recordAudit(AgentAuditEvent.ACTION_EXECUTED, "action:${action.kind}:${AgentActionStatus.COMPLETED}")
    saveTaskRecord(result = result)
    return snapshot()
}

internal fun MobileNativeAgent.forgetKnowledgeCommand(query: String): AgentUiState {
    val deletedCount = knowledgeStore.delete(query)
    val result = if (deletedCount == 0) {
        "No matching knowledge for \"$query\""
    } else {
        "Deleted $deletedCount matching knowledge items"
    }
    val action = AgentAction(
        id = "forget-knowledge",
        kind = AgentActionKind.DRAFT_PLAN,
        target = "Agent Knowledge",
        risk = AgentRisk.MEDIUM,
        status = AgentActionStatus.COMPLETED,
        description = "Delete matching Agent knowledge",
        parameters = mapOf("query" to query),
        result = result
    )
    currentPlan = AgentPlan(
        goal = currentGoal,
        screen = currentScreen,
        steps = completedSteps(),
        actions = listOf(action),
        selectedAgentOrModel = "Agent Knowledge",
        confirmationRequired = false,
        expectedResult = result,
        route = AgentRoute(
            routeId = "agent-knowledge",
            kind = AgentRouteKind.KNOWLEDGE,
            targetId = "agent-knowledge",
            targetTitle = "Agent Knowledge",
            status = AgentConnectorStatus.AVAILABLE,
            deliveryMode = "local",
            capabilities = listOf(AgentCapability.KNOWLEDGE_SEARCH)
        ),
        safetyReview = AgentSafetyReview(
            risk = AgentRisk.MEDIUM,
            requiresConfirmation = false,
            mode = safetyPolicy.permissionMode()
        )
    )
    phase = AgentPhase.COMPLETED
    lastActionResult = AgentActionResult(action.id, true, result)
    recordAudit(AgentAuditEvent.GOAL_RECEIVED, goalAuditDetail(currentGoal))
    recordAudit(AgentAuditEvent.MEMORY_FORGOTTEN, "knowledge_query:$query deleted:$deletedCount")
    recordAudit(AgentAuditEvent.ACTION_EXECUTED, "action:${action.kind}:${AgentActionStatus.COMPLETED}")
    saveTaskRecord(result = result)
    return snapshot()
}

internal fun MobileNativeAgent.defaultSteps(): List<AgentStep> = listOf(
    AgentStep(1, AgentStepKind.OBSERVE_SCREEN, AgentStepStatus.CURRENT),
    AgentStep(2, AgentStepKind.ANALYZE_GOAL, AgentStepStatus.WAITING),
    AgentStep(3, AgentStepKind.BUILD_PLAN, AgentStepStatus.WAITING),
    AgentStep(4, AgentStepKind.CONFIRM_AND_ACT, AgentStepStatus.SAFE)
)

internal fun MobileNativeAgent.completedSteps(): List<AgentStep> = listOf(
    AgentStep(1, AgentStepKind.OBSERVE_SCREEN, AgentStepStatus.DONE),
    AgentStep(2, AgentStepKind.ANALYZE_GOAL, AgentStepStatus.DONE),
    AgentStep(3, AgentStepKind.BUILD_PLAN, AgentStepStatus.DONE),
    AgentStep(4, AgentStepKind.CONFIRM_AND_ACT, AgentStepStatus.DONE)
)

internal fun MobileNativeAgent.renderPlanOnlyResult(plan: AgentPlan): String = buildString {
    append(appContext.getString(R.string.agent_plan_only_intro))
    val actions = plan.actions.ifEmpty {
        listOf(
            AgentAction(
                id = "plan-only-summary",
                kind = AgentActionKind.DRAFT_PLAN,
                target = plan.selectedAgentOrModel,
                risk = plan.safetyReview.risk,
                status = AgentActionStatus.PROPOSED,
                description = plan.expectedResult.ifBlank { plan.goal }
            )
        )
    }
    actions.forEachIndexed { index, action ->
        append('\n')
        append(
            appContext.getString(
                R.string.agent_plan_only_step,
                index + 1,
                action.description.ifBlank { action.kind.name.lowercase(Locale.ROOT).replace('_', ' ') }
            )
        )
    }
    append('\n')
    append(
        appContext.getString(
            R.string.agent_plan_only_risk,
            plan.safetyReview.risk.name.lowercase(Locale.ROOT)
        )
    )
}

internal fun MobileNativeAgent.buildRuntimeContext(
    goal: String,
    screen: ScreenContext,
    targets: List<AgentCallableTarget>,
    memories: List<AgentMemoryItem>,
    knowledgeItems: List<AgentKnowledgeItem> = emptyList(),
    knowledgeStats: AgentKnowledgeStats = AgentKnowledgeStats(),
    planningRuntime: AgentPlanningRuntimeSnapshot = planningRuntimeSnapshot()
): AgentRuntimeContext = AgentRuntimeContextBuilder.build(
    sessionId = sessionId,
    goal = goal,
    screen = screen,
    permissionMode = planningRuntime.permissionMode,
    highRiskGuard = planningRuntime.highRiskGuard,
    memoryCapture = planningRuntime.memoryCapture,
    callableTargets = targets,
    memories = memories,
    systemTools = planningRuntime.systemTools,
    nativeTools = planningRuntime.nativeTools,
    knowledgeItems = knowledgeItems,
    knowledgeStats = knowledgeStats
)

internal fun MobileNativeAgent.planningRuntimeSnapshot(): AgentPlanningRuntimeSnapshot {
    val safetySettings = safetySettingsStore.load()
    return AgentPlanningRuntimeSnapshot(
        permissionMode = safetyPolicy.permissionMode(),
        highRiskGuard = safetyPolicy.highRiskGuardEnabled(),
        memoryCapture = safetySettings.memoryCapture,
        systemTools = workflowSystemTools() + AgentSystemToolPlanner.availableTools(),
        nativeTools = AgentNativeToolPlanningCatalog.descriptors(appContext)
    )
}

internal fun MobileNativeAgent.cacheRuntimeContext(context: AgentRuntimeContext) {
    cachedRuntimeContext = context
    cachedRuntimeContextAtElapsedMillis = SystemClock.elapsedRealtime()
    activeRunRuntimeContext = context
}

internal fun MobileNativeAgent.cachedRuntimeContext(): AgentRuntimeContext? {
    val context = cachedRuntimeContext ?: return null
    val age = SystemClock.elapsedRealtime() - cachedRuntimeContextAtElapsedMillis
    if (age !in 0..RUNTIME_CONTEXT_CACHE_TTL_MILLIS || context.goal != currentGoal) return null
    return context.copy(screen = currentScreen)
}

internal fun MobileNativeAgent.invalidateRuntimeContext() {
    cachedRuntimeContext = null
    cachedRuntimeContextAtElapsedMillis = 0L
    activeRunRuntimeContext = null
}

internal fun MobileNativeAgent.logPlanningLatency(stage: String, stageStartedAt: Long, planningStartedAt: Long) {
    val now = SystemClock.elapsedRealtime()
    Log.i(
        "SignalASILatency",
        "agent_prepare stage=$stage stage_ms=${now - stageStartedAt} total_ms=${now - planningStartedAt} " +
            "turn=${activeConversationTurnId.take(12)}"
    )
}

internal fun MobileNativeAgent.workflowSystemTools(): List<AgentSystemTool> {
    val workflows = workflowStore.list().take(3).map { workflow ->
        AgentSystemTool(
            id = "workflow:${workflow.id}",
            title = workflow.name,
            kind = AgentActionKind.DRAFT_PLAN,
            risk = AgentRisk.MEDIUM,
            capabilities = listOf(AgentCapability.TASK_EXECUTION),
            examples = listOf("run workflow ${workflow.name}")
        )
    }
    val templateLimit = if (workflows.isEmpty()) 3 else 1
    val templates = AgentWorkflowTemplates.all.take(templateLimit).map { template ->
        AgentSystemTool(
            id = "template:${template.id}",
            title = template.name,
            kind = AgentActionKind.DRAFT_PLAN,
            risk = AgentRisk.LOW,
            capabilities = listOf(AgentCapability.TASK_EXECUTION),
            examples = listOf("run template ${template.name}")
        )
    }
    return workflows + templates
}

internal fun MobileNativeAgent.buildKnowledgeContent(
    goal: String,
    screen: ScreenContext,
    context: AgentRuntimeContext
): String = buildString {
    append("goal=").append(goal)
    append("\napp=").append(screen.foregroundApp)
    append("\npage=").append(screen.pageTitle)
    append("\ntexts=").append(screen.visibleTextCount)
    append("\nactions=").append(screen.clickableNodeCount)
    if (screen.clipboard.hasText) {
        append("\nclipboard_hash=").append(screen.clipboard.textHash)
        append("\nclipboard_length=").append(screen.clipboard.textLength)
    }
    if (screen.selectedText.isNotBlank()) {
        append("\nselected_text_length=").append(screen.selectedText.length)
    }
    screen.focusedInputField?.let { field ->
        append("\nfocused_input=").append(field.label.ifBlank { field.viewId.ifBlank { field.bounds } })
    }
    if (screen.notifications.items.isNotEmpty()) {
        append("\nnotification_count=").append(screen.notifications.items.size)
        append("\nnotification_packages=")
        append(screen.notifications.items.map { it.packageName }.distinct().take(6).joinToString("|"))
    }
    append("\nmode=").append(context.permissionMode.name)
    if (context.knowledgeItems.isNotEmpty()) {
        append("\nrelated_knowledge=")
        append(context.knowledgeItems.joinToString("; ") { it.title.take(60) })
    }
}

internal fun MobileNativeAgent.memoryBlockReason(
    value: String,
    screen: ScreenContext,
    memoryCapture: Boolean = safetySettingsStore.load().memoryCapture
): String? {
    if (!memoryCapture) return "Memory capture is paused"
    return sensitiveMemoryReason(value, screen)
}

internal fun MobileNativeAgent.isPrivateCommunicationGoal(goal: String): Boolean {
    val normalized = goal.trim().lowercase(Locale.US)
    return normalized.startsWith("reply notification ") ||
        normalized.startsWith("reply to notification ") ||
        normalized.startsWith("\u56de\u590d\u901a\u77e5") ||
        normalized.startsWith("\u56de\u590d\u6700\u65b0\u901a\u77e5")
}

internal fun MobileNativeAgent.sensitiveMemoryReason(value: String, screen: ScreenContext): String? {
    if (screen.sensitiveFlagCount > 0) {
        val flags = screen.sensitiveFlags.joinToString("|").take(80).ifBlank { "screen" }
        return "Memory skipped for sensitive screen context: $flags"
    }
    if (screen.clipboard.sensitiveFlags.isNotEmpty()) {
        val flags = screen.clipboard.sensitiveFlags.joinToString("|").take(80)
        return "Memory skipped for sensitive clipboard context: $flags"
    }
    if (screen.notifications.sensitiveFlags.isNotEmpty()) {
        val flags = screen.notifications.sensitiveFlags.joinToString("|").take(80)
        return "Memory skipped for sensitive notification context: $flags"
    }
    val lower = value.lowercase(Locale.US)
    val matchedTerm = SENSITIVE_MEMORY_TERMS.firstOrNull { lower.contains(it) }
    if (matchedTerm != null) return "Memory skipped for sensitive content: $matchedTerm"
    if (Regex("\\b\\d{4,8}\\b").containsMatchIn(value) &&
        listOf("code", "otp", "verification", "2fa", "sms").any { lower.contains(it) }
    ) {
        return "Memory skipped for verification code"
    }
    return null
}

internal fun MobileNativeAgent.goalAuditDetail(goal: String): String =
    "goal_hash=${goal.hashCode()}; length=${goal.length}"

internal fun MobileNativeAgent.saveTaskRecord(result: String = lastActionResult?.message.orEmpty()) {
    val plan = currentPlan ?: return
    val goalMayBeStored = sensitiveMemoryReason(currentGoal, currentScreen) == null
    val storedGoal = if (goalMayBeStored) currentGoal else "Sensitive goal withheld"
    val actionLog = (plan.actionHistory + plan.actions)
        .distinctBy(AgentAction::id)
        .map { action ->
            buildString {
                append(action.status.name.lowercase(Locale.ROOT))
                append(": ")
                append(
                    if (goalMayBeStored) {
                        action.description.ifBlank { action.kind.name.lowercase(Locale.ROOT) }
                    } else {
                        action.kind.name.lowercase(Locale.ROOT)
                    }
                )
            }
        }
    val execution = AgentExecutionPresentationPolicy.location(
        route = plan.route,
        action = plan.actions.lastOrNull { action ->
            action.status in setOf(
                AgentActionStatus.RUNNING,
                AgentActionStatus.WAITING_RESPONSE,
                AgentActionStatus.COMPLETED
            )
        } ?: plan.actions.firstOrNull()
    )
    val storedSessionId = activeConversationContext.conversationId.ifBlank { sessionId }
    val storedTargetTitle = plan.route.targetTitle.ifBlank { plan.selectedAgentOrModel }
    val storedResult = result.ifBlank { plan.safetyReview.reason }.take(MAX_TASK_RESULT_CHARACTERS)
    val storedVerification = plan.verificationResults.lastOrNull()?.let { verification ->
        "${verification.observedApp}:${verification.observedTitle}:${verification.success}"
    }.orEmpty()
    val fingerprint = AgentTaskPersistenceFingerprint(
        taskId = plan.planId,
        sessionId = storedSessionId,
        goal = storedGoal,
        phase = phase,
        routeKind = plan.route.kind,
        targetTitle = storedTargetTitle,
        risk = plan.safetyReview.risk,
        blocked = plan.safetyReview.blocked,
        executionLocationKind = execution.locationKind,
        executionRuntimeKind = execution.runtimeKind,
        executionLocationId = execution.locationId,
        executionLocationName = execution.locationName,
        executionRuntimeId = execution.runtimeId,
        executionLocationTrusted = execution.trusted,
        result = storedResult,
        verification = storedVerification,
        actionLog = actionLog
    )
    taskPersistenceGate.persistIfChanged(fingerprint) {
        val existingTask = taskStore.find(plan.planId)
        val executionLog = (existingTask?.executionLog.orEmpty() + actionLog)
            .distinct()
            .takeLast(MAX_TASK_EXECUTION_LOG_ITEMS)
        taskStore.upsert(
            AgentTaskRecord(
                taskId = plan.planId,
                sessionId = storedSessionId,
                goal = storedGoal,
                phase = phase,
                routeKind = plan.route.kind,
                targetTitle = storedTargetTitle,
                risk = plan.safetyReview.risk,
                blocked = plan.safetyReview.blocked,
                executionLocationKind = execution.locationKind,
                executionRuntimeKind = execution.runtimeKind,
                executionLocationId = execution.locationId,
                executionLocationName = execution.locationName,
                executionRuntimeId = execution.runtimeId,
                executionLocationTrusted = execution.trusted,
                result = storedResult,
                verification = storedVerification,
                executionLog = executionLog,
                createdAtMillis = existingTask?.createdAtMillis ?: System.currentTimeMillis()
            )
        )
    }
}

internal fun MobileNativeAgent.recordAudit(event: AgentAuditEvent, detail: String) {
    recordAudits(AgentAuditRecord(event, detail))
}

internal fun MobileNativeAgent.appendAudits(vararg records: AgentAuditRecord) {
    AgentAuditBatchPersistence.append(
        auditTrail = auditTrail,
        records = records.asList(),
        maxItems = MAX_AUDIT_ITEMS
    )
}

internal fun MobileNativeAgent.recordAudits(vararg records: AgentAuditRecord) {
    AgentAuditBatchPersistence.appendAndPersist(
        auditTrail = auditTrail,
        records = records.asList(),
        maxItems = MAX_AUDIT_ITEMS,
        persist = ::persistSession
    )
}

internal fun MobileNativeAgent.invocationAuditDetail(
    plan: AgentPlan,
    action: AgentAction,
    result: AgentActionResult?,
    userConfirmed: Boolean
): String {
    val prompt = action.parameters["prompt"].orEmpty()
    val inputLength = prompt.ifBlank { currentGoal }.length
    val inputHash = prompt.ifBlank { currentGoal }.hashCode().toString()
    val permissionScope = plan.requiredPermissions
        .filter { it.required }
        .joinToString("|") { "${it.id}:${if (it.granted) "ready" else "missing"}" }
        .ifBlank { "none" }
    val response = result?.message.orEmpty().take(96).ifBlank { "-" }
    val failure = if (result?.success == false) response else "-"
    return listOf(
        "target=${plan.route.targetTitle.ifBlank { action.target }}",
        "route=${plan.route.kind.name}",
        "action=${action.kind.name}",
        "input_hash=$inputHash",
        "input_length=$inputLength",
        "permissions=$permissionScope",
        "sensitive_flags=${currentScreen.sensitiveFlagCount}",
        "confirmed=$userConfirmed",
        "response=$response",
        "failure=$failure"
    ).joinToString("; ")
}

internal fun MobileNativeAgent.restoreSession(session: AgentSessionSnapshot?) {
    if (session == null) return
    executionLoop = session.executionLoopSnapshot?.let(AgentExecutionLoop::restore)
        ?: AgentExecutionLoop.create()
    val persistedTask = session.currentPlan?.planId?.let(taskStore::find)
    val lifecycleNormalization = AgentPlanLifecyclePolicy.normalize(session)
    val restoredSession = AgentPlanLifecyclePolicy.recoverCompletedConnector(
        lifecycleNormalization.session,
        persistedTask,
        appContext.getString(R.string.agent_stale_connector_no_result)
    )
    logRestoredLifecycle(session, restoredSession, persistedTask)
    val completedDispatch = AgentInterruptedDispatchRecoveryPolicy.completedAction(
        restoredSession.currentPlan,
        restoredSession.lastActionResult
    )
    val executionWasInterrupted = AgentSessionInterruptionPolicy.wasInterrupted(restoredSession) &&
        completedDispatch == null
    sessionId = restoredSession.sessionId.ifBlank { UUID.randomUUID().toString() }
    activeTaskExecutionMode = restoredSession.taskExecutionMode
    phase = if (executionWasInterrupted || completedDispatch != null) AgentPhase.PAUSED else restoredSession.phase
    currentGoal = restoredSession.currentGoal
    currentScreen = restoredSession.currentScreen
    if (!safetySettingsStore.load().screenObservationAllowed) {
        currentScreen = captureScreen()
    }
    val restoredPlan = if (executionWasInterrupted) {
        restoredSession.currentPlan?.recoverInterruptedExecution()
    } else {
        restoredSession.currentPlan
    }
    currentPlan = restoredPlan?.withSafetyReview(safetyPolicy.review(restoredPlan, sessionId))
    if (phase == AgentPhase.WAITING_CONFIRMATION) {
        phase = AgentPhase.EXECUTING
    }
    lastActionResult = if (executionWasInterrupted) {
        AgentActionResult(
            actionId = "agent-interrupted",
            success = false,
            message = "Execution was interrupted and restored at the last checkpoint"
        )
    } else {
        restoredSession.lastActionResult
    }
    activeWorkflowExecutionId = restoredSession.activeWorkflowExecutionId.takeIf { it.isNotBlank() }
    auditTrail.clear()
    auditTrail.addAll(restoredSession.auditTrail.takeLast(MAX_AUDIT_ITEMS))
    val restorationAudits = mutableListOf<AgentAuditRecord>()
    if (lifecycleNormalization.changed) {
        restorationAudits += AgentAuditRecord(
            AgentAuditEvent.INVOCATION_AUDIT,
            "restored_plan_removed_trailing_drafts=${lifecycleNormalization.removedActions.joinToString(",", transform = AgentAction::id)}"
        )
    }
    if (executionWasInterrupted || completedDispatch != null) {
        executionLoop.recoverInterrupted()
        restorationAudits += AgentAuditRecord(
            AgentAuditEvent.TASK_INTERRUPTED,
            if (completedDispatch != null) {
                "restored_completed_dispatch_for_observation:${completedDispatch.id}"
            } else {
                "restored_to_safe_pause"
            }
        )
    }
    if (restorationAudits.isNotEmpty()) {
        recordAudits(*restorationAudits.toTypedArray())
    }
}

internal fun MobileNativeAgent.logRestoredLifecycle(
    original: AgentSessionSnapshot,
    restored: AgentSessionSnapshot,
    persistedTask: AgentTaskRecord?
) {
    fun actionSummary(plan: AgentPlan?): String = plan?.actions.orEmpty().joinToString(",") { action ->
        "${action.kind.name}:${action.target}:${action.status.name}:${action.result.length}"
    }.ifBlank { "none" }
    Log.i(
        "SignalASIAgentLifecycle",
        "restore phase=${original.phase.name}->${restored.phase.name} " +
            "actions=${actionSummary(original.currentPlan)}->${actionSummary(restored.currentPlan)} " +
            "last=${original.lastActionResult?.actionId.orEmpty()}:${original.lastActionResult?.message?.length ?: 0}" +
            "->${restored.lastActionResult?.actionId.orEmpty()}:${restored.lastActionResult?.message?.length ?: 0} " +
            "task=${persistedTask?.phase?.name.orEmpty()}:${persistedTask?.routeKind?.name.orEmpty()}:" +
            "${persistedTask?.targetTitle.orEmpty()}:${persistedTask?.result?.length ?: 0}"
    )
}

internal fun MobileNativeAgent.persistSession() {
    sessionStore.save(
        AgentSessionSnapshot(
            sessionId = sessionId,
            phase = phase,
            currentGoal = currentGoal,
            currentScreen = currentScreen,
            currentPlan = currentPlan,
            auditTrail = auditTrail.toList(),
            lastActionResult = lastActionResult,
            activeWorkflowExecutionId = activeWorkflowExecutionId.orEmpty(),
            taskExecutionMode = activeTaskExecutionMode,
            executionLoopSnapshot = executionLoop.snapshot,
            processInstanceId = AgentProcessIdentity.instanceId,
            updatedAtMillis = System.currentTimeMillis()
        )
    )
}

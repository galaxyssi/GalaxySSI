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

internal fun MobileNativeAgent.bindExecutionLoopEventSink(sink: AgentExecutionLoopEventSink) {
    executionLoopEventSink = sink
}

internal fun MobileNativeAgent.executionLoopSnapshot(): AgentExecutionLoopSnapshot? = executionLoop.snapshot

internal fun MobileNativeAgent.phaseSnapshot(): AgentPhase = phase

internal fun MobileNativeAgent.beginExecutionFinalization(): Boolean =
    advanceExecutionLoop(
        AgentExecutionLoopPhase.FINALIZE,
        "Final result prepared"
    )

internal fun MobileNativeAgent.beginExecutionLearning(): Boolean =
    advanceExecutionLoop(
        AgentExecutionLoopPhase.LEARN,
        "Verified execution evidence queued for learning"
    )

internal fun MobileNativeAgent.completeExecutionLoop(): Boolean =
    advanceExecutionLoop(
        AgentExecutionLoopPhase.COMPLETED,
        "Task completed"
    )

internal fun MobileNativeAgent.failExecutionLoop(reason: String): Boolean =
    advanceExecutionLoop(
        AgentExecutionLoopPhase.FAILED,
        reason.trim().ifBlank { "Task failed" }
    )

internal fun MobileNativeAgent.startExecutionLoop(turnId: String): Boolean {
    val taskId = turnId.trim().ifBlank { sessionId }
    val profile = AgentExecutionProfile.forGoal(
        goal = currentGoal,
        hasAttachments = activeConversationContext.hasAttachments
    )
    val taskBudget = AgentTaskBudgetStore(appContext).load()
    val event = executionLoop.start(
        taskId = taskId,
        budget = modelPlannerSettings().executionLoopBudget(profile),
        profile = profile,
        taskBudget = taskBudget,
        environment = AgentTaskBudgetProbe.environment(appContext)
    )
    persistExecutionLoopEvent(event)
    recordAudit(
        AgentAuditEvent.REASONING_SUMMARY,
        "execution_profile=${profile.taskKind.name}; effort=${profile.reasoningEffort.name}; " +
            "no_progress_ms=${event.snapshot.budget.noProgressTimeoutMillis}; " +
            "task_budget=${taskBudget.profile.wireValue}"
    )
    if (event.snapshot.budgetFailure.isNotBlank()) {
        phase = AgentPhase.FAILED
        lastActionResult = AgentActionResult(
            actionId = "agent-task-budget",
            success = false,
            message = event.snapshot.budgetFailure
        )
        saveTaskRecord(result = event.snapshot.budgetFailure)
        return false
    }
    return true
}

internal fun MobileNativeAgent.recordTaskBudgetUsage(
    inputTokens: Long = 0L,
    outputTokens: Long = 0L,
    costMicros: Long = 0L,
    networkBytes: Long = 0L,
    estimated: Boolean = false
): Boolean {
    if (executionLoop.snapshot == null) return true
    val event = executionLoop.recordTaskBudgetUsage(
        inputTokens = inputTokens,
        outputTokens = outputTokens,
        costMicros = costMicros,
        networkBytes = networkBytes,
        estimated = estimated,
        environment = AgentTaskBudgetProbe.environment(appContext)
    )
    persistExecutionLoopEvent(event)
    if (event.snapshot.budgetFailure.isBlank()) return true
    phase = AgentPhase.FAILED
    lastActionResult = AgentActionResult(
        actionId = "agent-task-budget",
        success = false,
        message = event.snapshot.budgetFailure
    )
    saveTaskRecord(result = event.snapshot.budgetFailure)
    return false
}

internal fun MobileNativeAgent.advanceExecutionLoop(
    nextPhase: AgentExecutionLoopPhase,
    reason: String,
    actionId: String = "",
    toolCall: Boolean = false,
    retry: Boolean = false
): Boolean {
    val current = executionLoop.snapshot ?: return true
    if (current.phase == nextPhase && !retry) return current.budgetFailure.isBlank()
    val event = executionLoop.transition(
        phase = nextPhase,
        reason = reason,
        actionId = actionId,
        toolCall = toolCall,
        retry = retry
    )
    persistExecutionLoopEvent(event)
    if (event.snapshot.budgetFailure.isNotBlank()) {
        phase = AgentPhase.FAILED
        lastActionResult = AgentActionResult(
            actionId = actionId.ifBlank { "agent-loop-budget" },
            success = false,
            message = event.snapshot.budgetFailure
        )
        saveTaskRecord(result = event.snapshot.budgetFailure)
        return false
    }
    return true
}

internal fun MobileNativeAgent.persistExecutionLoopEvent(event: AgentExecutionLoopEvent) {
    persistSession()
    executionLoopEventSink.onEvent(event)
}

internal fun MobileNativeAgent.recordExecutionFailure(
    failureClass: String,
    reason: String,
    actionId: String
): Boolean {
    val event = executionLoop.recordFailure(
        failureClass = failureClass,
        reason = reason,
        actionId = actionId
    )
    persistExecutionLoopEvent(event)
    if (event.phase != AgentExecutionLoopPhase.FAILED) return true
    phase = AgentPhase.FAILED
    lastActionResult = AgentActionResult(
        actionId = actionId.ifBlank { "agent-loop-failure" },
        success = false,
        message = event.snapshot.budgetFailure.ifBlank { reason }
    )
    saveTaskRecord(result = lastActionResult?.message.orEmpty())
    return false
}

internal fun MobileNativeAgent.reconcileExecutionLoop(state: AgentUiState): AgentUiState {
    val loop = executionLoop.snapshot ?: return state
    if (loop.phase.isTerminal) return state
    when (state.phase) {
        AgentPhase.WAITING_CONFIRMATION -> advanceExecutionLoop(
            AgentExecutionLoopPhase.WAITING_CONFIRMATION,
            state.pendingAction?.description.orEmpty().ifBlank { "Waiting for confirmation" },
            state.pendingAction?.id.orEmpty()
        )
        AgentPhase.WAITING_RESPONSE -> advanceExecutionLoop(
            AgentExecutionLoopPhase.WAITING_RESPONSE,
            state.lastActionResult?.message.orEmpty().ifBlank { "Waiting for a resource response" },
            state.lastActionResult?.actionId.orEmpty()
        )
        AgentPhase.PAUSED -> {
            if (loop.phase != AgentExecutionLoopPhase.PAUSED) {
                val event = executionLoop.pause(
                    state.lastActionResult?.message.orEmpty().ifBlank { "Task paused" }
                )
                persistExecutionLoopEvent(event)
            }
        }
        AgentPhase.BLOCKED -> advanceExecutionLoop(
            AgentExecutionLoopPhase.BLOCKED,
            state.plan?.safetyReview?.reason.orEmpty().ifBlank { "Task blocked" },
            state.pendingAction?.id.orEmpty()
        )
        AgentPhase.FAILED -> advanceExecutionLoop(
            AgentExecutionLoopPhase.FAILED,
            state.lastActionResult?.message.orEmpty().ifBlank { "Task failed" },
            state.lastActionResult?.actionId.orEmpty()
        )
        AgentPhase.CANCELLED -> advanceExecutionLoop(
            AgentExecutionLoopPhase.CANCELLED,
            state.lastActionResult?.message.orEmpty().ifBlank { "Task cancelled" }
        )
        AgentPhase.COMPLETED -> {
            if (loop.phase !in setOf(
                    AgentExecutionLoopPhase.VERIFY,
                    AgentExecutionLoopPhase.FINALIZE,
                    AgentExecutionLoopPhase.LEARN,
                    AgentExecutionLoopPhase.COMPLETED
                )
            ) {
                advanceExecutionLoop(
                    AgentExecutionLoopPhase.VERIFY,
                    "Goal outcome ready for verification",
                    state.lastActionResult?.actionId.orEmpty()
                )
            }
        }
        AgentPhase.OBSERVING,
        AgentPhase.PLANNING,
        AgentPhase.EXECUTING,
        AgentPhase.VERIFYING -> Unit
    }
    return snapshot()
}

internal fun MobileNativeAgent.captureScreen(foregroundApp: String? = null, pageTitle: String? = null): ScreenContext {
    if (!safetySettingsStore.load().screenObservationAllowed) {
        return ScreenContext(
            foregroundApp = foregroundApp.orEmpty(),
            pageTitle = pageTitle.orEmpty(),
            isAccessibilityEnabled = false
        )
    }
    return if (foregroundApp != null && pageTitle != null) {
        perceptionProvider.capture(foregroundApp, pageTitle)
    } else {
        perceptionProvider.capture()
    }
}

internal fun MobileNativeAgent.snapshot(): AgentUiState {
    syncActiveWorkflowExecution()
    val context = cachedRuntimeContext()
        ?: AgentActiveRunRuntimeContextPolicy.reuse(
            base = activeRunRuntimeContext,
            goal = currentGoal,
            screen = currentScreen,
            phase = phase
        )?.also(::cacheRuntimeContext)
        ?: run {
            val targets = connectorRegistry.availableTargets()
            val memories = if (currentGoal.isNotBlank()) memoryStore.recall(currentGoal) else emptyList()
            val knowledge = knowledgeStore.querySnapshot(currentGoal)
            buildRuntimeContext(
                goal = currentGoal,
                screen = currentScreen,
                targets = targets,
                memories = memories,
                knowledgeItems = knowledge.items,
                knowledgeStats = knowledge.stats
            ).also(::cacheRuntimeContext)
        }
    return AgentUiState(
        phase = phase,
        currentGoal = currentGoal,
        currentScreen = currentScreen,
        taskExecutionMode = activeTaskExecutionMode,
        permissionMode = context.permissionMode,
        highRiskGuard = context.highRiskGuard,
        callableTargets = context.callableTargets,
        runtimeContext = context,
        runningTaskCount = if (phase == AgentPhase.PLANNING ||
            phase == AgentPhase.WAITING_CONFIRMATION ||
            phase == AgentPhase.EXECUTING ||
            phase == AgentPhase.VERIFYING ||
            phase == AgentPhase.WAITING_RESPONSE ||
            phase == AgentPhase.PAUSED) 1 else 0,
        steps = currentPlan?.steps ?: defaultSteps(),
        lastEvent = if (currentGoal.isBlank()) AgentEvent.WAITING_FOR_GOAL else AgentEvent.GOAL_RECEIVED,
        sessionId = sessionId,
        plan = currentPlan,
        pendingAction = if (phase == AgentPhase.BLOCKED) {
            null
        } else {
            currentPlan?.actions?.firstOrNull { it.status == AgentActionStatus.PENDING_CONFIRMATION }
        },
        auditTrail = auditTrail.toList(),
        lastActionResult = lastActionResult,
        recentTasks = taskStore.recent(limit = 3),
        executionLoop = executionLoop.snapshot
    )
}

internal fun MobileNativeAgent.reloadSession(): AgentUiState {
    restoreSession(sessionStore.load())
    return snapshot()
}

internal fun MobileNativeAgent.agentRegistrySnapshot(): List<AgentRegistration> = connectorRegistry.registrations()

internal fun MobileNativeAgent.agentReputation(
    agentId: String,
    capabilities: Set<AgentCapability> = emptySet()
): AgentReputationSnapshot = reputationLedger.snapshot(agentId, capabilities)

internal fun MobileNativeAgent.recordAgentExecutionReceipt(
    receipt: AgentSignedExecutionReceipt
): AgentReputationRecordResult = reputationLedger.record(receipt)

internal fun MobileNativeAgent.recordAgentVerification(
    attestation: AgentSignedReputationAttestation
): AgentReputationRecordResult = reputationLedger.record(attestation)

internal fun MobileNativeAgent.startNewConversation(conversationId: String): AgentUiState {
    val previousSessionId = sessionId
    PhoneExecutionAuthority.requestCancellation(previousSessionId)
    confirmationConsentStore.endSession(previousSessionId)
    sessionId = UUID.randomUUID().toString()
    PhoneExecutionAuthority.clearCancellation(sessionId)
    activeConversationContext = AgentConversationContext(conversationId, "", emptyList(), false)
    activeConversationTurnId = ""
    phase = AgentPhase.OBSERVING
    currentGoal = ""
    currentScreen = captureScreen()
    currentPlan = null
    lastActionResult = null
    activeWorkflowExecutionId = null
    executionLoop = AgentExecutionLoop.create()
    auditTrail.clear()
    persistSession()
    return snapshot()
}

internal fun MobileNativeAgent.knowledgeSourceGroups(): List<AgentKnowledgeSourceGroup> =
    AgentKnowledgeRetriever.sourceGroups(knowledgeStore)

internal fun MobileNativeAgent.nativeToolCatalog(): List<AgentNativeToolDescriptor> = nativeToolRegistry.descriptors()

internal fun MobileNativeAgent.nativeToolIds(): Set<String> = AgentPhoneNativeToolCatalog.defaultToolIds

internal fun MobileNativeAgent.resolveDeterministicLocalAction(
    goal: String,
    conversationContext: AgentConversationContext
): AgentAction? = RuleBasedAgentPlanner(appContext).deterministicLocalAction(
    deterministicRoutingRequest(goal, conversationContext)
)

internal fun MobileNativeAgent.resolveDeterministicAction(
    goal: String,
    conversationContext: AgentConversationContext
): AgentAction? {
    val request = deterministicRoutingRequest(goal, conversationContext)
    val planner = RuleBasedAgentPlanner(appContext)
    return planner.deterministicLocalAction(request)
        ?: planner.directInformationConnectorAction(request)
}

internal fun MobileNativeAgent.deterministicRoutingRequest(
    goal: String,
    conversationContext: AgentConversationContext
): AgentRequest {
    val screen = if (AgentScreenObservationPolicy.requiresObservation(goal)) {
        captureScreen().also { currentScreen = it }
    } else {
        ScreenContext(foregroundApp = "", pageTitle = "")
    }
    val targets = connectorRegistry.availableTargets()
    val context = buildRuntimeContext(
        goal = goal,
        screen = screen,
        targets = targets,
        memories = emptyList(),
        knowledgeItems = emptyList(),
        knowledgeStats = AgentKnowledgeStats()
    )
    return AgentRequest(
        goal = goal,
        screen = screen,
        targets = targets,
        memories = emptyList(),
        runtimeContext = context,
        conversationContext = conversationContext
    )
}

internal fun MobileNativeAgent.nativeToolAudit(
    limit: Int = 100,
    toolId: String = "",
    status: AgentNativeToolResultStatus? = null
): List<AgentNativeToolAuditRecord> = nativeToolRegistry.audit(limit, toolId, status)

internal fun MobileNativeAgent.executeDirectAction(
    action: AgentAction,
    conversationId: String = "",
    turnId: String = ""
): AgentActionResult {
    return executeAction(
        action,
        currentScreen,
        userConfirmed = true,
        conversationIdOverride = conversationId,
        turnIdOverride = turnId
    )
}

internal fun MobileNativeAgent.invokeNativeTool(
    toolId: String,
    input: AgentNativeJsonObject,
    grantedPermissions: Set<String> = emptySet(),
    grantedConsents: Set<String> = emptySet(),
    cancellationToken: AgentNativeToolCancellationToken = AgentNativeToolCancellationToken.NONE,
    conversationId: String = "",
    turnId: String = ""
): AgentNativeToolResult {
    val effectiveConversationId = conversationId.ifBlank { activeConversationContext.conversationId }
    val workspaceId = AgentWorkspaceScope.id(effectiveConversationId, sessionId)
    val descriptor = nativeToolRegistry.lookup(toolId)?.descriptor
    val invocationContext = AgentNativeToolInvocationContext(
        sessionId = sessionId,
        conversationId = effectiveConversationId,
        turnId = turnId.ifBlank { activeConversationTurnId },
        grantedPermissions = grantedPermissions +
            descriptor?.requiredPermissions.orEmpty().filter { it.required }.map { it.id },
        grantedConsents = grantedConsents +
            descriptor?.requiredConsents.orEmpty().filter { it.required }.map { it.id },
        attributes = mapOf(
            "execution_authority" to "signalasi-phone",
            "workspace_id" to workspaceId,
            "permission_mode" to "full_access"
        )
    )
    return nativeToolRegistry.invoke(
        id = toolId,
        input = AgentWorkspaceScope.bindToolInput(toolId, input, workspaceId),
        context = invocationContext,
        hooks = nativeToolHooks(toolId, invocationContext, cancellationToken)
    )
}

internal fun MobileNativeAgent.hasDurablePullRequestEvidence(action: AgentAction): Boolean {
    if (action.kind != AgentActionKind.CALL_NATIVE_TOOL ||
        action.parameters["tool_id"] != AgentMobileProjectNativeTools.CREATE_PULL_REQUEST
    ) {
        return false
    }
    val input = runCatching { JSONObject(action.parameters["input_json"].orEmpty()) }.getOrNull()
        ?: return false
    val head = input.optString("head").trim()
    if (head.isBlank()) return false
    val conversationId = action.parameters[INTERNAL_CONVERSATION_ID].orEmpty()
        .ifBlank { activeConversationContext.conversationId }
    val workspaceId = AgentWorkspaceScope.id(conversationId, sessionId)
    return AgentEncryptedProjectPublicationGuard(appContext)
        .hasPullRequestEvidence(workspaceId, head)
}

internal fun MobileNativeAgent.executeAction(
    action: AgentAction,
    screen: ScreenContext,
    userConfirmed: Boolean = false,
    conversationIdOverride: String = "",
    turnIdOverride: String = ""
): AgentActionResult {
    if (action.kind != AgentActionKind.CALL_NATIVE_TOOL) return actionExecutor.execute(action, screen)
    action.parameters[PHONE_DEVELOPMENT_ERROR_PARAMETER]
        ?.takeIf(String::isNotBlank)
        ?.let { error ->
            val zh = currentGoal.any { it in '\u3400'..'\u9fff' }
            return AgentActionResult(
                actionId = action.id,
                success = false,
                message = if (zh) {
                    "\u6ca1\u6709\u6267\u884c\u4ee3\u7801\uff1a${error.take(500)}\u3002\n\n\u8bf7\u91cd\u65b0\u53d1\u9001\u4efb\u52a1\uff0c\u6211\u4f1a\u91cd\u65b0\u751f\u6210\u5e76\u9a8c\u8bc1\u3002"
                } else {
                    "The code was not executed: ${error.take(500)}.\n\nSend the task again to regenerate and verify it."
                }
            )
        }
    val toolId = action.parameters["tool_id"].orEmpty()
    val descriptor = nativeToolRegistry.lookup(toolId)?.descriptor
        ?: return AgentActionResult(action.id, false, "Native tool is not registered: $toolId")
    val input = runCatching { nativeJsonObject(action.parameters["input_json"].orEmpty()) }
        .getOrElse { return AgentActionResult(action.id, false, it.message ?: "Invalid native tool input") }
    val effectiveConversationId = conversationIdOverride
        .ifBlank { action.parameters[INTERNAL_CONVERSATION_ID].orEmpty() }
        .ifBlank { activeConversationContext.conversationId }
    val effectiveTurnId = turnIdOverride
        .ifBlank { action.parameters[INTERNAL_TURN_ID].orEmpty() }
        .ifBlank { activeConversationTurnId }
    val workspaceId = AgentWorkspaceScope.id(effectiveConversationId, sessionId)
    val scopedInput = AgentWorkspaceScope.bindToolInput(toolId, input, workspaceId)
    val confirmationTier = AgentConfirmationPolicy.tier(action)
    val rememberedConsent = confirmationTier == AgentConfirmationTier.CONFIRM_ONCE &&
        confirmationConsentStore.decision(
            AgentConfirmationPolicy.consentKey(action),
            sessionId
        ).allowed
    val fullAccess = safetyPolicy.permissionMode() == PermissionMode.FULL_ACCESS
    val grantedConsents = if (
        fullAccess || userConfirmed || confirmationTier == AgentConfirmationTier.DIRECT || rememberedConsent
    ) {
        descriptor.requiredConsents.mapTo(linkedSetOf()) { it.id }
    } else {
        emptySet()
    }
    val invocationContext = AgentNativeToolInvocationContext(
        sessionId = sessionId,
        conversationId = effectiveConversationId,
        turnId = effectiveTurnId,
        callerId = "signalasi.mobile_agent.plan",
        idempotencyKey = if (descriptor.idempotency == AgentNativeToolIdempotency.IDEMPOTENCY_KEY_REQUIRED) {
            action.id
        } else null,
        grantedPermissions = descriptor.requiredPermissions.mapTo(linkedSetOf()) { it.id },
        grantedConsents = grantedConsents,
        attributes = mapOf(
            "execution_authority" to "signalasi-phone",
            "confirmation_id" to action.id,
            "step_id" to action.id,
            "workspace_id" to workspaceId,
            "explicit_user_approval" to (fullAccess || userConfirmed || rememberedConsent).toString(),
            "permission_mode" to safetyPolicy.permissionMode().name.lowercase(Locale.US)
        )
    )
    val toolCancellationSource = AgentNativeToolCancellationSource()
    synchronized(this) {
        activeNativeToolCancellationSource = toolCancellationSource
        activeNativeToolCancellationReason = ""
    }
    val result = try {
        nativeToolRegistry.invoke(
            id = toolId,
            input = scopedInput,
            context = invocationContext,
            hooks = nativeToolHooks(toolId, invocationContext, toolCancellationSource.token)
        )
    } finally {
        synchronized(this) {
            if (activeNativeToolCancellationSource === toolCancellationSource) {
                activeNativeToolCancellationSource = null
            }
        }
    }
    Log.i(
        "SignalASILatency",
        "agent_native_tool stage=registry_return tool=${toolId.take(48)} " +
            "status=${result.status.wireValue} invocation=${result.receipt.invocationId.take(8)}" +
            if (result.isSuccess) {
                ""
            } else {
                " error=${AgentPlannerObservation.sanitize(
                    result.message.ifBlank { result.error?.message.orEmpty() },
                    320
                ).orEmpty()}"
            }
    )
    val renderedOutput = AgentNativeJsonCodec.stringify(result.output).take(MAX_NATIVE_TOOL_EVIDENCE_CHARACTERS)
    val cancellationReason = synchronized(this) {
        activeNativeToolCancellationReason.also {
            if (activeNativeToolCancellationSource == null) activeNativeToolCancellationReason = ""
        }
    }
    val nativeMessage = if (
        result.status == AgentNativeToolResultStatus.CANCELLED && cancellationReason.isNotBlank()
    ) {
        cancellationReason
    } else {
        result.message.ifBlank { result.modelVisibleError() }
    }
    val responseLanguage = action.parameters["response_language"].orEmpty()
    val zh = responseLanguage == "zh" || (responseLanguage.isBlank() && currentGoal.any { it in '\u3400'..'\u9fff' })
    val developmentFile = action.parameters[PHONE_DEVELOPMENT_FILE_PARAMETER].orEmpty()
    val userMessage = if (toolId == AgentOnDeviceRuntimeTools.EXECUTE && developmentFile.isNotBlank()) {
        renderPhoneDevelopmentExecution(result.output, nativeMessage, zh)
    } else {
        renderNativeToolResult(toolId, nativeMessage, result.output, zh)
            .ifBlank { renderedOutput }
    }
    val richOutput = when {
        toolId == AgentOnDeviceRuntimeTools.EXECUTE ->
            AgentRuntimeArtifactUi.artifactOutput(result.output, developmentFile, zh)
        toolId in AgentVisibleCaptureNativeTools.toolIds && result.isSuccess ->
            captureArtifactRichOutput(toolId, result.output, zh)
        else -> ""
    }
    return AgentActionResult(
        actionId = action.id,
        success = result.isSuccess,
        message = userMessage,
        metadata = mapOf(
            "native_tool_id" to toolId,
            "native_tool_status" to result.status.wireValue,
            "native_tool_output" to renderedOutput,
            "invocation_id" to result.receipt.invocationId,
            "started_at_millis" to result.receipt.startedAtEpochMillis.toString(),
            "completed_at_millis" to result.receipt.finishedAtEpochMillis.toString(),
            "provenance" to result.provenance.executorId
        ) + richOutput.takeIf(String::isNotBlank)?.let { mapOf("rich_output" to it) }.orEmpty()
    )
}

private fun AgentNativeToolResult.modelVisibleError(): String {
    val nativeError = error ?: return ""
    val issues = (nativeError.details["issues"] as? Iterable<*>)
        ?.mapNotNull { rawIssue ->
            val issue = rawIssue as? Map<*, *> ?: return@mapNotNull null
            val path = issue["path"]?.toString().orEmpty()
            val code = issue["code"]?.toString().orEmpty()
            val message = issue["message"]?.toString().orEmpty()
            listOf(path, code, message).filter(String::isNotBlank).joinToString(" | ")
                .takeIf(String::isNotBlank)
        }
        .orEmpty()
        .take(8)
    return buildString {
        append(nativeError.message)
        if (issues.isNotEmpty()) append(": ").append(issues.joinToString("; "))
    }.take(MAX_NATIVE_TOOL_EVIDENCE_CHARACTERS)
}

internal fun MobileNativeAgent.cancelActiveNativeTool(reason: String): Boolean = synchronized(this) {
    val source = activeNativeToolCancellationSource ?: return@synchronized false
    activeNativeToolCancellationReason = reason.trim().ifBlank {
        "The native tool stopped reporting progress"
    }
    source.cancel()
}

internal fun MobileNativeAgent.nativeToolHooks(
    toolId: String,
    context: AgentNativeToolInvocationContext,
    cancellationToken: AgentNativeToolCancellationToken = AgentNativeToolCancellationToken.NONE
) = AgentNativeToolInvocationHooks(
    cancellationToken = cancellationToken,
    onStarted = {
        emitNativeToolEvent(
            AgentNativeToolLifecycleEvent(
                stage = AgentNativeToolLifecycleStage.STARTED,
                toolId = toolId,
                invocationId = context.invocationId,
                stepId = context.attributes["step_id"].orEmpty().ifBlank { context.invocationId },
                conversationId = context.conversationId,
                turnId = context.turnId,
                timestampMillis = System.currentTimeMillis()
            )
        )
    },
    onProgress = { _, progress ->
        emitNativeToolEvent(
            AgentNativeToolLifecycleEvent(
                stage = AgentNativeToolLifecycleStage.PROGRESS,
                toolId = toolId,
                invocationId = context.invocationId,
                stepId = context.attributes["step_id"].orEmpty().ifBlank { context.invocationId },
                conversationId = context.conversationId,
                turnId = context.turnId,
                progressStage = progress.stage,
                message = progress.message,
                percent = progress.percent,
                sequence = progress.sequence,
                timestampMillis = progress.timestampEpochMillis
            )
        )
    },
    onFinished = { result ->
        emitNativeToolEvent(
            AgentNativeToolLifecycleEvent(
                stage = AgentNativeToolLifecycleStage.FINISHED,
                toolId = toolId,
                invocationId = context.invocationId,
                stepId = context.attributes["step_id"].orEmpty().ifBlank { context.invocationId },
                conversationId = context.conversationId,
                turnId = context.turnId,
                status = result.status,
                message = result.message.ifBlank { result.error?.message.orEmpty() }.take(2_000),
                timestampMillis = result.receipt.finishedAtEpochMillis
            )
        )
    }
)

internal fun MobileNativeAgent.emitNativeToolEvent(event: AgentNativeToolLifecycleEvent) {
    runCatching { nativeToolEventSink.onEvent(event) }
}

internal fun MobileNativeAgent.renderAndroidSystemToolResult(message: String, output: AgentNativeJsonObject): String {
    if (output.isEmpty()) return message
    val details = output.entries.joinToString("\n") { (key, value) ->
        "${key.replace('_', ' ')}: ${renderAndroidSystemToolValue(value)}"
    }.take(6_000)
    return listOf(message.trim(), details.trim()).filter { it.isNotBlank() }.joinToString("\n")
}

internal fun MobileNativeAgent.renderNativeToolResult(
    toolId: String,
    message: String,
    output: AgentNativeJsonObject,
    zh: Boolean
): String {
    if (output.isEmpty()) return renderNativeToolFailure(message, zh)
    if (toolId == AgentWebMediaNativeTools.WEB_SEARCH) return renderPhoneWebSearchResult(output, zh)
    if (toolId in AgentWebIntelligenceNativeTools.toolIds) {
        return renderPhoneWebIntelligenceResult(toolId, output, zh)
    }
    if (toolId == AgentOnDeviceRuntimeTools.STATUS) return renderRuntimeStatus(output, zh)
    if (toolId == AgentOnDeviceRuntimeTools.LIST_PACKS) return renderRuntimePackList(output, zh)
    if (toolId == AgentOnDeviceRuntimeTools.EXECUTE) return renderRuntimeExecution(output, message, zh)
    if (toolId == AgentOnDeviceRuntimeTools.INSTALL_PACK) return renderRuntimePackInstallation(output, zh)
    if (toolId in AgentDesktopRemoteNativeTools.toolIds) return renderDesktopNativeToolResult(toolId, message, output, zh)
    renderAndroidSystemSummary(toolId, output, zh)?.let { return it }
    if (zh) return renderNativeToolResultChinese(toolId, message, output)
    fun bool(name: String) = output[name] as? Boolean ?: false
    fun long(name: String) = (output[name] as? Number)?.toLong()
    fun number(name: String) = (output[name] as? Number)?.toDouble()
    fun text(name: String) = output[name]?.toString().orEmpty()
    return when (toolId) {
        AgentVisibleCaptureNativeTools.CAMERA_CAPTURE ->
            "Photo captured and attached."
        AgentVisibleCaptureNativeTools.MICROPHONE_RECORD -> {
            val durationSeconds = ((long("duration_ms") ?: 0L) / 1_000.0)
            "Audio recorded and attached (${String.format(Locale.US, "%.1f", durationSeconds)} s)."
        }
        AgentNotificationNativeTools.NOTIFICATIONS_LIST -> renderNotificationList(output, zh = false)
        AgentNotificationNativeTools.NOTIFICATION_REPLY ->
            "The reply was dispatched to ${text("target_title").ifBlank { text("package_name") }.ifBlank { "the notification" }}. Android did not provide a delivery receipt."
        AgentHomeAssistantNativeTools.CONNECTION_STATUS ->
            "Home Assistant is connected."
        AgentHomeAssistantNativeTools.ENTITIES_LIST -> {
            val entities = (output["entities"] as? Iterable<*>)
                ?.mapNotNull { it as? Map<*, *> }
                .orEmpty()
            val lines = entities.take(20).map { entity ->
                val name = entity["friendly_name"]?.toString().orEmpty()
                    .ifBlank { entity["entity_id"]?.toString().orEmpty() }
                val state = entity["state"]?.toString().orEmpty()
                "- $name: $state"
            }
            "Found ${entities.size} Home Assistant entities." +
                (if (lines.isEmpty()) "" else lines.joinToString("\n", prefix = "\n"))
        }
        AgentHomeAssistantNativeTools.ENTITY_READ -> {
            val entity = output["entity"] as? Map<*, *> ?: emptyMap<Any?, Any?>()
            val name = entity["friendly_name"]?.toString().orEmpty()
                .ifBlank { entity["entity_id"]?.toString().orEmpty() }
            "$name is ${entity["state"]?.toString().orEmpty().ifBlank { "unknown" }}."
        }
        AgentHomeAssistantNativeTools.SERVICE_CALL -> {
            val target = text("entity_id").ifBlank { "the Home Assistant entity" }
            val service = text("service").replace('_', ' ')
            when {
                bool("controller_state_verified") ->
                    "Ran $service for $target. Home Assistant now reports ${text("current_state").ifBlank { "the requested state" }}."
                bool("verification_supported") ->
                    "Home Assistant accepted $service for $target, but its controller state has not matched yet."
                else -> "Home Assistant accepted $service for $target."
            }
        }
        AgentHardwareNativeTools.BATTERY_STATUS -> {
            val percent = long("percent")?.toString() ?: "unknown"
            val charging = bool("charging")
            val status = text("status")
            when {
                status == "full" -> "Phone battery is $percent% and fully charged."
                charging -> "Phone battery is $percent% and charging."
                else -> "Phone battery is $percent%."
            }
        }
        AgentHardwareNativeTools.POWER_STATUS ->
            "Screen is ${if (bool("interactive")) "on" else "off"}. Battery Saver is ${if (bool("power_save_mode")) "on" else "off"}; Doze is ${if (bool("device_idle_mode")) "active" else "inactive"}."
        AgentHardwareNativeTools.MEMORY_STATUS -> {
            val used = formatBytes(long("used_bytes") ?: 0L)
            val total = formatBytes(long("total_bytes") ?: 0L)
            val available = formatBytes(long("available_bytes") ?: 0L)
            val percent = long("used_percent") ?: 0L
            "Phone memory: $used used of $total, $available available ($percent%). " +
                if (bool("low_memory")) "Android reports low memory." else "Memory status is normal."
        }
        AgentHardwareNativeTools.STORAGE_STATUS -> {
            val available = formatBytes(long("available_bytes") ?: 0L)
            val total = formatBytes(long("total_bytes") ?: 0L)
            "Available storage is $available of $total on the app volume."
        }
        AgentHardwareNativeTools.NETWORK_STATUS -> {
            val transports = (output["transports"] as? Iterable<*>)?.joinToString(", ") { it.toString() }.orEmpty()
            if (!bool("connected")) {
                "The phone is currently offline."
            } else {
                "The phone is connected over ${transports.ifBlank { "an active network" }}. Internet is ${if (bool("validated")) "available" else "not yet validated"}; the connection is ${if (bool("metered")) "metered" else "unmetered"}."
            }
        }
        AgentHardwareNativeTools.LOCATION_FOREGROUND_READ -> {
            val latitude = number("latitude")
            val longitude = number("longitude")
            val accuracy = number("accuracy_meters")
            "Current location: ${formatCoordinate(latitude)}, ${formatCoordinate(longitude)} (about ${accuracy?.toInt() ?: 0} m accuracy)."
        }
        AgentHardwareNativeTools.SENSORS_LIST -> {
            val sensors = (output["sensors"] as? Iterable<*>)
                ?.mapNotNull { (it as? Map<*, *>)?.get("name")?.toString() }
                .orEmpty()
            val names = sensors.take(12).joinToString(", ")
            val suffix = if (sensors.size > 12) ", and more" else ""
            "Found ${sensors.size} sensors: $names$suffix."
        }
        AgentHardwareNativeTools.SENSOR_SAMPLE -> {
            val values = (output["values"] as? Iterable<*>)?.joinToString(", ") { it.toString() }.orEmpty()
            "One ${text("type")} sample: $values."
        }
        AgentHardwareNativeTools.FLASHLIGHT_SET -> {
            val enabled = bool("requested_enabled")
            if (enabled) "Flashlight turned on." else "Flashlight turned off."
        }
        AgentHardwareNativeTools.BLUETOOTH_STATUS ->
            if (!bool("supported")) "This phone does not support Bluetooth." else "Bluetooth is ${if (bool("enabled")) "on" else "off"}."
        AgentHardwareNativeTools.BLUETOOTH_DISCOVERY_FOREGROUND -> {
            val count = long("result_count") ?: 0L
            "Bluetooth scan finished and found $count devices."
        }
        AgentHardwareNativeTools.NFC_STATUS ->
            if (!bool("supported")) "This phone does not support NFC." else "NFC is ${if (bool("enabled")) "on" else "off"}."
        AgentHardwareNativeTools.INSTALLED_APPS_LIST -> {
            val apps = (output["apps"] as? Iterable<*>)
                ?.mapNotNull { (it as? Map<*, *>)?.get("label")?.toString() }
                .orEmpty()
            val names = apps.take(12).joinToString(", ")
            val remaining = (apps.size - 12).coerceAtLeast(0)
            "Found ${apps.size} query-visible apps: $names${if (remaining > 0) ", and $remaining more" else ""}."
        }
        AgentHardwareNativeTools.PACKAGE_DETAIL ->
            if (!bool("visible")) renderPackageUnavailable(text("package_name"), false)
            else "${text("label").ifBlank { text("package_name") }} ${text("version_name")} (${text("package_name")})."
        AgentAndroidSystemNativeTools.AUDIO_VOLUME_SET -> {
            val volume = long("volume") ?: 0L
            val max = long("max") ?: 0L
            val actualPercent = if (max > 0L) {
                ((volume * 100L + max / 2L) / max).coerceIn(0L, 100L)
            } else {
                long("percent") ?: 0L
            }
            val stream = audioStreamLabel(text("stream"), zh)
            if (zh) "$stream\u97f3\u91cf\u5df2\u8bbe\u4e3a $actualPercent%\u3002" else "$stream volume is now $actualPercent%."
        }
        AgentAndroidSystemNativeTools.AUDIO_MUTE_SET -> {
            val stream = audioStreamLabel(text("stream"), zh)
            val muted = bool("muted")
            if (zh) "$stream\u5df2${if (muted) "\u9759\u97f3" else "\u53d6\u6d88\u9759\u97f3"}\u3002"
            else "$stream is ${if (muted) "muted" else "unmuted"}."
        }
        AgentHardwareNativeTools.BLUETOOTH_PAIRING_HANDOFF,
        AgentAndroidSystemNativeTools.WIFI_PANEL_OPEN,
        AgentAndroidSystemNativeTools.WIFI_HOTSPOT_PANEL_OPEN,
        AgentAndroidSystemNativeTools.BIOMETRIC_ENROLLMENT_OPEN,
        AgentAndroidSystemNativeTools.VPN_CONSENT_OPEN,
        AgentAndroidSystemNativeTools.TELEPHONY_DIAL_HANDOFF,
        AgentAndroidSystemNativeTools.SMS_COMPOSE_HANDOFF -> message.trim()
        else -> if (toolId in AgentAndroidSystemNativeTools.toolIds || toolId in AgentWebMediaNativeTools.toolIds) {
            renderAndroidSystemToolResult(message, output)
        } else {
            message
        }
    }
}

internal fun MobileNativeAgent.renderDesktopNativeToolResult(
    toolId: String,
    message: String,
    output: AgentNativeJsonObject,
    zh: Boolean
): String {
    fun long(name: String) = (output[name] as? Number)?.toLong()
    fun text(name: String) = output[name]?.toString().orEmpty()
    fun maps(name: String) = (output[name] as? Iterable<*>)?.mapNotNull { it as? Map<*, *> }.orEmpty()
    fun heading(chinese: String, english: String) = if (zh) chinese else english
    return when (toolId) {
        AgentDesktopRemoteNativeTools.SYSTEM_STATUS -> {
            val available = formatBytes(long("memory_available_bytes") ?: 0L)
            val total = formatBytes(long("memory_total_bytes") ?: 0L)
            if (zh) {
                "Windows ${text("release")}\uff0c${text("architecture")}\uff0c${long("logical_cpu_count") ?: 0} \u4e2a\u903b\u8f91\u5904\u7406\u5668\u3002\u53ef\u7528\u5185\u5b58 $available / $total\u3002"
            } else {
                "Windows ${text("release")} on ${text("architecture")} with ${long("logical_cpu_count") ?: 0} logical processors. Available memory: $available of $total."
            }
        }
        AgentDesktopRemoteNativeTools.PROCESS_LIST -> {
            val processes = maps("processes")
            val lines = processes.take(20).map { row ->
                val name = row["name"]?.toString().orEmpty()
                val pid = row["pid"]?.toString().orEmpty()
                val memoryMb = ((row["memory_kb"] as? Number)?.toLong() ?: 0L) / 1_024L
                "- $name (PID $pid, ${memoryMb} MB)"
            }
            heading("\u627e\u5230 ${processes.size} \u4e2a Windows \u8fdb\u7a0b\uff1a", "Found ${processes.size} Windows processes:") +
                if (lines.isEmpty()) "" else "\n" + lines.joinToString("\n")
        }
        AgentDesktopRemoteNativeTools.FILE_LIST -> {
            val entries = maps("entries")
            val lines = entries.take(40).map { row ->
                val suffix = if (row["type"] == "directory") "/" else ""
                "- ${row["path"]}$suffix"
            }
            heading("Desktop \u5de5\u4f5c\u533a\u5305\u542b ${entries.size} \u9879\uff1a", "Desktop workspace contains ${entries.size} entries:") +
                if (lines.isEmpty()) "" else "\n" + lines.joinToString("\n")
        }
        AgentDesktopRemoteNativeTools.FILE_READ_TEXT -> {
            val path = text("path")
            val body = text("text").take(12_000)
            heading("\u5df2\u8bfb\u53d6 $path\uff1a", "Read $path:") + "\n\n```text\n$body\n```"
        }
        AgentDesktopRemoteNativeTools.FILE_WRITE_TEXT ->
            heading("\u5df2\u5199\u5165 ${text("path")}\uff08${formatBytes(long("size_bytes") ?: 0L)}\uff09\u3002", "Wrote ${text("path")} (${formatBytes(long("size_bytes") ?: 0L)}).")
        AgentDesktopRemoteNativeTools.FILE_SHA256 ->
            heading("${text("path")} \u7684 SHA-256\uff1a${text("sha256")}", "SHA-256 for ${text("path")}: ${text("sha256")}")
        AgentDesktopRemoteNativeTools.ARCHIVE_CREATE ->
            heading("\u5df2\u521b\u5efa ${text("path")}\uff0c\u5305\u542b ${long("entry_count") ?: 0} \u4e2a\u6587\u4ef6\u3002", "Created ${text("path")} with ${long("entry_count") ?: 0} files.")
        AgentDesktopRemoteNativeTools.TERMINAL_RUN -> {
            val exitCode = long("exit_code") ?: 0L
            val stdout = text("stdout").trim().take(12_000)
            val stderr = text("stderr").trim().take(6_000)
            buildList {
                add(heading("Desktop \u547d\u4ee4\u5df2\u5b8c\u6210\uff0c\u9000\u51fa\u7801 $exitCode\u3002", "Desktop command completed with exit code $exitCode."))
                if (stdout.isNotBlank()) add("```text\n$stdout\n```")
                if (stderr.isNotBlank()) add(heading("\u9519\u8bef\u8f93\u51fa\uff1a", "Error output:") + "\n```text\n$stderr\n```")
            }.joinToString("\n\n")
        }
        AgentDesktopRemoteNativeTools.OFFICE_INSPECT -> {
            val documentType = text("document_type")
            val details = if (documentType == "excel") {
                (output["rows"] as? Iterable<*>)?.take(30)?.joinToString("\n") { row ->
                    (row as? Iterable<*>)?.joinToString("\t") { it?.toString().orEmpty() }.orEmpty()
                }.orEmpty()
            } else {
                (output["text_items"] as? Iterable<*>)?.take(40)?.joinToString("\n") { "- ${it?.toString().orEmpty()}" }.orEmpty()
            }
            heading("\u5df2\u68c0\u67e5 ${text("path")}\uff08$documentType\uff09\u3002", "Inspected ${text("path")} ($documentType).") +
                details.takeIf(String::isNotBlank)?.let { "\n\n$it" }.orEmpty()
        }
        AgentDesktopRemoteNativeTools.OFFICE_CONVERT ->
            heading("\u5df2\u751f\u6210 ${text("path")}\uff08${formatBytes(long("size_bytes") ?: 0L)}\uff09\u3002", "Created ${text("path")} (${formatBytes(long("size_bytes") ?: 0L)}).")
        else -> message.trim()
    }
}

internal fun MobileNativeAgent.renderRuntimeExecution(output: AgentNativeJsonObject, message: String, zh: Boolean): String {
    val exitCode = (output["exit_code"] as? Number)?.toInt()
    val stdout = output["stdout"]?.toString().orEmpty().trim().take(6_000)
    val stderr = output["stderr"]?.toString().orEmpty().trim().take(3_000)
    val duration = (output["duration_ms"] as? Number)?.toLong()
    val artifacts = (output["artifacts"] as? Iterable<*>)
        ?.mapNotNull { (it as? Map<*, *>)?.get("relative_path")?.toString()?.takeIf(String::isNotBlank) }
        .orEmpty()
    val heading = when {
        exitCode == 0 && zh -> "\u5df2\u5728\u624b\u673a\u672c\u673a Linux \u73af\u5883\u4e2d\u5b8c\u6210\u8fd0\u884c\u3002"
        exitCode == 0 -> "Completed in the phone's on-device Linux runtime."
        zh -> "\u672c\u673a\u8fd0\u884c\u5931\u8d25\uff0c\u9000\u51fa\u7801\u4e3a ${exitCode ?: "\u672a\u77e5"}\u3002"
        else -> "The on-device run failed with exit code ${exitCode ?: "unknown"}."
    }
    return buildList {
        add(heading)
        if (stdout.isNotBlank()) add(if (zh) "\u7ed3\u679c\uff1a\n$stdout" else "Result:\n$stdout")
        if (stderr.isNotBlank()) add(if (zh) "\u9519\u8bef\uff1a\n$stderr" else "Error:\n$stderr")
        if (stderr.isBlank() && exitCode != 0 && message.isNotBlank()) {
            add(if (zh) "\u9519\u8bef\uff1a\n${message.take(3_000)}" else "Error:\n${message.take(3_000)}")
        }
        if (artifacts.isNotEmpty()) {
            add((if (zh) "\u4ea7\u7269\uff1a" else "Artifacts:") + "\n" + artifacts.joinToString("\n") { "- $it" })
        }
        if (duration != null) add(if (zh) "\u8017\u65f6\uff1a${duration} ms" else "Duration: ${duration} ms")
    }.joinToString("\n\n")
}

internal fun MobileNativeAgent.renderPhoneDevelopmentExecution(
    output: AgentNativeJsonObject,
    message: String,
    zh: Boolean
): String {
    val exitCode = (output["exit_code"] as? Number)?.toInt()
    val stdout = output["stdout"]?.toString().orEmpty().trim().take(8_000)
    val stderr = output["stderr"]?.toString().orEmpty().trim().take(4_000)
    val passed = exitCode == 0
    return buildList {
        if (stdout.isNotBlank()) {
            add((if (zh) "\u8fd0\u884c\u7ed3\u679c\uff1a" else "Run output:") + "\n\n```text\n$stdout\n```")
        }
        if (stderr.isNotBlank()) {
            add((if (zh) "\u9519\u8bef\u4fe1\u606f\uff1a" else "Error output:") + "\n\n```text\n$stderr\n```")
        }
        if (!passed && stderr.isBlank() && message.isNotBlank()) {
            add((if (zh) "\u4e0b\u4e00\u6b65\uff1a" else "Next step: ") + message.take(1_000))
        }
    }.joinToString("\n\n")
}

internal fun MobileNativeAgent.renderRuntimeStatus(output: AgentNativeJsonObject, zh: Boolean): String {
    val ready = output["backend_ready"] as? Boolean == true
    val backend = output["backend"]?.toString().orEmpty()
    val reason = output["reason"]?.toString().orEmpty()
    val languages = (output["languages"] as? Iterable<*>)
        ?.mapNotNull { it as? Map<*, *> }
        ?.filter { it["ready"] == true }
        ?.mapNotNull { it["id"]?.toString() }
        .orEmpty()
    return if (zh) {
        "\u672c\u673a Linux \u8fd0\u884c\u73af\u5883${if (ready) "\u5df2\u5c31\u7eea" else "\u5c1a\u672a\u5c31\u7eea"}\u3002" +
            "\n\n\u540e\u7aef\uff1a${backend.ifBlank { "\u65e0" }}" +
            "\n\u53ef\u7528\u80fd\u529b\uff1a${languages.joinToString("\u3001").ifBlank { "\u65e0" }}" +
            reason.takeIf(String::isNotBlank)?.let { "\n\u72b6\u6001\uff1a$it" }.orEmpty()
    } else {
        "The on-device Linux runtime is ${if (ready) "ready" else "not ready"}." +
            "\n\nBackend: ${backend.ifBlank { "none" }}" +
            "\nAvailable: ${languages.joinToString(", ").ifBlank { "none" }}" +
            reason.takeIf(String::isNotBlank)?.let { "\nStatus: $it" }.orEmpty()
    }
}

internal fun MobileNativeAgent.renderRuntimePackList(output: AgentNativeJsonObject, zh: Boolean): String {
    val packs = (output["packs"] as? Iterable<*>)
        ?.mapNotNull { it as? Map<*, *> }
        .orEmpty()
    val lines = packs.map { row ->
        val id = row["id"]?.toString().orEmpty()
        val state = row["state"]?.toString().orEmpty()
        val version = row["version"]?.toString().orEmpty()
        "- $id: $state${version.takeIf(String::isNotBlank)?.let { " ($it)" }.orEmpty()}"
    }
    val heading = if (zh) "\u672c\u673a\u8fd0\u884c\u5305\uff1a" else "On-device runtime packs:"
    return heading + if (lines.isEmpty()) "\n-" else "\n" + lines.joinToString("\n")
}

internal fun MobileNativeAgent.renderRuntimePackInstallation(output: AgentNativeJsonObject, zh: Boolean): String {
    val requested = output["requested_pack"]?.toString().orEmpty()
    val installed = (output["installed"] as? Iterable<*>)
        ?.mapNotNull { it as? Map<*, *> }
        ?.mapNotNull { row ->
            val id = row["pack_id"]?.toString().orEmpty()
            val version = row["version"]?.toString().orEmpty()
            if (id.isBlank()) null else "$id${version.takeIf(String::isNotBlank)?.let { " $it" }.orEmpty()}"
        }
        .orEmpty()
    val ready = installed.ifEmpty { listOf(requested) }.filter(String::isNotBlank)
    return if (zh) {
        "\u672c\u673a\u8fd0\u884c\u73af\u5883\u5df2\u5c31\u7eea\uff1a${ready.joinToString("\u3001")}\u3002"
    } else {
        "On-device runtime ready: ${ready.joinToString(", ")}."
    }
}

internal fun MobileNativeAgent.renderAndroidSystemSummary(
    toolId: String,
    output: AgentNativeJsonObject,
    zh: Boolean
): String? {
    fun bool(name: String) = output[name] as? Boolean ?: false
    fun long(name: String) = (output[name] as? Number)?.toLong()
    fun text(name: String) = output[name]?.toString().orEmpty()
    fun maps(name: String) = (output[name] as? Iterable<*>)?.mapNotNull { it as? Map<*, *> }.orEmpty()
    fun percent(current: Any?, maximum: Any?): Int {
        val value = (current as? Number)?.toDouble() ?: 0.0
        val max = (maximum as? Number)?.toDouble() ?: 0.0
        return if (max <= 0.0) 0 else ((value / max) * 100.0).toInt().coerceIn(0, 100)
    }
    return when (toolId) {
        AgentAndroidSystemNativeTools.DOWNLOAD_ENQUEUE -> AgentAndroidDownloadPolicy.startedMessage(zh)
        AgentAndroidSystemNativeTools.DOWNLOAD_QUERY -> {
            val status = when (long("status")?.toInt()) {
                android.app.DownloadManager.STATUS_PENDING -> if (zh) "\u7b49\u5f85\u4e2d" else "pending"
                android.app.DownloadManager.STATUS_RUNNING -> if (zh) "\u4e0b\u8f7d\u4e2d" else "downloading"
                android.app.DownloadManager.STATUS_PAUSED -> if (zh) "\u5df2\u6682\u505c" else "paused"
                android.app.DownloadManager.STATUS_SUCCESSFUL -> if (zh) "\u5df2\u5b8c\u6210" else "complete"
                android.app.DownloadManager.STATUS_FAILED -> if (zh) "\u5df2\u5931\u8d25" else "failed"
                else -> if (zh) "\u72b6\u6001\u672a\u77e5" else "unknown"
            }
            val downloaded = long("bytes_downloaded") ?: 0L
            val total = long("total_bytes") ?: 0L
            val progress = if (total > 0L) " (${((downloaded * 100L) / total).coerceIn(0L, 100L)}%)" else ""
            if (zh) "\u4e0b\u8f7d\u72b6\u6001\uff1a$status$progress\u3002" else "Download status: $status$progress."
        }
        AgentAndroidSystemNativeTools.DOWNLOAD_REMOVE -> {
            val removed = long("removed") ?: 0L
            if (zh) {
                if (removed > 0L) "\u5df2\u5220\u9664\u4e0b\u8f7d\u8bb0\u5f55\u548c\u6587\u4ef6\u3002" else "\u6ca1\u6709\u627e\u5230\u53ef\u5220\u9664\u7684\u4e0b\u8f7d\u3002"
            } else {
                if (removed > 0L) "Download record and file removed." else "No removable download was found."
            }
        }
        AgentAndroidSystemNativeTools.TELEPHONY_STATUS -> {
            val operator = text("network_operator_name").ifBlank { if (zh) "\u672a\u77e5\u8fd0\u8425\u5546" else "unknown carrier" }
            val data = if (bool("data_enabled")) if (zh) "\u5df2\u5f00\u542f" else "on" else if (zh) "\u5df2\u5173\u95ed" else "off"
            if (zh) "\u79fb\u52a8\u7f51\u7edc\uff1a$operator\u3002\u901a\u8bdd\u72b6\u6001\uff1a${text("call_state")}\uff1b\u79fb\u52a8\u6570\u636e\uff1a$data\u3002"
            else "Mobile service: $operator. Call state: ${text("call_state")}; mobile data: $data."
        }
        AgentAndroidSystemNativeTools.TELEPHONY_CALL_STATE,
        AgentAndroidSystemNativeTools.TELEPHONY_CALL_STATE_OBSERVE ->
            if (zh) "\u5f53\u524d\u901a\u8bdd\u72b6\u6001\uff1a${text("call_state").ifBlank { "idle" }}\u3002"
            else "Current call state: ${text("call_state").ifBlank { "idle" }}."
        AgentAndroidSystemNativeTools.SMS_LIST -> {
            val messages = maps("messages")
            if (messages.isEmpty()) {
                if (zh) "\u6ca1\u6709\u8fd4\u56de\u53ef\u8bfb\u7684\u77ed\u4fe1\u3002" else "No readable SMS messages were returned."
            } else {
                val lines = messages.take(10).map { row ->
                    val sender = row["address"]?.toString().orEmpty().ifBlank { if (zh) "\u672a\u77e5\u53d1\u4ef6\u4eba" else "Unknown sender" }
                    val body = row["body"]?.toString().orEmpty().replace(Regex("\\s+"), " ").take(120)
                    "- $sender: $body"
                }
                (if (zh) "\u6700\u8fd1\u77ed\u4fe1\uff1a" else "Recent SMS messages:") + "\n" + lines.joinToString("\n")
            }
        }
        AgentAndroidSystemNativeTools.CONTACTS_SEARCH -> {
            val contacts = maps("contacts")
            if (contacts.isEmpty()) {
                if (zh) "\u6ca1\u6709\u627e\u5230\u5339\u914d\u7684\u8054\u7cfb\u4eba\u3002" else "No matching contacts were found."
            } else {
                val names = contacts.take(20).mapNotNull { it["display_name"]?.toString()?.takeIf(String::isNotBlank) }
                if (zh) "\u627e\u5230 ${contacts.size} \u4e2a\u8054\u7cfb\u4eba\uff1a${names.joinToString("\u3001")}\u3002"
                else "Found ${contacts.size} contacts: ${names.joinToString(", ")}."
            }
        }
        AgentAndroidSystemNativeTools.CALENDARS_LIST -> {
            val calendars = maps("calendars")
            val names = calendars.mapNotNull { it["display_name"]?.toString()?.takeIf(String::isNotBlank) }
            if (calendars.isEmpty()) {
                if (zh) "\u6ca1\u6709\u53ef\u8bfb\u7684\u65e5\u5386\u3002" else "No readable calendars were found."
            } else if (zh) {
                "\u627e\u5230 ${calendars.size} \u4e2a\u65e5\u5386\uff1a${names.joinToString("\u3001")}\u3002"
            } else "Found ${calendars.size} calendars: ${names.joinToString(", ")}."
        }
        AgentAndroidSystemNativeTools.CALENDAR_EVENTS_QUERY -> {
            val events = maps("events")
            if (events.isEmpty()) {
                if (zh) "\u8be5\u65f6\u95f4\u8303\u56f4\u5185\u6ca1\u6709\u65e5\u7a0b\u3002" else "There are no events in that time range."
            } else {
                val titles = events.take(20).mapNotNull { it["title"]?.toString()?.takeIf(String::isNotBlank) }
                if (zh) "\u627e\u5230 ${events.size} \u4e2a\u65e5\u7a0b\uff1a${titles.joinToString("\u3001")}\u3002"
                else "Found ${events.size} events: ${titles.joinToString(", ")}."
            }
        }
        AgentAndroidSystemNativeTools.WIFI_STATUS -> {
            if (!bool("wifi_enabled")) {
                if (zh) "Wi-Fi \u5df2\u5173\u95ed\u3002" else "Wi-Fi is off."
            } else {
                val ssid = text("ssid").takeUnless { it.isBlank() || it == "<unknown ssid>" }
                val speed = long("link_speed_mbps") ?: 0L
                if (zh) "Wi-Fi \u5df2\u5f00\u542f${ssid?.let { "\uff0c\u5df2\u8fde\u63a5 $it" }.orEmpty()}\uff0c\u94fe\u8def\u901f\u7387 $speed Mbps\uff0c\u4e92\u8054\u7f51${if (bool("validated")) "\u53ef\u7528" else "\u5c1a\u672a\u9a8c\u8bc1"}\u3002"
                else "Wi-Fi is on${ssid?.let { " and connected to $it" }.orEmpty()}. Link speed is $speed Mbps; internet is ${if (bool("validated")) "available" else "not yet validated"}."
            }
        }
        AgentAndroidSystemNativeTools.WIFI_SCAN_RESULTS -> {
            val networks = maps("networks")
            val names = networks.take(20).mapNotNull { it["ssid"]?.toString()?.takeIf(String::isNotBlank) }
            if (networks.isEmpty()) {
                if (zh) "\u6ca1\u6709\u8fd4\u56de\u9644\u8fd1\u7684 Wi-Fi \u7f51\u7edc\u3002" else "No nearby Wi-Fi networks were returned."
            } else if (zh) {
                "\u627e\u5230 ${networks.size} \u4e2a Wi-Fi \u7f51\u7edc\uff1a${names.joinToString("\u3001")}\u3002"
            } else "Found ${networks.size} Wi-Fi networks: ${names.joinToString(", ")}."
        }
        AgentAndroidSystemNativeTools.WIFI_SCAN_START ->
            if (zh) "\u5df2\u8bf7\u6c42\u5237\u65b0 Wi-Fi \u626b\u63cf\u7ed3\u679c\u3002" else "Requested a Wi-Fi scan refresh."
        AgentAndroidSystemNativeTools.AUDIO_STATUS -> {
            val streams = output["streams"] as? Map<*, *> ?: emptyMap<Any, Any>()
            fun streamPercent(name: String): Int {
                val row = streams[name] as? Map<*, *> ?: return 0
                return percent(row["current"], row["max"])
            }
            if (zh) "\u5a92\u4f53 ${streamPercent("music")}%\uff0c\u94c3\u58f0 ${streamPercent("ring")}%\uff0c\u95f9\u949f ${streamPercent("alarm")}%\uff1b\u9ea6\u514b\u98ce${if (bool("microphone_muted")) "\u5df2\u9759\u97f3" else "\u672a\u9759\u97f3"}\u3002"
            else "Media ${streamPercent("music")}%, ringer ${streamPercent("ring")}%, alarm ${streamPercent("alarm")}%" +
                "; microphone is ${if (bool("microphone_muted")) "muted" else "not muted"}."
        }
        AgentAndroidSystemNativeTools.BIOMETRIC_STATUS -> {
            val code = long("can_authenticate_code")?.toInt()
            val state = when (code) {
                0 -> if (zh) "\u53ef\u7528" else "available"
                11 -> if (zh) "\u672a\u5f55\u5165\u751f\u7269\u8bc6\u522b" else "not enrolled"
                12 -> if (zh) "\u8bbe\u5907\u4e0d\u652f\u6301" else "not supported"
                else -> if (zh) "\u5f53\u524d\u4e0d\u53ef\u7528" else "currently unavailable"
            }
            if (zh) "\u751f\u7269\u8bc6\u522b\uff1a$state\uff1b\u8bbe\u5907\u5b89\u5168\u9501${if (bool("device_secure")) "\u5df2\u8bbe\u7f6e" else "\u672a\u8bbe\u7f6e"}\u3002"
            else "Biometrics are $state; a secure device lock is ${if (bool("device_secure")) "configured" else "not configured"}."
        }
        AgentAndroidSystemNativeTools.VPN_STATUS ->
            if (zh) "VPN ${if (bool("active")) "\u5df2\u8fde\u63a5" else "\u672a\u8fde\u63a5"}\uff0c\u7cfb\u7edf\u6388\u6743${if (bool("consent_granted")) "\u5df2\u6388\u4e88" else "\u672a\u6388\u4e88"}\u3002"
            else "VPN is ${if (bool("active")) "connected" else "not connected"}; system consent is ${if (bool("consent_granted")) "granted" else "not granted"}."
        AgentAndroidSystemNativeTools.DEVICE_POLICY_STATUS ->
            if (zh) "\u8bbe\u5907\u7ba1\u7406\u5458${if (bool("admin_active")) "\u5df2\u542f\u7528" else "\u672a\u542f\u7528"}\uff0c\u8bbe\u5907\u6240\u6709\u8005${if (bool("device_owner")) "\u5df2\u914d\u7f6e" else "\u672a\u914d\u7f6e"}\u3002"
            else "Device admin is ${if (bool("admin_active")) "active" else "inactive"}; device owner is ${if (bool("device_owner")) "configured" else "not configured"}."
        else -> null
    }
}

internal fun MobileNativeAgent.renderNativeToolResultChinese(
    toolId: String,
    message: String,
    output: AgentNativeJsonObject
): String {
    fun bool(name: String) = output[name] as? Boolean ?: false
    fun long(name: String) = (output[name] as? Number)?.toLong()
    fun number(name: String) = (output[name] as? Number)?.toDouble()
    fun text(name: String) = output[name]?.toString().orEmpty()
    return when (toolId) {
        AgentVisibleCaptureNativeTools.CAMERA_CAPTURE ->
            "\u5df2\u62cd\u6444\u7167\u7247\u5e76\u6dfb\u52a0\u5230\u5f53\u524d\u4f1a\u8bdd\u3002"
        AgentVisibleCaptureNativeTools.MICROPHONE_RECORD -> {
            val durationSeconds = ((long("duration_ms") ?: 0L) / 1_000.0)
            "\u5df2\u5f55\u5236\u8bed\u97f3\u5e76\u6dfb\u52a0\u5230\u5f53\u524d\u4f1a\u8bdd\uff08${String.format(Locale.US, "%.1f", durationSeconds)} \u79d2\uff09\u3002"
        }
        AgentNotificationNativeTools.NOTIFICATIONS_LIST -> renderNotificationList(output, zh = true)
        AgentNotificationNativeTools.NOTIFICATION_REPLY ->
            "\u5df2\u5c06\u56de\u590d\u4ea4\u7ed9 ${text("target_title").ifBlank { text("package_name") }.ifBlank { "\u8be5\u901a\u77e5" }} \u53d1\u9001\u3002Android \u672a\u63d0\u4f9b\u9001\u8fbe\u56de\u6267\u3002"
        AgentHomeAssistantNativeTools.CONNECTION_STATUS ->
            "Home Assistant \u8fde\u63a5\u6b63\u5e38\u3002"
        AgentHomeAssistantNativeTools.ENTITIES_LIST -> {
            val entities = (output["entities"] as? Iterable<*>)
                ?.mapNotNull { it as? Map<*, *> }
                .orEmpty()
            val lines = entities.take(20).map { entity ->
                val name = entity["friendly_name"]?.toString().orEmpty()
                    .ifBlank { entity["entity_id"]?.toString().orEmpty() }
                val state = entity["state"]?.toString().orEmpty()
                "- $name: $state"
            }
            "\u627e\u5230 ${entities.size} \u4e2a Home Assistant \u5b9e\u4f53\u3002" +
                (if (lines.isEmpty()) "" else lines.joinToString("\n", prefix = "\n"))
        }
        AgentHomeAssistantNativeTools.ENTITY_READ -> {
            val entity = output["entity"] as? Map<*, *> ?: emptyMap<Any?, Any?>()
            val name = entity["friendly_name"]?.toString().orEmpty()
                .ifBlank { entity["entity_id"]?.toString().orEmpty() }
            "$name \u5f53\u524d\u72b6\u6001\uff1a${entity["state"]?.toString().orEmpty().ifBlank { "\u672a\u77e5" }}\u3002"
        }
        AgentHomeAssistantNativeTools.SERVICE_CALL -> {
            val target = text("entity_id").ifBlank { "Home Assistant \u5b9e\u4f53" }
            val service = text("service").replace('_', ' ')
            when {
                bool("controller_state_verified") ->
                    "\u5df2\u5bf9 $target \u6267\u884c $service\uff0cHome Assistant \u63a7\u5236\u5668\u72b6\u6001\u4e3a ${text("current_state").ifBlank { "\u76ee\u6807\u72b6\u6001" }}\u3002"
                bool("verification_supported") ->
                    "Home Assistant \u5df2\u63a5\u53d7 $target \u7684 $service\uff0c\u4f46\u63a7\u5236\u5668\u72b6\u6001\u5c1a\u672a\u5339\u914d\u3002"
                else -> "Home Assistant \u5df2\u63a5\u53d7 $target \u7684 $service\u3002"
            }
        }
        AgentHardwareNativeTools.BATTERY_STATUS -> {
            val percent = long("percent")?.toString() ?: "\u672a\u77e5"
            when {
                text("status") == "full" -> "\u624b\u673a\u7535\u91cf $percent%\uff0c\u5df2\u5145\u6ee1\u3002"
                bool("charging") -> "\u624b\u673a\u7535\u91cf $percent%\uff0c\u6b63\u5728\u5145\u7535\u3002"
                else -> "\u624b\u673a\u7535\u91cf $percent%\u3002"
            }
        }
        AgentHardwareNativeTools.POWER_STATUS ->
            "\u5c4f\u5e55${if (bool("interactive")) "\u5df2\u70b9\u4eae" else "\u5df2\u7184\u706d"}\uff0c" +
                "\u7701\u7535\u6a21\u5f0f${if (bool("power_save_mode")) "\u5df2\u5f00\u542f" else "\u672a\u5f00\u542f"}\uff0c" +
                "Doze ${if (bool("device_idle_mode")) "\u5df2\u542f\u7528" else "\u672a\u542f\u7528"}\u3002"
        AgentHardwareNativeTools.MEMORY_STATUS -> {
            val used = formatBytes(long("used_bytes") ?: 0L)
            val total = formatBytes(long("total_bytes") ?: 0L)
            val available = formatBytes(long("available_bytes") ?: 0L)
            val percent = long("used_percent") ?: 0L
            "\u624b\u673a\u5185\u5b58\uff1a\u5df2\u7528 $used / $total\uff0c\u53ef\u7528 $available\uff08$percent%\uff09\uff1b" +
                if (bool("low_memory")) "Android \u62a5\u544a\u5185\u5b58\u4e0d\u8db3\u3002" else "\u7cfb\u7edf\u5185\u5b58\u72b6\u6001\u6b63\u5e38\u3002"
        }
        AgentHardwareNativeTools.STORAGE_STATUS ->
            "\u5e94\u7528\u6240\u5728\u5b58\u50a8\u5377\u5269\u4f59 ${formatBytes(long("available_bytes") ?: 0L)}\uff0c" +
                "\u5171 ${formatBytes(long("total_bytes") ?: 0L)}\u3002"
        AgentHardwareNativeTools.NETWORK_STATUS -> {
            val transports = (output["transports"] as? Iterable<*>)
                ?.joinToString(", ") { it.toString() }.orEmpty()
            if (!bool("connected")) {
                "\u624b\u673a\u5f53\u524d\u672a\u8fde\u63a5\u7f51\u7edc\u3002"
            } else {
                "\u624b\u673a\u5df2\u901a\u8fc7${transports.ifBlank { "\u7f51\u7edc" }}\u8fde\u63a5\uff0c" +
                    "\u4e92\u8054\u7f51${if (bool("validated")) "\u53ef\u7528" else "\u5c1a\u672a\u9a8c\u8bc1"}\uff0c" +
                    "${if (bool("metered")) "\u6309\u6d41\u91cf\u8ba1\u8d39" else "\u975e\u6309\u6d41\u91cf\u8ba1\u8d39"}\u3002"
            }
        }
        AgentHardwareNativeTools.LOCATION_FOREGROUND_READ ->
            "\u5f53\u524d\u4f4d\u7f6e\uff1a${formatCoordinate(number("latitude"))}, " +
                "${formatCoordinate(number("longitude"))}\uff0c\u7cbe\u5ea6\u7ea6 ${number("accuracy_meters")?.toInt() ?: 0} \u7c73\u3002"
        AgentHardwareNativeTools.SENSORS_LIST -> {
            val sensors = (output["sensors"] as? Iterable<*>)
                ?.mapNotNull { (it as? Map<*, *>)?.get("name")?.toString() }
                .orEmpty()
            val suffix = if (sensors.size > 12) "\u7b49" else ""
            "\u68c0\u6d4b\u5230 ${sensors.size} \u4e2a\u4f20\u611f\u5668\uff1a${sensors.take(12).joinToString("\u3001")}$suffix\u3002"
        }
        AgentHardwareNativeTools.SENSOR_SAMPLE -> {
            val values = (output["values"] as? Iterable<*>)?.joinToString(", ") { it.toString() }.orEmpty()
            "${text("type")} \u5355\u6b21\u91c7\u6837\uff1a$values\u3002"
        }
        AgentHardwareNativeTools.FLASHLIGHT_SET ->
            if (bool("requested_enabled")) "\u5df2\u6253\u5f00\u624b\u7535\u7b52\u3002" else "\u5df2\u5173\u95ed\u624b\u7535\u7b52\u3002"
        AgentHardwareNativeTools.BLUETOOTH_STATUS ->
            if (!bool("supported")) "\u8fd9\u53f0\u624b\u673a\u4e0d\u652f\u6301\u84dd\u7259\u3002"
            else "\u84dd\u7259${if (bool("enabled")) "\u5df2\u5f00\u542f" else "\u672a\u5f00\u542f"}\u3002"
        AgentHardwareNativeTools.BLUETOOTH_DISCOVERY_FOREGROUND ->
            "\u84dd\u7259\u626b\u63cf\u7ed3\u675f\uff0c\u53d1\u73b0 ${long("result_count") ?: 0L} \u53f0\u8bbe\u5907\u3002"
        AgentHardwareNativeTools.NFC_STATUS ->
            if (!bool("supported")) "\u8fd9\u53f0\u624b\u673a\u4e0d\u652f\u6301 NFC\u3002"
            else "NFC ${if (bool("enabled")) "\u5df2\u5f00\u542f" else "\u672a\u5f00\u542f"}\u3002"
        AgentHardwareNativeTools.INSTALLED_APPS_LIST -> {
            val apps = (output["apps"] as? Iterable<*>)
                ?.mapNotNull { (it as? Map<*, *>)?.get("label")?.toString() }
                .orEmpty()
            val remaining = (apps.size - 12).coerceAtLeast(0)
            "\u53ef\u67e5\u8be2\u5230 ${apps.size} \u4e2a\u5e94\u7528\uff1a${apps.take(12).joinToString("\u3001")}" +
                "${if (remaining > 0) "\uff0c\u53e6\u6709 $remaining \u4e2a" else ""}\u3002"
        }
        AgentHardwareNativeTools.PACKAGE_DETAIL ->
            if (!bool("visible")) renderPackageUnavailable(text("package_name"), true)
            else "${text("label").ifBlank { text("package_name") }} ${text("version_name")}\uff08${text("package_name")}\uff09\u3002"
        AgentAndroidSystemNativeTools.AUDIO_VOLUME_SET -> {
            val volume = long("volume") ?: 0L
            val max = long("max") ?: 0L
            val percent = if (max > 0L) ((volume * 100L + max / 2L) / max).coerceIn(0L, 100L) else 0L
            "${audioStreamLabel(text("stream"), true)}\u97f3\u91cf\u5df2\u8bbe\u4e3a $percent%\u3002"
        }
        AgentAndroidSystemNativeTools.AUDIO_MUTE_SET ->
            "${audioStreamLabel(text("stream"), true)}\u5df2${if (bool("muted")) "\u9759\u97f3" else "\u53d6\u6d88\u9759\u97f3"}\u3002"
        AgentHardwareNativeTools.BLUETOOTH_PAIRING_HANDOFF,
        AgentAndroidSystemNativeTools.WIFI_PANEL_OPEN,
        AgentAndroidSystemNativeTools.WIFI_HOTSPOT_PANEL_OPEN,
        AgentAndroidSystemNativeTools.BIOMETRIC_ENROLLMENT_OPEN,
        AgentAndroidSystemNativeTools.VPN_CONSENT_OPEN,
        AgentAndroidSystemNativeTools.TELEPHONY_DIAL_HANDOFF,
        AgentAndroidSystemNativeTools.SMS_COMPOSE_HANDOFF -> message.trim()
        else -> renderAndroidSystemToolResult(message, output)
    }
}

internal fun MobileNativeAgent.renderNativeToolFailure(message: String, zh: Boolean): String {
    val normalized = message.trim().lowercase(Locale.US)
    return when {
        "download record was not found" in normalized -> if (zh) {
            "\u627e\u4e0d\u5230\u8be5\u4e0b\u8f7d\u8bb0\u5f55\u3002\u8bf7\u68c0\u67e5\u4e0b\u8f7d ID \u540e\u91cd\u8bd5\u3002"
        } else "That download record was not found. Check the download ID and try again."
        "bluetooth is disabled" in normalized -> if (zh) {
            "\u84dd\u7259\u5df2\u5173\u95ed\u3002\u8bf7\u5148\u6253\u5f00\u84dd\u7259\uff0c\u518d\u91cd\u8bd5\u626b\u63cf\u3002"
        } else "Bluetooth is off. Turn it on, then try the scan again."
        "location provider" in normalized -> if (zh) {
            "\u5b9a\u4f4d\u670d\u52a1\u5df2\u5173\u95ed\u3002\u8bf7\u5148\u6253\u5f00\u7cfb\u7edf\u5b9a\u4f4d\uff0c\u518d\u91cd\u8bd5\u3002"
        } else "Location is off. Turn on Android Location, then try again."
        "missing permission" in normalized || ("permission" in normalized && "denied" in normalized) -> if (zh) {
            "\u7f3a\u5c11\u6240\u9700\u6743\u9650\u3002\u8bf7\u5141\u8bb8\u540e\u91cd\u8bd5\u3002"
        } else "The required permission is missing. Allow it, then try again."
        "timeout" in normalized || "timed out" in normalized -> if (zh) {
            "\u64cd\u4f5c\u8d85\u65f6\u3002\u8bf7\u68c0\u67e5\u7f51\u7edc\u6216\u8bbe\u5907\u72b6\u6001\u540e\u91cd\u8bd5\u3002"
        } else "The operation timed out. Check the network or device state and try again."
        else -> message.trim().ifBlank {
            if (zh) "\u64cd\u4f5c\u672a\u5b8c\u6210\u3002\u8bf7\u68c0\u67e5\u5f53\u524d\u8bbe\u5907\u72b6\u6001\u540e\u91cd\u8bd5\u3002"
            else "The operation did not complete. Check the current device state and try again."
        }
    }
}

internal fun MobileNativeAgent.renderNotificationList(output: AgentNativeJsonObject, zh: Boolean): String {
    val notifications = (output["notifications"] as? Iterable<*>)
        ?.mapNotNull { it as? Map<*, *> }
        .orEmpty()
    if (notifications.isEmpty()) {
        return if (zh) "\u5f53\u524d\u6ca1\u6709\u53ef\u8bfb\u7684\u901a\u77e5\u3002" else "There are no readable notifications right now."
    }
    val lines = notifications.map { row ->
        val redacted = row["redacted"] as? Boolean == true
        val packageName = row["package_name"]?.toString().orEmpty()
        if (redacted) {
            if (zh) "- $packageName\uff1a\u654f\u611f\u5185\u5bb9\u5df2\u9690\u85cf" else "- $packageName: sensitive content hidden"
        } else {
            val title = row["title"]?.toString().orEmpty().ifBlank { packageName }
            val preview = row["text_preview"]?.toString().orEmpty().replace(Regex("\\s+"), " ").take(160)
            "- $title${preview.takeIf(String::isNotBlank)?.let { ": $it" }.orEmpty()}"
        }
    }
    val heading = if (zh) "\u5f53\u524d\u901a\u77e5\uff1a" else "Current notifications:"
    val suffix = if (output["truncated"] as? Boolean == true) {
        if (zh) "\n- \u5176\u4ed6\u901a\u77e5\u5df2\u7701\u7565" else "\n- More notifications omitted"
    } else ""
    return "$heading\n${lines.joinToString("\n")}$suffix"
}

internal fun MobileNativeAgent.captureArtifactRichOutput(
    toolId: String,
    output: AgentNativeJsonObject,
    zh: Boolean
): String {
    val uri = output["content_uri"]?.toString().orEmpty()
    if (uri.isBlank()) return ""
    val isPhoto = toolId == AgentVisibleCaptureNativeTools.CAMERA_CAPTURE
    val title = when {
        isPhoto && zh -> "\u5df2\u62cd\u6444\u7167\u7247"
        isPhoto -> "Captured photo"
        zh -> "\u5df2\u5f55\u5236\u8bed\u97f3"
        else -> "Recorded audio"
    }
    val message = when {
        isPhoto && zh -> "\u5df2\u62cd\u6444\u7167\u7247\u5e76\u6dfb\u52a0\u5230\u5f53\u524d\u4f1a\u8bdd\u3002"
        isPhoto -> "Photo captured and attached."
        zh -> "\u5df2\u5f55\u5236\u8bed\u97f3\u5e76\u6dfb\u52a0\u5230\u5f53\u524d\u4f1a\u8bdd\u3002"
        else -> "Audio recorded and attached."
    }
    val mediaBlock = AgentRichBlock(
        id = "visible-capture:${AgentNativeJsonCodec.sha256(uri).take(24)}",
        type = if (isPhoto) AgentRichBlockType.IMAGE else AgentRichBlockType.AUDIO,
        title = title,
        uri = uri,
        mimeType = output["mime_type"]?.toString().orEmpty(),
        fallbackText = title,
        metadata = mapOf(
            "user_visible" to "true",
            "size_bytes" to ((output["size_bytes"] as? Number)?.toLong() ?: 0L).toString(),
            "width_px" to ((output["width_px"] as? Number)?.toInt() ?: 0).toString(),
            "height_px" to ((output["height_px"] as? Number)?.toInt() ?: 0).toString(),
            "duration_ms" to ((output["duration_ms"] as? Number)?.toLong() ?: 0L).toString()
        )
    )
    return AgentRichContentCodec.encode(AgentRichContentCodec.fromText(message) + mediaBlock)
}

internal fun MobileNativeAgent.formatBytes(bytes: Long): String {
    val gib = bytes.toDouble() / (1024.0 * 1024.0 * 1024.0)
    return if (gib >= 1.0) String.format(Locale.US, "%.1f GB", gib) else String.format(Locale.US, "%.1f MB", bytes / (1024.0 * 1024.0))
}

internal fun MobileNativeAgent.formatCoordinate(value: Double?): String = value?.let { String.format(Locale.US, "%.6f", it) } ?: "-"

internal fun MobileNativeAgent.audioStreamLabel(stream: String, zh: Boolean): String = when (stream.lowercase(Locale.US)) {
    "music", "media" -> if (zh) "\u5a92\u4f53" else "Media"
    "ring" -> if (zh) "\u94c3\u58f0" else "Ringer"
    "alarm" -> if (zh) "\u95f9\u949f" else "Alarm"
    "notification" -> if (zh) "\u901a\u77e5" else "Notification"
    "voice_call" -> if (zh) "\u901a\u8bdd" else "Call"
    else -> if (zh) "\u7cfb\u7edf" else "System"
}

internal fun MobileNativeAgent.renderAndroidSystemToolValue(value: Any?): String = when (value) {
    null -> "-"
    is Map<*, *> -> value.entries.joinToString(prefix = "{", postfix = "}", limit = 12) {
        "${it.key}: ${renderAndroidSystemToolValue(it.value)}"
    }
    is Iterable<*> -> value.joinToString(prefix = "[", postfix = "]", separator = "; ", limit = 30) {
        renderAndroidSystemToolValue(it)
    }
    else -> value.toString()
}

internal fun MobileNativeAgent.nativeJsonObject(value: String): AgentNativeJsonObject {
    val source = value.ifBlank { "{}" }
    val root = JSONObject(source)
    return root.keys().asSequence().associateWith { key -> nativeJsonValue(root.opt(key)) }
}

internal fun MobileNativeAgent.nativeJsonValue(value: Any?): Any? = when (value) {
    null, JSONObject.NULL -> null
    is JSONObject -> value.keys().asSequence().associateWith { key -> nativeJsonValue(value.opt(key)) }
    is org.json.JSONArray -> (0 until value.length()).map { index -> nativeJsonValue(value.opt(index)) }
    is String, is Boolean, is Number -> value
    else -> value.toString()
}

internal fun MobileNativeAgent.searchKnowledge(query: String, limit: Int = 12): List<AgentKnowledgeHit> =
    knowledgeStore.searchRanked(query, limit)

internal fun MobileNativeAgent.updateKnowledgeSourceAccess(
    itemIds: Set<String>,
    cloudAccess: AgentKnowledgeCloudAccess,
    agentAccess: AgentKnowledgeAgentAccess,
    allowedAgentIds: List<String> = emptyList()
): Int {
    val updated = knowledgeStore.updateAccess(itemIds, cloudAccess, agentAccess, allowedAgentIds)
    if (updated > 0) {
        recordAudit(
            AgentAuditEvent.KNOWLEDGE_ACCESS_UPDATED,
            "items=$updated; cloud=${cloudAccess.name}; agents=${agentAccess.name}"
        )
    }
    return updated
}

internal fun MobileNativeAgent.knowledgeAccessAudit(limit: Int = 20): List<AgentKnowledgeAccessAuditEntry> =
    AgentKnowledgeAccessAuditStore(appContext).recent(limit)

internal fun MobileNativeAgent.attachWorkflowExecution(executionId: String) {
    val cleanId = executionId.trim()
    if (cleanId.isBlank() || workflowExecutionHistoryStore.findById(cleanId) == null) return
    activeWorkflowExecutionId = cleanId
    persistSession()
}

internal fun MobileNativeAgent.observeCurrentScreen(): AgentUiState {
    currentScreen = captureScreen()
    phase = AgentPhase.OBSERVING
    currentGoal = ""
    currentPlan = null
    lastActionResult = null
    recordAudit(AgentAuditEvent.SCREEN_OBSERVED, "screen:${currentScreen.foregroundApp}")
    return snapshot()
}

internal fun MobileNativeAgent.observeCurrentScreen(foregroundApp: String, pageTitle: String): AgentUiState {
    currentScreen = captureScreen(foregroundApp, pageTitle)
    phase = AgentPhase.OBSERVING
    currentGoal = ""
    currentPlan = null
    lastActionResult = null
    recordAudit(AgentAuditEvent.SCREEN_OBSERVED, "screen:${currentScreen.foregroundApp}")
    return snapshot()
}

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

internal fun MobileNativeAgent.applyPlanEdit(result: AgentPlanEditResult): AgentUiState {
    val edited = result.plan
    if (!result.success || edited == null) {
        lastActionResult = AgentActionResult(
            actionId = "agent-plan-edit-rejected",
            success = false,
            message = result.error.ifBlank { "Plan edit was rejected" }
        )
        recordAudit(
            AgentAuditEvent.PLAN_EDIT_REJECTED,
            "reason_hash=${lastActionResult?.message.orEmpty().hashCode()}"
        )
        return snapshot()
    }
    val targets = connectorRegistry.availableTargets()
    val memories = memoryStore.recall(currentGoal)
    val runtimeContext = buildRuntimeContext(
        goal = currentGoal,
        screen = currentScreen,
        targets = targets,
        memories = memories,
        knowledgeItems = knowledgeStore.search(currentGoal),
        knowledgeStats = knowledgeStore.stats()
    )
    val rebuilt = AgentPlanFactory.actions(
        AgentRequest(
            goal = currentGoal,
            screen = currentScreen,
            targets = targets,
            memories = memories,
            runtimeContext = runtimeContext,
            executionHistory = edited.actionHistory,
            replanReason = "user_edited_plan"
        ),
        edited.actions
    )
    var merged = rebuilt.copy(
        planId = edited.planId,
        plannerProfile = edited.plannerProfile,
        revision = edited.revision,
        replanCount = edited.replanCount,
        actionHistory = edited.actionHistory,
        checkpoints = edited.checkpoints,
        verificationResults = edited.verificationResults,
        routeRationale = edited.routeRationale
    )
    merged = merged.copy(validation = AgentPlanValidator.validate(merged))
    merged = AgentActionRiskHardener.enforce(appContext, merged)
    val reviewed = merged.withSafetyReview(safetyPolicy.review(merged, sessionId))
    currentPlan = reviewed
    phase = when {
        reviewed.safetyReview.blocked -> AgentPhase.BLOCKED
        reviewed.actions.any {
            it.status == AgentActionStatus.PENDING_CONFIRMATION || it.status == AgentActionStatus.PROPOSED
        } -> AgentPhase.WAITING_CONFIRMATION
        else -> AgentPhase.COMPLETED
    }
    lastActionResult = AgentActionResult(
        actionId = "agent-plan-edited",
        success = true,
        message = "Plan revision ${reviewed.revision} saved"
    )
    recordAudit(
        AgentAuditEvent.PLAN_EDITED,
        "revision=${reviewed.revision}; actions=${reviewed.actions.size}"
    )
    saveTaskRecord()
    return snapshot()
}

internal fun MobileNativeAgent.replanFromCurrentState(
    plan: AgentPlan,
    reason: String,
    force: Boolean = false
): AgentPlan? {
    val settings = AgentModelPlannerSettingsStore(appContext).load()
    val specializedAdapter = plan.plannerProfile.startsWith("specialized-adapter:")
    val phoneDevelopmentRepair = plan.isPhoneDevelopmentRepairRequest(reason)
    val supervisedProject = plan.isSupervisedProjectPlan()
    if (supervisedProject) {
        val recovered = supervisedProjectRecoveryPlan(plan, reason)
        recovered?.let {
            recordAudit(
                AgentAuditEvent.PLAN_REPLANNED,
                "revision=${it.revision}; reason=${reason.take(120)}; supervised_project=true"
            )
        }
        return recovered
    }
    if (!specializedAdapter && !phoneDevelopmentRepair &&
        (!settings.enabled || (!settings.dynamicReplanning && !force))) return null
    val maxReplans = when {
        phoneDevelopmentRepair -> MAX_PHONE_DEVELOPMENT_REPAIRS
        specializedAdapter -> MAX_SPECIALIZED_ADAPTER_REPLANS
        else -> settings.maxReplans
    }
    if (plan.replanCount >= maxReplans) {
        recordAudit(
            AgentAuditEvent.PLAN_REPLAN_LIMIT_REACHED,
            "revision=${plan.revision}; replans=${plan.replanCount}"
        )
        return null
    }
    if (phoneDevelopmentRepair) {
        recordAudit(
            AgentAuditEvent.REASONING_SUMMARY,
            "summary_key=phone_development_repair"
        )
    }
    val targets = connectorRegistry.availableTargets()
    val memories = memoryStore.recall(currentGoal)
    val knowledgeItems = knowledgeStore.search(currentGoal)
    val runtimeContext = buildRuntimeContext(
        goal = currentGoal,
        screen = currentScreen,
        targets = targets,
        memories = memories,
        knowledgeItems = knowledgeItems,
        knowledgeStats = knowledgeStore.stats()
    )
    val history = plan.historyForReplan()
    val proposal = planner.plan(
        AgentRequest(
            goal = currentGoal,
            screen = currentScreen,
            targets = targets,
            memories = memories,
            runtimeContext = runtimeContext,
            executionHistory = history,
            replanReason = reason
        )
    )
    if (!proposal.plannerProfile.startsWith("guarded-model:") &&
        !proposal.plannerProfile.startsWith("specialized-adapter:") &&
        proposal.plannerProfile != PHONE_DEVELOPMENT_PLANNER_PROFILE) return null
    val revision = plan.revision + 1
    val actionIdMap = proposal.actions.mapIndexed { index, action ->
        action.id to "r$revision-${index + 1}-${action.id}"
    }.toMap()
    val revisedActions = proposal.actions.map { action ->
        action.remapToolGraphIds(
            newId = actionIdMap.getValue(action.id),
            idMap = actionIdMap
        )
    }
    var revised = proposal.copy(
        planId = plan.planId,
        executionMode = plan.executionMode,
        actions = revisedActions,
        revision = revision,
        replanCount = plan.replanCount + 1,
        actionHistory = history,
        checkpoints = plan.checkpoints,
        verificationResults = plan.verificationResults,
        artifactRichOutputJson = plan.artifactRichOutputJson,
        routeRationale = proposal.routeRationale + " Replanned from the latest verified screen state."
    )
    revised = revised.copy(validation = AgentPlanValidator.validate(revised))
    if (!revised.validation.valid) return null
    val reviewed = revised.withSafetyReview(safetyPolicy.review(revised, sessionId))
    recordAudit(
        AgentAuditEvent.PLAN_REPLANNED,
        "revision=$revision; reason=${reason.take(120)}; actions=${revisedActions.size}"
    )
    return reviewed
}

@Synchronized
internal fun MobileNativeAgent.assessLivenessWithModel(reason: String): AgentUiState {
    if (phase in setOf(
            AgentPhase.COMPLETED,
            AgentPhase.FAILED,
            AgentPhase.CANCELLED,
            AgentPhase.BLOCKED
        )
    ) return snapshot()
    val plan = currentPlan ?: return snapshot()
    val actionId = lastActionResult?.actionId
        ?.takeIf(String::isNotBlank)
        ?: plan.actions.lastOrNull { action ->
            action.status in setOf(AgentActionStatus.RUNNING, AgentActionStatus.WAITING_RESPONSE)
        }?.id
        ?: plan.actions.lastOrNull()?.id
        ?: "agent-liveness-assessment"
    val assessmentReason = buildString {
        append("The task stopped reporting progress. Inspect the latest verified evidence and decide whether to ")
        append("continue, retry with corrected arguments, choose another available tool or resource, or finish with ")
        append("the specific unrecoverable cause. Watchdog evidence: ")
        append(reason.trim().ifBlank { "no_progress_observed" })
    }
    val evidence = AgentActionResult(
        actionId = actionId,
        success = false,
        message = assessmentReason,
        metadata = lastActionResult?.metadata.orEmpty() + mapOf(
            "failure_kind" to "liveness_assessment_required",
            "watchdog_reason" to reason,
            "terminal_failure" to "false"
        )
    )
    val observedPlan = if (plan.actions.any { it.id == actionId }) {
        plan.markAction(actionId, AgentActionStatus.FAILED, evidence)
    } else {
        plan.copy(actionHistory = plan.actionHistory)
    }
    lastActionResult = evidence
    val replanned = replanFromCurrentState(
        plan = observedPlan,
        reason = assessmentReason,
        force = true
    ) ?: run {
        recordAudit(
            AgentAuditEvent.INVOCATION_AUDIT,
            "liveness_assessment_waiting_for_model:reason=${reason.take(120)}"
        )
        phase = AgentPhase.WAITING_RESPONSE
        saveTaskRecord()
        return reconcileExecutionLoop(snapshot())
    }
    currentPlan = replanned
    phase = AgentPhase.PLANNING
    recordAudit(
        AgentAuditEvent.PLAN_REPLANNED,
        "liveness_assessment_by_model:revision=${replanned.revision}; reason=${reason.take(120)}"
    )
    if (!advanceExecutionLoop(
            nextPhase = AgentExecutionLoopPhase.REPLAN,
            reason = assessmentReason,
            actionId = replanned.actions.firstOrNull()?.id.orEmpty()
        )
    ) return reconcileExecutionLoop(snapshot())
    saveTaskRecord()
    return reconcileExecutionLoop(executeFirstPendingAction())
}

internal fun MobileNativeAgent.safetySettings(): AgentSafetySettings = safetySettingsStore.load()

internal fun MobileNativeAgent.preferenceMode(): AgentPreferenceMode = activePreferenceMode

internal fun MobileNativeAgent.updatePreferenceMode(mode: AgentPreferenceMode): AgentUiState {
    val profile = AgentPreferenceModePolicy.profile(mode)
    activePreferenceMode = mode
    preferenceModeStore.save(mode)
    safetySettingsStore.save(
        safetySettingsStore.load().copy(
            taskExecutionMode = profile.taskExecutionMode,
            permissionMode = profile.permissionMode,
            highRiskGuard = profile.highRiskGuard
        )
    )
    activeTaskExecutionMode = profile.taskExecutionMode
    recordAudit(AgentAuditEvent.SETTINGS_UPDATED, "preference_mode:${mode.wireValue}")
    return snapshot()
}

internal fun MobileNativeAgent.modelPlannerSettings(): AgentModelPlannerSettings = AgentModelPlannerSettingsStore(appContext).load()

internal fun MobileNativeAgent.updateModelPlannerEnabled(enabled: Boolean): AgentUiState {
    val store = AgentModelPlannerSettingsStore(appContext)
    store.save(store.load().copy(enabled = enabled))
    recordAudit(AgentAuditEvent.SETTINGS_UPDATED, "model_planner_enabled:$enabled")
    return snapshot()
}

internal fun MobileNativeAgent.updateModelPlannerScreenText(enabled: Boolean): AgentUiState {
    val store = AgentModelPlannerSettingsStore(appContext)
    store.save(store.load().copy(shareScreenText = enabled))
    recordAudit(AgentAuditEvent.SETTINGS_UPDATED, "model_planner_share_screen_text:$enabled")
    return snapshot()
}

internal fun MobileNativeAgent.updateModelPlannerMaxActions(maxActions: Int): AgentUiState {
    val store = AgentModelPlannerSettingsStore(appContext)
    store.save(store.load().copy(maxActions = maxActions.coerceIn(1, 12)))
    recordAudit(AgentAuditEvent.SETTINGS_UPDATED, "model_planner_max_actions:${maxActions.coerceIn(1, 12)}")
    return snapshot()
}

internal fun MobileNativeAgent.updateModelPlannerCloudContact(contactId: String): AgentUiState {
    val store = AgentModelPlannerSettingsStore(appContext)
    val normalizedId = contactId.trim().take(120)
    store.save(store.load().copy(cloudContactId = normalizedId))
    recordAudit(
        AgentAuditEvent.SETTINGS_UPDATED,
        "model_planner_cloud_contact:${normalizedId.ifBlank { "automatic" }}"
    )
    return snapshot()
}

internal fun MobileNativeAgent.updateModelPlannerDynamicReplanning(enabled: Boolean): AgentUiState {
    val store = AgentModelPlannerSettingsStore(appContext)
    store.save(store.load().copy(dynamicReplanning = enabled))
    recordAudit(AgentAuditEvent.SETTINGS_UPDATED, "model_planner_dynamic_replanning:$enabled")
    return snapshot()
}

internal fun MobileNativeAgent.updateModelPlannerMaxReplans(maxReplans: Int): AgentUiState {
    val store = AgentModelPlannerSettingsStore(appContext)
    val normalized = maxReplans.coerceIn(1, 5)
    store.save(store.load().copy(maxReplans = normalized))
    recordAudit(AgentAuditEvent.SETTINGS_UPDATED, "model_planner_max_replans:$normalized")
    return snapshot()
}

internal fun MobileNativeAgent.updateMultiAgentCoordination(enabled: Boolean): AgentUiState {
    val store = AgentModelPlannerSettingsStore(appContext)
    store.save(store.load().copy(multiAgentCoordination = enabled))
    recordAudit(AgentAuditEvent.SETTINGS_UPDATED, "multi_agent_coordination:$enabled")
    return snapshot()
}

internal fun MobileNativeAgent.updateShareAgentOutputsWithPlanner(enabled: Boolean): AgentUiState {
    val store = AgentModelPlannerSettingsStore(appContext)
    store.save(store.load().copy(shareAgentOutputsWithPlanner = enabled))
    recordAudit(AgentAuditEvent.SETTINGS_UPDATED, "share_agent_outputs_with_planner:$enabled")
    return snapshot()
}

internal fun MobileNativeAgent.updateMaxAgentHops(maxAgentHops: Int): AgentUiState {
    val store = AgentModelPlannerSettingsStore(appContext)
    val normalized = maxAgentHops.coerceIn(1, 8)
    store.save(store.load().copy(maxAgentHops = normalized))
    recordAudit(AgentAuditEvent.SETTINGS_UPDATED, "max_agent_hops:$normalized")
    return snapshot()
}

internal fun MobileNativeAgent.updateMaxToolCalls(maxToolCalls: Int): AgentUiState {
    val store = AgentModelPlannerSettingsStore(appContext)
    val normalized = maxToolCalls.coerceIn(4, 32)
    store.save(store.load().copy(maxToolCalls = normalized))
    recordAudit(AgentAuditEvent.SETTINGS_UPDATED, "max_tool_calls:$normalized")
    return snapshot()
}

internal fun MobileNativeAgent.updateMaxLoopIterations(maxIterations: Int): AgentUiState {
    val store = AgentModelPlannerSettingsStore(appContext)
    val normalized = maxIterations.coerceIn(1, 24)
    store.save(store.load().copy(maxLoopIterations = normalized))
    recordAudit(AgentAuditEvent.SETTINGS_UPDATED, "max_loop_iterations:$normalized")
    return snapshot()
}

internal fun MobileNativeAgent.updateMaxPhaseRetries(maxRetries: Int): AgentUiState {
    val store = AgentModelPlannerSettingsStore(appContext)
    val normalized = maxRetries.coerceIn(0, 5)
    store.save(store.load().copy(maxPhaseRetries = normalized))
    recordAudit(AgentAuditEvent.SETTINGS_UPDATED, "max_phase_retries:$normalized")
    return snapshot()
}

internal fun MobileNativeAgent.updateNoProgressTimeoutSeconds(timeoutSeconds: Int): AgentUiState {
    val store = AgentModelPlannerSettingsStore(appContext)
    val normalized = timeoutSeconds.coerceIn(60, 3_600)
    store.save(store.load().copy(noProgressTimeoutSeconds = normalized))
    recordAudit(AgentAuditEvent.SETTINGS_UPDATED, "no_progress_timeout_seconds:$normalized")
    return snapshot()
}

internal fun MobileNativeAgent.updatePermissionMode(mode: PermissionMode): AgentUiState {
    safetySettingsStore.save(safetySettingsStore.load().copy(permissionMode = mode))
    recordAudit(AgentAuditEvent.SETTINGS_UPDATED, "permission_mode:${mode.name}")
    return snapshot()
}

internal fun MobileNativeAgent.updateTaskExecutionMode(mode: AgentTaskExecutionMode): AgentUiState {
    safetySettingsStore.save(safetySettingsStore.load().copy(taskExecutionMode = mode))
    activeTaskExecutionMode = mode
    recordAudit(AgentAuditEvent.SETTINGS_UPDATED, "task_execution_mode:${mode.wireValue}")
    return snapshot()
}

internal fun MobileNativeAgent.updateHighRiskGuard(enabled: Boolean): AgentUiState {
    safetySettingsStore.save(safetySettingsStore.load().copy(highRiskGuard = enabled))
    recordAudit(AgentAuditEvent.SETTINGS_UPDATED, "high_risk_guard:$enabled")
    return snapshot()
}

internal fun MobileNativeAgent.memorySnapshot(): AgentMemorySnapshot = memoryStore.snapshot()

internal fun MobileNativeAgent.updateMemoryItem(itemId: String, value: String, key: String = ""): AgentMemoryWriteResult? {
    val reason = sensitiveMemoryReason(value, currentScreen)
    if (reason != null) {
        recordAudit(AgentAuditEvent.MEMORY_SKIPPED, reason)
        return null
    }
    val result = memoryStore.update(itemId, value, key)
    if (result?.conflict != null) {
        recordAudit(
            AgentAuditEvent.MEMORY_CONFLICT_DETECTED,
            "group:${result.conflict.groupId}; candidates:${result.conflict.candidates.size}"
        )
    } else if (result?.item != null) {
        recordAudit(AgentAuditEvent.MEMORY_UPDATED, "item:${result.item.id}; version:${result.item.version}")
    }
    return result
}

internal fun MobileNativeAgent.deleteMemoryItem(itemId: String): Boolean {
    val deleted = memoryStore.deleteById(itemId)
    if (deleted) recordAudit(AgentAuditEvent.MEMORY_FORGOTTEN, "item:$itemId")
    return deleted
}

internal fun MobileNativeAgent.setMemoryItemImportant(itemId: String, important: Boolean): Boolean {
    val updated = memoryStore.setImportant(itemId, important)
    if (updated) recordAudit(AgentAuditEvent.MEMORY_UPDATED, "item:$itemId; important:$important")
    return updated
}

internal fun MobileNativeAgent.resolveMemoryConflict(
    groupId: String,
    selectedItemId: String,
    mergedValue: String? = null
): AgentMemoryItem? {
    if (!mergedValue.isNullOrBlank()) {
        val reason = sensitiveMemoryReason(mergedValue, currentScreen)
        if (reason != null) {
            recordAudit(AgentAuditEvent.MEMORY_SKIPPED, reason)
            return null
        }
    }
    val resolved = memoryStore.resolveConflict(groupId, selectedItemId, mergedValue)
    if (resolved != null) {
        recordAudit(
            AgentAuditEvent.MEMORY_CONFLICT_RESOLVED,
            "group:$groupId; item:${resolved.id}; version:${resolved.version}"
        )
    }
    return resolved
}

internal fun MobileNativeAgent.updateMemoryCapture(enabled: Boolean): AgentUiState {
    safetySettingsStore.save(safetySettingsStore.load().copy(memoryCapture = enabled))
    recordAudit(AgentAuditEvent.SETTINGS_UPDATED, "memory_capture:$enabled")
    return snapshot()
}

internal fun MobileNativeAgent.updateScreenObservationAllowed(enabled: Boolean): AgentUiState {
    safetySettingsStore.save(safetySettingsStore.load().copy(screenObservationAllowed = enabled))
    currentScreen = captureScreen()
    recordAudit(AgentAuditEvent.SETTINGS_UPDATED, "screen_observation_allowed:$enabled")
    return snapshot()
}

internal fun MobileNativeAgent.updateLocalActionsAllowed(enabled: Boolean): AgentUiState {
    safetySettingsStore.save(safetySettingsStore.load().copy(localActionsAllowed = enabled))
    recordAudit(AgentAuditEvent.SETTINGS_UPDATED, "local_actions_allowed:$enabled")
    return snapshot()
}

internal fun MobileNativeAgent.updateConnectorCallsAllowed(enabled: Boolean): AgentUiState {
    safetySettingsStore.save(safetySettingsStore.load().copy(connectorCallsAllowed = enabled))
    recordAudit(AgentAuditEvent.SETTINGS_UPDATED, "connector_calls_allowed:$enabled")
    return snapshot()
}

internal fun MobileNativeAgent.updateDeviceControlAllowed(enabled: Boolean): AgentUiState {
    safetySettingsStore.save(safetySettingsStore.load().copy(deviceControlAllowed = enabled))
    recordAudit(AgentAuditEvent.SETTINGS_UPDATED, "device_control_allowed:$enabled")
    return snapshot()
}

internal fun MobileNativeAgent.updateExecutionPaused(enabled: Boolean): AgentUiState {
    safetySettingsStore.save(safetySettingsStore.load().copy(executionPaused = enabled))
    if (enabled && currentPlan != null && phase in ACTIVE_EXECUTION_PHASES) {
        phase = AgentPhase.PAUSED
        lastActionResult = AgentActionResult(
            actionId = "agent-emergency-pause",
            success = true,
            message = "All Agent execution paused"
        )
    }
    recordAudit(AgentAuditEvent.SETTINGS_UPDATED, "execution_paused:$enabled")
    persistSession()
    return snapshot()
}

internal fun MobileNativeAgent.recordKnowledgeImport(result: AgentKnowledgeImportResult): AgentUiState {
    currentGoal = "Import knowledge document ${result.title}"
    currentScreen = captureScreen()
    val status = if (result.success) AgentActionStatus.COMPLETED else AgentActionStatus.FAILED
    val action = AgentAction(
        id = "import-knowledge-document",
        kind = AgentActionKind.DRAFT_PLAN,
        target = "Agent Knowledge",
        risk = AgentRisk.LOW,
        status = status,
        description = "Import document into Agent knowledge",
        parameters = mapOf(
            "mime_type" to result.mimeType,
            "byte_count" to result.byteCount.toString(),
            "character_count" to result.characterCount.toString(),
            "chunk_count" to result.chunkCount.toString(),
            "truncated" to result.truncated.toString()
        ),
        result = result.message
    )
    currentPlan = AgentPlan(
        goal = currentGoal,
        screen = currentScreen,
        steps = completedSteps(),
        actions = listOf(action),
        selectedAgentOrModel = "Agent Knowledge",
        confirmationRequired = false,
        expectedResult = result.message,
        route = AgentRoute(
            routeId = "agent-knowledge-import",
            kind = AgentRouteKind.KNOWLEDGE,
            targetId = "agent-knowledge-import",
            targetTitle = "Agent Knowledge",
            status = AgentConnectorStatus.AVAILABLE,
            deliveryMode = "local",
            capabilities = listOf(AgentCapability.KNOWLEDGE_SEARCH)
        ),
        safetyReview = AgentSafetyReview(
            risk = AgentRisk.LOW,
            requiresConfirmation = false,
            mode = safetyPolicy.permissionMode(),
            warnings = result.sensitiveFlags.map { "sensitive_import:$it" }
        )
    )
    phase = if (result.success) AgentPhase.COMPLETED else AgentPhase.FAILED
    lastActionResult = AgentActionResult(action.id, result.success, result.message)
    recordAudit(
        AgentAuditEvent.KNOWLEDGE_IMPORTED,
        "success=${result.success}; title_hash=${result.title.hashCode()}; chunks=${result.chunkCount}; sensitive=${result.sensitiveFlags.joinToString("|").ifBlank { "none" }}"
    )
    recordAudit(AgentAuditEvent.ACTION_EXECUTED, "action:${action.kind}:$status")
    return snapshot()
}

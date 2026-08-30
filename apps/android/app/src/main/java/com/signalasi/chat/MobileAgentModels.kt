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

private const val MAX_ACTION_EVIDENCE_CHARACTERS = 12_000

data class AgentUiState(
    val phase: AgentPhase,
    val currentGoal: String,
    val currentScreen: ScreenContext,
    val taskExecutionMode: AgentTaskExecutionMode = AgentTaskExecutionMode.AUTO_COMPLETE,
    val permissionMode: PermissionMode,
    val highRiskGuard: Boolean,
    val callableTargets: List<AgentCallableTarget>,
    val runtimeContext: AgentRuntimeContext,
    val runningTaskCount: Int,
    val steps: List<AgentStep>,
    val lastEvent: AgentEvent,
    val sessionId: String,
    val plan: AgentPlan? = null,
    val pendingAction: AgentAction? = null,
    val auditTrail: List<AgentAuditEntry> = emptyList(),
    val lastActionResult: AgentActionResult? = null,
    val recentTasks: List<AgentTaskRecord> = emptyList(),
    val executionLoop: AgentExecutionLoopSnapshot? = null
)

data class AgentSessionSnapshot(
    val sessionId: String,
    val phase: AgentPhase,
    val currentGoal: String,
    val currentScreen: ScreenContext,
    val currentPlan: AgentPlan?,
    val auditTrail: List<AgentAuditEntry>,
    val lastActionResult: AgentActionResult?,
    val activeWorkflowExecutionId: String = "",
    val taskExecutionMode: AgentTaskExecutionMode = AgentTaskExecutionMode.AUTO_COMPLETE,
    val executionLoopSnapshot: AgentExecutionLoopSnapshot? = null,
    val processInstanceId: String = "",
    val updatedAtMillis: Long
)

data class AgentRequest(
    val goal: String,
    val screen: ScreenContext,
    val targets: List<AgentCallableTarget>,
    val registrations: List<AgentRegistration>? = null,
    val requestedMembers: List<AgentRequestedMember> = emptyList(),
    val memories: List<AgentMemoryItem>,
    val runtimeContext: AgentRuntimeContext,
    val conversationContext: AgentConversationContext = AgentConversationContext("", "", emptyList(), false),
    val executionHistory: List<AgentAction> = emptyList(),
    val replanReason: String = ""
)

data class AgentCallableTarget(
    val id: String,
    val title: String,
    val kind: AgentConnectorKind,
    val status: AgentConnectorStatus,
    val capabilities: List<AgentCapability>,
    val failureDomain: String = "",
    val runtimeFailureDomain: String = "",
    val adapterType: String = "",
    val independentlyUpgradeable: Boolean = true,
    val desktopAccessProfile: String = "",
    val providerProfile: ProviderProfile? = null,
    val invocationProfile: AgentInvocationProfile = AgentInvocationProfile()
)

data class ScreenContext(
    val foregroundApp: String,
    val activityName: String = "",
    val pageTitle: String,
    val visibleTextCount: Int = 0,
    val clickableNodeCount: Int = 0,
    val inputFieldCount: Int = 0,
    val scrollableRegionCount: Int = 0,
    val sensitiveFlagCount: Int = 0,
    val visibleTexts: List<String> = emptyList(),
    val selectedText: String = "",
    val focusedInputField: ScreenElement? = null,
    val clickableElements: List<ScreenElement> = emptyList(),
    val inputFields: List<ScreenElement> = emptyList(),
    val scrollableRegions: List<ScreenElement> = emptyList(),
    val sensitiveFlags: List<String> = emptyList(),
    val visualScene: AgentVisualScene = AgentVisualScene(),
    val clipboard: ClipboardContext = ClipboardContext(),
    val notifications: AgentNotificationContext = AgentNotificationContext(),
    val installedApps: List<InstalledAppInfo> = emptyList(),
    val deviceStatus: AgentDeviceStatusContext = AgentDeviceStatusContext(),
    val isAccessibilityEnabled: Boolean = false,
    val snapshotAgeMillis: Long = 0L
)

data class InstalledAppInfo(
    val label: String = "",
    val packageName: String = ""
)

data class AgentDeviceStatusContext(
    val batteryPercent: Int = -1,
    val charging: Boolean = false,
    val powerSaveMode: Boolean = false,
    val network: String = "unknown",
    val freeStorageMb: Long = 0L,
    val totalStorageMb: Long = 0L
)

data class ClipboardContext(
    val hasText: Boolean = false,
    val textLength: Int = 0,
    val textHash: String = "",
    val preview: String = "",
    val sensitiveFlags: List<String> = emptyList()
)

internal fun AgentAction.requiresSpecializedContinuation(): Boolean {
    if (!id.contains("special-wechat-")) return false
    return !id.contains("-send") &&
        !id.contains("-notification-reply") &&
        !id.contains("-missing")
}

internal fun AgentActionKind.mayChangeScreen(): Boolean = when (this) {
    AgentActionKind.TAP,
    AgentActionKind.SWIPE,
    AgentActionKind.LONG_PRESS,
    AgentActionKind.BACK,
    AgentActionKind.HOME,
    AgentActionKind.RECENTS,
    AgentActionKind.LOCK_SCREEN,
    AgentActionKind.OPEN_APP,
    AgentActionKind.OPEN_URL,
    AgentActionKind.SET_ALARM,
    AgentActionKind.TYPE_TEXT,
    AgentActionKind.DELETE_TEXT,
    AgentActionKind.PASTE_TEXT -> true
    AgentActionKind.READ_SCREEN,
    AgentActionKind.SAVE_SCREEN_KNOWLEDGE,
    AgentActionKind.DRAFT_PLAN,
    AgentActionKind.COPY_SCREEN_TEXT,
    AgentActionKind.CREATE_NOTIFICATION,
    AgentActionKind.REPLY_NOTIFICATION,
    AgentActionKind.IMPORT_WEB_KNOWLEDGE,
    AgentActionKind.CALL_NATIVE_TOOL,
    AgentActionKind.CALL_CONNECTOR,
    AgentActionKind.CONTROL_DEVICE -> false
}

internal fun AgentActionKind.requiresScreenObservation(): Boolean = when (this) {
    AgentActionKind.READ_SCREEN,
    AgentActionKind.SAVE_SCREEN_KNOWLEDGE,
    AgentActionKind.TAP,
    AgentActionKind.TYPE_TEXT,
    AgentActionKind.SWIPE,
    AgentActionKind.LONG_PRESS,
    AgentActionKind.BACK,
    AgentActionKind.HOME,
    AgentActionKind.RECENTS,
    AgentActionKind.LOCK_SCREEN,
    AgentActionKind.OPEN_APP,
    AgentActionKind.OPEN_URL,
    AgentActionKind.SET_ALARM,
    AgentActionKind.COPY_SCREEN_TEXT,
    AgentActionKind.DELETE_TEXT,
    AgentActionKind.PASTE_TEXT -> true
    AgentActionKind.DRAFT_PLAN,
    AgentActionKind.CREATE_NOTIFICATION,
    AgentActionKind.REPLY_NOTIFICATION,
    AgentActionKind.IMPORT_WEB_KNOWLEDGE,
    AgentActionKind.CALL_NATIVE_TOOL,
    AgentActionKind.CALL_CONNECTOR,
    AgentActionKind.CONTROL_DEVICE -> false
}

internal fun AgentActionKind.isLocalExecutionAction(): Boolean = when (this) {
    AgentActionKind.TAP,
    AgentActionKind.TYPE_TEXT,
    AgentActionKind.SWIPE,
    AgentActionKind.LONG_PRESS,
    AgentActionKind.BACK,
    AgentActionKind.HOME,
    AgentActionKind.RECENTS,
    AgentActionKind.LOCK_SCREEN,
    AgentActionKind.OPEN_APP,
    AgentActionKind.OPEN_URL,
    AgentActionKind.SET_ALARM,
    AgentActionKind.CREATE_NOTIFICATION,
    AgentActionKind.REPLY_NOTIFICATION,
    AgentActionKind.COPY_SCREEN_TEXT,
    AgentActionKind.DELETE_TEXT,
    AgentActionKind.PASTE_TEXT -> true
    AgentActionKind.CALL_NATIVE_TOOL -> true
    AgentActionKind.READ_SCREEN,
    AgentActionKind.SAVE_SCREEN_KNOWLEDGE,
    AgentActionKind.DRAFT_PLAN,
    AgentActionKind.IMPORT_WEB_KNOWLEDGE,
    AgentActionKind.CALL_CONNECTOR,
    AgentActionKind.CONTROL_DEVICE -> false
}

internal fun AgentActionKind.writesAgentKnowledge(): Boolean =
    this == AgentActionKind.SAVE_SCREEN_KNOWLEDGE || this == AgentActionKind.IMPORT_WEB_KNOWLEDGE

data class AgentPlan(
    val goal: String,
    val screen: ScreenContext,
    val steps: List<AgentStep>,
    val actions: List<AgentAction>,
    val executionMode: AgentTaskExecutionMode = AgentTaskExecutionMode.AUTO_COMPLETE,
    val planId: String = UUID.randomUUID().toString(),
    val selectedAgentOrModel: String = actions.firstOrNull()?.target.orEmpty(),
    val requiredPermissions: List<AgentPermissionRequirement> = emptyList(),
    val confirmationRequired: Boolean = true,
    val rollbackStrategy: String = "Stop execution and ask the user before retrying.",
    val expectedResult: String = actions.firstOrNull()?.description.orEmpty(),
    val timeoutSeconds: Int = 60,
    val plannerProfile: String = "rule-based-local",
    val contextDigest: String = "",
    val routeRationale: String = "",
    val route: AgentRoute = AgentRoute(),
    val validation: AgentPlanValidation = AgentPlanValidation(),
    val verificationResults: List<AgentVerificationResult> = emptyList(),
    val safetyReview: AgentSafetyReview = AgentSafetyReview(),
    val revision: Int = 1,
    val replanCount: Int = 0,
    val actionHistory: List<AgentAction> = emptyList(),
    val checkpoints: List<AgentExecutionCheckpoint> = emptyList(),
    val artifactRichOutputJson: String = ""
) {
    fun withSafetyReview(review: AgentSafetyReview): AgentPlan {
        val reviewedActions = if (review.blocked) {
            actions.map { action ->
                if (action.status == AgentActionStatus.PENDING_CONFIRMATION) {
                    action.copy(status = AgentActionStatus.BLOCKED, result = review.reason)
                } else {
                    action
                }
            }
        } else {
            actions
        }
        val next = copy(
            actions = reviewedActions,
            safetyReview = review,
            confirmationRequired = review.requiresConfirmation
        )
        return next.copy(validation = AgentPlanValidator.validate(next))
    }

    fun markAction(
        actionId: String,
        status: AgentActionStatus,
        result: AgentActionResult? = null
    ): AgentPlan {
        val nextActions = actions.map { action ->
            if (action.id == actionId) {
                action.copy(
                    status = status,
                    result = result?.message ?: action.result,
                    evidence = result?.let { actionResult ->
                        actionResult.metadata["native_tool_output"]
                            .orEmpty()
                            .take(MAX_ACTION_EVIDENCE_CHARACTERS)
                            .ifBlank { if (actionResult.success) "executor_success" else "executor_failure" }
                    } ?: action.evidence
                )
            } else {
                action
            }
        }
        val hasPendingAction = nextActions.any { it.status == AgentActionStatus.PENDING_CONFIRMATION }
        return copy(
            actions = nextActions,
            steps = steps.map { step ->
                when {
                    status == AgentActionStatus.COMPLETED && step.kind == AgentStepKind.CONFIRM_AND_ACT -> {
                        step.copy(status = if (hasPendingAction) AgentStepStatus.CURRENT else AgentStepStatus.DONE)
                    }
                    status == AgentActionStatus.FAILED && step.kind == AgentStepKind.CONFIRM_AND_ACT -> {
                        step.copy(status = AgentStepStatus.CURRENT)
                    }
                    status == AgentActionStatus.WAITING_RESPONSE && step.kind == AgentStepKind.CONFIRM_AND_ACT -> {
                        step.copy(status = AgentStepStatus.CURRENT)
                    }
                    step.kind == AgentStepKind.ANALYZE_GOAL || step.kind == AgentStepKind.BUILD_PLAN -> {
                        step.copy(status = AgentStepStatus.DONE)
                    }
                    step.kind == AgentStepKind.CONFIRM_AND_ACT && status == AgentActionStatus.RUNNING -> {
                        step.copy(status = AgentStepStatus.CURRENT)
                    }
                    else -> step
                }
            }
        )
    }

    fun resetActionForRetry(actionId: String): AgentPlan = copy(
        actions = actions.map { action ->
            if (action.id == actionId) {
                action.rekeyAgentTeamForRetry().copy(
                    status = AgentActionStatus.PENDING_CONFIRMATION,
                    result = "",
                    evidence = ""
                )
            } else {
                action
            }
        },
        verificationResults = verificationResults.filterNot { it.actionId == actionId },
        steps = steps.map { step ->
            if (step.kind == AgentStepKind.CONFIRM_AND_ACT) {
                step.copy(status = AgentStepStatus.CURRENT)
            } else {
                step
            }
        }
    )

    fun addVerification(result: AgentVerificationResult): AgentPlan = copy(
        verificationResults = verificationResults
            .filterNot { it.actionId == result.actionId }
            .plus(result)
    )

    fun addArtifactRichOutput(value: String): AgentPlan = copy(
        artifactRichOutputJson = AgentRuntimeArtifactUi.mergeArtifactOutputs(
            artifactRichOutputJson,
            value
        )
    )
}

data class AgentStep(
    val order: Int,
    val kind: AgentStepKind,
    val status: AgentStepStatus
)

data class AgentRoute(
    val routeId: String = "",
    val kind: AgentRouteKind = AgentRouteKind.UNKNOWN,
    val targetId: String = "",
    val targetTitle: String = "",
    val status: AgentConnectorStatus = AgentConnectorStatus.DISCONNECTED,
    val deliveryMode: String = "",
    val capabilities: List<AgentCapability> = emptyList(),
    val executionLocationKind: AgentExecutionLocationKind = AgentExecutionLocationKind.UNKNOWN,
    val executionRuntimeKind: AgentExecutionRuntimeKind = AgentExecutionRuntimeKind.UNKNOWN,
    val executionDeviceId: String = "",
    val executionDeviceName: String = ""
)

data class AgentAction(
    val id: String,
    val kind: AgentActionKind,
    val target: String,
    val risk: AgentRisk,
    val status: AgentActionStatus,
    val description: String,
    val parameters: Map<String, String> = emptyMap(),
    val requiresConfirmation: Boolean = true,
    val result: String = "",
    val evidence: String = ""
)

data class AgentPermissionRequirement(
    val id: String,
    val title: String,
    val required: Boolean = true,
    val granted: Boolean = false
)

data class AgentPlanValidation(
    val valid: Boolean = true,
    val issues: List<String> = emptyList()
)

data class AgentSafetyReview(
    val risk: AgentRisk = AgentRisk.LOW,
    val requiresConfirmation: Boolean = true,
    val blocked: Boolean = false,
    val mode: PermissionMode = PermissionMode.ASK_BEFORE_ACTION,
    val deniedPermissions: List<String> = emptyList(),
    val warnings: List<String> = emptyList(),
    val reason: String = ""
)

data class AgentActionResult(
    val actionId: String,
    val success: Boolean,
    val message: String,
    val metadata: Map<String, String> = emptyMap()
)

enum class AgentConnectorTimeoutStage {
    NOT_ACCEPTED,
    NOT_RUNNING,
    READ_ONLY_STALE
}

data class AgentVerificationResult(
    val actionId: String,
    val success: Boolean,
    val observedApp: String,
    val observedTitle: String,
    val visibleTextCount: Int,
    val clickableNodeCount: Int,
    val evidence: String,
    val observationDecision: AgentObservationDecision = AgentObservationDecision.NO_CHANGE_REQUIRED,
    val observationSampleCount: Int = 1,
    val observationDurationMillis: Long = 0L,
    val screenChanged: Boolean = false,
    val screenStable: Boolean = true,
    val recoveryDecision: AgentRecoveryDecision = AgentRecoveryDecision.NOT_NEEDED,
    val recoveryAttemptCount: Int = 0,
    val timestampMillis: Long = System.currentTimeMillis()
) {
    companion object {
        fun from(
            actionId: String,
            actionResult: AgentActionResult?,
            recovery: AgentRecoveryOutcome
        ): AgentVerificationResult = AgentVerificationResult(
            actionId = actionId,
            success = actionResult?.success == true,
            observedApp = recovery.observation.screen.foregroundApp,
            observedTitle = recovery.observation.screen.pageTitle,
            visibleTextCount = recovery.observation.screen.visibleTextCount,
            clickableNodeCount = recovery.observation.screen.clickableNodeCount,
            evidence = actionResult?.message.orEmpty(),
            observationDecision = recovery.observation.decision,
            observationSampleCount = recovery.observation.sampleCount,
            observationDurationMillis = recovery.observation.durationMillis,
            screenChanged = recovery.observation.screenChanged,
            screenStable = recovery.observation.screenStable,
            recoveryDecision = recovery.decision,
            recoveryAttemptCount = recovery.attemptCount
        )
    }
}

data class AgentMemoryItem(
    val kind: AgentMemoryKind,
    val value: String,
    val timestampMillis: Long = System.currentTimeMillis(),
    val id: String = UUID.randomUUID().toString(),
    val source: String = "agent",
    val key: String = "",
    val version: Int = 1,
    val supersedesId: String = "",
    val important: Boolean = false,
    val status: AgentMemoryStatus = AgentMemoryStatus.ACTIVE,
    val conflictGroupId: String = "",
    val scope: AgentMemoryScope = AgentMemoryScope.GLOBAL,
    val scopeId: String = "",
    val confidence: Double = 0.65,
    val evidenceCount: Int = 1,
    val autoLearned: Boolean = false,
    val lastConfirmedAtMillis: Long = 0L,
    val lastAccessedAtMillis: Long = 0L,
    val expiresAtMillis: Long = 0L
) {
    fun isExpired(nowMillis: Long = System.currentTimeMillis()): Boolean =
        expiresAtMillis > 0L && expiresAtMillis <= nowMillis
}

data class AgentMemoryWriteResult(
    val item: AgentMemoryItem?,
    val conflict: AgentMemoryConflict? = null,
    val duplicate: Boolean = false
)

data class AgentMemoryConflict(
    val groupId: String,
    val kind: AgentMemoryKind,
    val key: String,
    val candidates: List<AgentMemoryItem>
)

data class AgentMemorySnapshot(
    val activeItems: List<AgentMemoryItem> = emptyList(),
    val conflicts: List<AgentMemoryConflict> = emptyList(),
    val historyItems: List<AgentMemoryItem> = emptyList()
) {
    val activeCount: Int get() = activeItems.size
    val historyCount: Int get() = historyItems.size
}

data class AgentAuditEntry(
    val event: AgentAuditEvent,
    val detail: String,
    val timestampMillis: Long
)

enum class AgentPhase {
    OBSERVING,
    PLANNING,
    WAITING_CONFIRMATION,
    EXECUTING,
    VERIFYING,
    WAITING_RESPONSE,
    PAUSED,
    CANCELLED,
    BLOCKED,
    COMPLETED,
    FAILED
}

enum class AgentStepKind {
    OBSERVE_SCREEN,
    ANALYZE_GOAL,
    BUILD_PLAN,
    CONFIRM_AND_ACT
}

enum class AgentStepStatus {
    CURRENT,
    DONE,
    WAITING,
    SAFE
}

enum class AgentActionKind {
    READ_SCREEN,
    SAVE_SCREEN_KNOWLEDGE,
    DRAFT_PLAN,
    TAP,
    TYPE_TEXT,
    SWIPE,
    LONG_PRESS,
    BACK,
    HOME,
    RECENTS,
    LOCK_SCREEN,
    OPEN_APP,
    OPEN_URL,
    SET_ALARM,
    CREATE_NOTIFICATION,
    REPLY_NOTIFICATION,
    IMPORT_WEB_KNOWLEDGE,
    COPY_SCREEN_TEXT,
    DELETE_TEXT,
    PASTE_TEXT,
    CALL_CONNECTOR,
    CALL_NATIVE_TOOL,
    CONTROL_DEVICE
}

enum class AgentActionStatus {
    PROPOSED,
    PENDING_CONFIRMATION,
    RUNNING,
    WAITING_RESPONSE,
    COMPLETED,
    FAILED,
    BLOCKED,
    ROLLED_BACK
}

enum class AgentRisk(val weight: Int) {
    LOW(1),
    MEDIUM(2),
    HIGH(3),
    BLOCKED(4)
}

enum class AgentMemoryKind {
    IDENTITY,
    CONTACT,
    TASK,
    PREFERENCE,
    WORKFLOW,
    KNOWLEDGE,
    SAFETY
}

enum class AgentMemoryScope {
    GLOBAL,
    CONVERSATION,
    APPLICATION,
    CONTACT,
    WORKSPACE,
    DEVICE
}

enum class AgentMemoryStatus {
    ACTIVE,
    CONFLICTED,
    SUPERSEDED
}

enum class AgentConnectorKind {
    MODEL,
    AGENT,
    DEVICE,
    KNOWLEDGE
}

internal enum class CallableInventoryFilter {
    ALL,
    TOOLS,
    AGENTS,
    MODELS,
    DEVICES
}

internal data class AgentPermissionChecklistItem(
    val title: String,
    val ready: Boolean,
    val required: Boolean,
    val fixCommand: String
)

internal data class WorkflowScheduleRequest(
    val workflowName: String,
    val kind: AgentWorkflowScheduleKind,
    val hour: Int = -1,
    val minute: Int = -1,
    val intervalMinutes: Int = 0
)

internal data class WorkflowTriggerRequest(
    val workflowName: String,
    val kind: AgentWorkflowTriggerKind,
    val condition: String = ""
)

internal data class WorkflowTriggerConditionRequest(
    val triggerId: String,
    val condition: AgentWorkflowCondition
)

enum class AgentConnectorStatus {
    AVAILABLE,
    NEEDS_SETUP,
    DISCONNECTED
}

enum class AgentRouteKind {
    LOCAL_SYSTEM,
    CLOUD_MODEL,
    LOCAL_MODEL,
    DESKTOP_AGENT,
    DEVICE_CONNECTOR,
    KNOWLEDGE,
    UNKNOWN
}

enum class AgentCapability {
    CHAT,
    REASONING,
    LIVE_DATA,
    TOOL_USE,
    MCP,
    SKILL,
    LOCAL_INFERENCE,
    RESEARCH,
    CODE,
    TASK_EXECUTION,
    SMART_HOME,
    DEVICE_CONTROL,
    KNOWLEDGE_SEARCH,
    SCREEN_READING,
    CLIPBOARD,
    SYSTEM_SETTINGS,
    APP_NAVIGATION,
    ALARM
}

enum class AgentAuditEvent {
    SCREEN_OBSERVED,
    SCREEN_VERIFIED,
    CHECKPOINT_SAVED,
    CHECKPOINT_RESTORED,
    CHECKPOINT_RESTORE_FAILED,
    PLAN_REPLANNED,
    PLAN_REPLAN_LIMIT_REACHED,
    PLAN_EDITED,
    PLAN_EDIT_REJECTED,
    REASONING_SUMMARY,
    TOOL_STARTED,
    TOOL_COMPLETED,
    TOOL_OUTPUT_HANDOFF,
    TOOL_GRAPH_BLOCKED,
    AUTONOMY_GUARD_BLOCKED,
    ACTION_RECOVERY_STARTED,
    ACTION_RECOVERY_COMPLETED,
    ACTION_RECOVERY_MANUAL_REQUIRED,
    GOAL_RECEIVED,
    INVOCATION_AUDIT,
    CONNECTOR_RESPONSE_RECEIVED,
    RESPONSE_SELF_CHECK_PASSED,
    RESPONSE_SELF_CHECK_FAILED,
    MEMORY_SKIPPED,
    MEMORY_FORGOTTEN,
    MEMORY_UPDATED,
    MEMORY_CONFLICT_DETECTED,
    MEMORY_CONFLICT_RESOLVED,
    KNOWLEDGE_IMPORTED,
    KNOWLEDGE_ACCESSED,
    KNOWLEDGE_ACCESS_UPDATED,
    WORKFLOW_UPDATED,
    WORKFLOW_RUN,
    ACTION_EXECUTED,
    ACTION_BLOCKED,
    TASK_CANCELLED,
    TASK_PAUSED,
    TASK_RESUMED,
    TASK_INTERRUPTED,
    SETTINGS_UPDATED
}

enum class AgentEvent {
    WAITING_FOR_GOAL,
    GOAL_RECEIVED
}

enum class PermissionMode {
    OBSERVE_ONLY,
    SUGGEST_ONLY,
    ASK_BEFORE_ACTION,
    AUTO_LOW_RISK,
    FULL_ACCESS
}

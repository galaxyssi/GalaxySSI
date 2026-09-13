package com.galaxyssi.chat

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.util.Log
import androidx.work.BackoffPolicy
import androidx.work.CoroutineWorker
import androidx.work.ExistingWorkPolicy
import androidx.work.ForegroundInfo
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.Operation
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import androidx.work.workDataOf
import org.json.JSONArray
import org.json.JSONObject
import java.io.Closeable
import java.util.Locale
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CancellationException

internal enum class AgentLongTaskRecoveryMode {
    TRANSCRIPT_PROJECTION,
    INITIAL_PLANNING,
    REPLANNING,
    INTERRUPTED_EXECUTION,
    LIVENESS_ASSESSMENT
}

internal data class AgentLongTaskRecoveryDecision(
    val mode: AgentLongTaskRecoveryMode,
    val reason: String
)

internal object AgentLongTaskRecoveryClaims {
    private val claimedWorkspaceIds = ConcurrentHashMap.newKeySet<String>()

    fun tryAcquire(workspaceId: String): Closeable? {
        val cleanWorkspaceId = workspaceId.trim()
        if (cleanWorkspaceId.isBlank() || !claimedWorkspaceIds.add(cleanWorkspaceId)) return null
        return Closeable { claimedWorkspaceIds.remove(cleanWorkspaceId) }
    }
}

/** Selects only work that can be resumed from durable evidence without replaying a mutation. */
internal object AgentLongTaskRecoveryPolicy {
    fun decide(
        workspace: AgentWorkspace,
        session: AgentSessionSnapshot?,
        activeWorkspaceIds: Set<String> = emptySet()
    ): AgentLongTaskRecoveryDecision? {
        if (workspace.workspaceId !in activeWorkspaceIds && session != null &&
            AgentRecoveryTranscript.needsProjection(workspace, session)) {
            return AgentLongTaskRecoveryDecision(AgentLongTaskRecoveryMode.TRANSCRIPT_PROJECTION,
                "Commit the saved result to its original conversation without executing tools")
        }
        if (workspace.workspaceId in activeWorkspaceIds || workspace.status.isTerminal ||
            workspace.cancellationRequested || session == null ||
            session.phase in setOf(AgentPhase.COMPLETED, AgentPhase.CANCELLED, AgentPhase.FAILED) ||
            session.lastActionResult?.actionId == "agent-paused"
        ) {
            return null
        }
        if (AgentReplanningRecoveryPolicy.belongsTo(workspace, session) &&
            (session.lastActionResult?.actionId == "agent-interrupted" || AgentSessionInterruptionPolicy.wasInterrupted(session))) {
            return AgentLongTaskRecoveryDecision(AgentLongTaskRecoveryMode.REPLANNING,
                "Resume the original plan revision, reason and committed model observations")
        }
        if (session.pendingPlanning?.isReplanning == true) return null
        if (AgentInitialPlanningRecoveryPolicy.belongsTo(workspace, session) &&
            (session.lastActionResult?.actionId == "agent-interrupted" || AgentSessionInterruptionPolicy.wasInterrupted(session))) {
            return AgentLongTaskRecoveryDecision(AgentLongTaskRecoveryMode.INITIAL_PLANNING,
                "Resume the original planning input and committed model observations")
        }
        if (session.currentPlan == null) return null
        val pendingAssessment = AgentTaskLivenessPolicy().hasPendingAssessment(workspace)
        if (pendingAssessment) {
            val reason = workspace.eventJournal.asReversed()
                .firstOrNull { it.kind == AgentTaskEventKinds.LIVENESS_ASSESSMENT_REQUESTED }
                ?.message
                .orEmpty()
                .ifBlank { "The task stopped reporting progress" }
            return AgentLongTaskRecoveryDecision(
                AgentLongTaskRecoveryMode.LIVENESS_ASSESSMENT,
                reason
            )
        }
        val interrupted = session.lastActionResult?.actionId == "agent-interrupted" ||
            AgentSessionInterruptionPolicy.wasInterrupted(session) ||
            session.currentPlan.hasInterruptedExecutionEvidence()
        if (!interrupted || workspace.status !in setOf(
                AgentWorkspaceStatus.CREATED,
                AgentWorkspaceStatus.QUEUED,
                AgentWorkspaceStatus.RUNNING,
                AgentWorkspaceStatus.PAUSED
            )
        ) {
            return null
        }
        return AgentLongTaskRecoveryDecision(
            AgentLongTaskRecoveryMode.INTERRUPTED_EXECUTION,
            "The app process ended before the active action produced a verified outcome"
        )
    }
}

/** Event-driven durable wake-up for interrupted or stalled Agent work. */
internal object AgentLongTaskRecoveryScheduler {
    fun enqueueRecoverable(context: Context, reason: String) {
        val appContext = context.applicationContext
        val supervisor = AgentTaskRuntime.supervisor(appContext)
        val activeIds = supervisor.activeWorkspaces().mapTo(linkedSetOf(), AgentWorkspace::workspaceId)
        supervisor.recoverableTasks().forEach { workspace ->
            val session = SharedPreferencesAgentSessionStore(
                appContext,
                "task:${workspace.workspaceId}"
            ).load()
            if (AgentLongTaskRecoveryPolicy.decide(workspace, session, activeIds) != null) {
                enqueue(appContext, workspace.workspaceId, reason)?.result?.get()
            }
        }
    }

    fun enqueue(context: Context, workspaceId: String, reason: String): Operation? {
        val cleanWorkspaceId = workspaceId.trim()
        if (cleanWorkspaceId.isBlank()) return null
        val request = OneTimeWorkRequestBuilder<AgentLongTaskRecoveryWorker>()
            .setInputData(
                workDataOf(
                    KEY_WORKSPACE_ID to cleanWorkspaceId,
                    KEY_REASON to reason.trim().take(240)
                )
            )
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30L, TimeUnit.SECONDS)
            .addTag(WORK_TAG)
            .build()
        return WorkManager.getInstance(context.applicationContext).enqueueUniqueWork(
            uniqueWorkName(cleanWorkspaceId),
            ExistingWorkPolicy.KEEP,
            request
        )
    }

    internal fun uniqueWorkName(workspaceId: String): String =
        "$WORK_NAME_PREFIX${AgentNativeJsonCodec.sha256(workspaceId)}"

    internal const val KEY_WORKSPACE_ID = "workspace_id"
    internal const val KEY_REASON = "reason"
    private const val WORK_TAG = "galaxyssi-agent-long-task-recovery"
    private const val WORK_NAME_PREFIX = "galaxyssi-agent-recovery-v1-"
}

class AgentLongTaskRecoveryWorker(
    appContext: Context,
    params: WorkerParameters
) : CoroutineWorker(appContext, params) {
    override suspend fun doWork(): Result {
        val workspaceId = inputData.getString(AgentLongTaskRecoveryScheduler.KEY_WORKSPACE_ID)
            .orEmpty()
            .trim()
        if (workspaceId.isBlank()) return Result.failure()
        val supervisor = AgentTaskRuntime.supervisor(applicationContext)
        val workspace = supervisor.findWorkspace(workspaceId)
            ?: return Result.success()
        val sessionStore = SharedPreferencesAgentSessionStore(
            applicationContext,
            "task:$workspaceId"
        )
        val activeWorkspaceIds = supervisor.activeWorkspaces()
            .mapTo(linkedSetOf(), AgentWorkspace::workspaceId)
        if (workspaceId in activeWorkspaceIds) {
            return if (AgentTaskLivenessPolicy().hasPendingAssessment(workspace)) {
                Result.retry()
            } else {
                Result.success()
            }
        }
        val decision = AgentLongTaskRecoveryPolicy.decide(
            workspace,
            sessionStore.load(),
            activeWorkspaceIds
        ) ?: return Result.success()
        runCatching { setForeground(foregroundInfo(workspaceId)) }
            .onFailure { Log.w(LOG_TAG, "Could not promote recovery worker to foreground", it) }
        val claim = AgentLongTaskRecoveryClaims.tryAcquire(workspaceId) ?: return Result.retry()
        var projectionRetry = false
        return try {
            val handle = runCatching {
                supervisor.resume(
                workspaceId = workspaceId,
                lane = AgentTaskLane.READ_REASONING,
                priority = AgentTaskPriority.BACKGROUND,
                hook = AgentTaskResumeHook { taskContext, _ ->
                    taskContext.progress("recovery.observe", decision.reason)
                    val context = AppLanguage.wrap(applicationContext)
                    val state = if (decision.mode == AgentLongTaskRecoveryMode.TRANSCRIPT_PROJECTION) {
                        val saved = checkNotNull(sessionStore.load())
                        check(AgentRecoveryTranscript.needsProjection(workspace, saved)) {
                            "Recovery session changed before projection"
                        }
                        AgentRecoveryTranscript.state(saved)
                    } else {
                        val runtime = MobileNativeAgent(context, sessionStore = sessionStore)
                        runtime.bindExecutionLoopEventSink(AgentExecutionLoopEventSink { event ->
                            taskContext.persistExecutionLoop(event)
                        })
                        // The runtime owns dispatch and permission waits; recovery never grants consent.
                        val recovered = if (decision.mode == AgentLongTaskRecoveryMode.LIVENESS_ASSESSMENT) {
                            runtime.assessLivenessWithModel(decision.reason)
                        } else runtime.resumeCurrentTask()
                        runtime.persistSession()
                        recovered
                    }
                    try {
                        taskContext.checkpoint(AgentRecoveryTranscript.CHECKPOINT_ID, stateJson =
                            AgentRecoveryTranscript.pendingCheckpoint(taskContext.workspace(),
                                checkNotNull(sessionStore.load())))
                        AgentRecoveryTranscript.commit(
                            project = { AgentRecoveryTranscript.project(context, taskContext.workspace(), state,
                                AgentTranscriptStore(context)) },
                            persistWorkspace = { persistRecoveredState(taskContext, state) },
                            acknowledge = { taskContext.checkpoint(AgentRecoveryTranscript.CHECKPOINT_ID,
                                stateJson = "{\"pending\":false}") }
                        )
                    } catch (error: Exception) {
                        if (error is CancellationException) throw error
                        projectionRetry = true
                        Log.w(LOG_TAG, "Result commit deferred workspace=${workspaceId.take(8)}", error)
                        taskContext.pause("Result commit pending; saved actions will not be replayed")
                    }
                    when (state.phase) {
                        AgentPhase.WAITING_CONFIRMATION ->
                            taskContext.waitForConfirmation(state.pendingAction?.description.orEmpty())
                        AgentPhase.WAITING_RESPONSE ->
                            taskContext.waitForResponse(state.lastActionResult?.message.orEmpty())
                        AgentPhase.PAUSED -> taskContext.pause(state.lastActionResult?.message.orEmpty())
                        AgentPhase.BLOCKED -> taskContext.blockTask(
                            state.plan?.safetyReview?.reason.orEmpty()
                        )
                        AgentPhase.FAILED -> taskContext.transition(
                            AgentWorkspaceStatus.FAILED,
                            AgentTaskEventKinds.FAILED,
                            state.lastActionResult?.message.orEmpty().ifBlank {
                                "Agent recovery failed"
                            }
                        )
                        AgentPhase.CANCELLED -> taskContext.transition(
                            AgentWorkspaceStatus.CANCELLED,
                            AgentTaskEventKinds.CANCELLED,
                            "Task cancellation requested"
                        )
                        AgentPhase.OBSERVING,
                        AgentPhase.PLANNING,
                        AgentPhase.EXECUTING,
                        AgentPhase.VERIFYING -> taskContext.pause(
                            "Recovery slice yielded after saving its latest checkpoint"
                        )
                        AgentPhase.COMPLETED -> Unit
                    }
                }
                )
            }.getOrElse { error ->
                val message = error.message.orEmpty()
                if (message.contains("already", ignoreCase = true) &&
                    message.contains("active", ignoreCase = true)
                ) {
                    return Result.retry()
                }
                Log.w(LOG_TAG, "Could not claim workspace=${workspaceId.take(8)}", error)
                return Result.retry()
            }
            handle.join()
            if (projectionRetry) Result.retry() else Result.success()
        } finally {
            claim.close()
        }
    }

    private fun persistRecoveredState(
        taskContext: AgentTaskContext,
        state: AgentUiState
    ) {
        val actions = (state.plan?.actionHistory.orEmpty() + state.plan?.actions.orEmpty())
            .distinctBy(AgentAction::id)
        val result = state.lastActionResult
        val planJson = JSONArray().apply {
            actions.forEach { action ->
                put(
                    JSONObject()
                        .put("id", action.id)
                        .put("kind", action.kind.name)
                        .put("target", action.target)
                        .put("status", action.status.name)
                )
            }
        }.toString()
        val stateJson = JSONObject()
            .put("phase", state.phase.name)
            .put("message", result?.message.orEmpty())
            .put("metadata", JSONObject(result?.metadata.orEmpty()))
            .put(
                "execution_loop",
                state.executionLoop
                    ?.let(AgentExecutionLoopJsonCodec::encode)
                    ?.let(::JSONObject)
            )
            .toString()
        taskContext.recordExecutionSnapshot(
            AgentWorkspaceExecutionSnapshot(
                status = state.phase.toWorkspaceStatus(),
                planSnapshot = planJson,
                resultJson = stateJson,
                errorMessage = if (state.phase in setOf(AgentPhase.FAILED, AgentPhase.BLOCKED)) {
                    result?.message.orEmpty()
                } else {
                    ""
                },
                toolCalls = actions.mapNotNull(::toolCallRecord)
            )
        )
        taskContext.checkpoint(
            checkpointId = "recovery-${state.executionLoop?.revision ?: 0L}",
            planSnapshot = planJson,
            stateJson = stateJson
        )
    }

    private fun toolCallRecord(action: AgentAction): AgentToolCallRecord? {
        if (action.kind !in setOf(AgentActionKind.CALL_NATIVE_TOOL, AgentActionKind.CALL_CONNECTOR)) {
            return null
        }
        return AgentToolCallRecord(
            id = action.id,
            toolName = action.parameters["tool_id"].orEmpty()
                .ifBlank { action.parameters["connector_id"].orEmpty() }
                .ifBlank { action.kind.name.lowercase(Locale.ROOT) },
            status = when (action.status) {
                AgentActionStatus.PROPOSED,
                AgentActionStatus.PENDING_CONFIRMATION -> AgentToolCallStatus.PENDING
                AgentActionStatus.RUNNING,
                AgentActionStatus.WAITING_RESPONSE -> AgentToolCallStatus.RUNNING
                AgentActionStatus.COMPLETED -> AgentToolCallStatus.SUCCEEDED
                AgentActionStatus.FAILED,
                AgentActionStatus.BLOCKED,
                AgentActionStatus.ROLLED_BACK -> AgentToolCallStatus.FAILED
            },
            argumentsJson = action.parameters["input_json"].orEmpty()
                .ifBlank { JSONObject(action.parameters).toString() },
            resultJson = JSONObject().put("message", action.result).toString(),
            errorMessage = action.result.takeIf {
                action.status in setOf(
                    AgentActionStatus.FAILED,
                    AgentActionStatus.BLOCKED,
                    AgentActionStatus.ROLLED_BACK
                )
            }.orEmpty()
        )
    }

    private fun foregroundInfo(workspaceId: String): ForegroundInfo {
        val notificationManager = applicationContext.getSystemService(NotificationManager::class.java)
        notificationManager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                applicationContext.getString(R.string.app_name),
                NotificationManager.IMPORTANCE_LOW
            )
        )
        val openIntent = PendingIntent.getActivity(
            applicationContext,
            workspaceId.hashCode(),
            Intent(applicationContext, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val notification = Notification.Builder(applicationContext, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_tab_chat_filled)
            .setContentTitle(applicationContext.getString(R.string.app_name))
            .setContentText(applicationContext.getString(R.string.agent_task_liveness_assessment))
            .setContentIntent(openIntent)
            .setOnlyAlertOnce(true)
            .setOngoing(true)
            .build()
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ForegroundInfo(
                foregroundNotificationId(workspaceId),
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
            )
        } else {
            ForegroundInfo(foregroundNotificationId(workspaceId), notification)
        }
    }

    private fun foregroundNotificationId(workspaceId: String): Int =
        FOREGROUND_NOTIFICATION_ID xor workspaceId.hashCode()

    private companion object {
        const val LOG_TAG = "GalaxySSILongTask"
        const val CHANNEL_ID = "galaxyssi_agent_long_tasks"
        const val FOREGROUND_NOTIFICATION_ID = 0x53410A
    }
}

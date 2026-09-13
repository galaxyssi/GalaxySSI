package com.galaxyssi.chat

import android.content.Context
import android.util.Log
import androidx.work.BackoffPolicy
import androidx.work.CoroutineWorker
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import androidx.work.workDataOf
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CancellationException
import org.json.JSONObject

/** Work contains only an opaque inbox key; private response bodies stay in the encrypted inbox. */
internal object AgentConnectorBackgroundRecovery {
    const val KEY_RESPONSE = "response_identity"

    fun enqueue(context: Context, response: AgentConnectorResponse) {
        val key = AgentConnectorResponseCodec.identity(response)
        WorkManager.getInstance(context.applicationContext).enqueueUniqueWork(
            "galaxyssi-connector-recovery-$key", ExistingWorkPolicy.KEEP,
            OneTimeWorkRequestBuilder<AgentConnectorBackgroundWorker>()
                .setInputData(workDataOf(KEY_RESPONSE to key))
                .setInitialDelay(1, TimeUnit.SECONDS)
                .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 10, TimeUnit.SECONDS)
                .build())
    }

    fun enqueuePending(context: Context) {
        val end = AgentConnectorResponseStore.highWatermark(context)
        var cursor = 0L
        while (cursor < end) {
            val page = AgentConnectorResponseStore.pendingPage(context, cursor, end)
            page.responses.forEach { enqueue(context, it) }
            check(page.unreadableCount == 0) { "Unreadable connector inbox entry" }
            if (page.nextSequence <= cursor) break
            cursor = page.nextSequence
        }
    }
}

class AgentConnectorBackgroundWorker(context: Context, parameters: WorkerParameters) :
    CoroutineWorker(context, parameters) {
    override suspend fun doWork(): Result {
        return try {
            val key = inputData.getString(AgentConnectorBackgroundRecovery.KEY_RESPONSE).orEmpty()
            if (key.isBlank()) return Result.failure()
            val response = AgentConnectorResponseStore.findPending(applicationContext, key)
                ?: return Result.success()
            // A page may claim and then disappear before committing. Keep the wake-up until retirement.
            if (AgentConnectorResponseBus.dispatchPending(response)) return Result.retry()
            setForeground(AgentRecoveryNotification.foregroundInfo(applicationContext, key))
            if (AgentConnectorBackgroundDelivery(AppLanguage.wrap(applicationContext)).consume(response))
                Result.success() else Result.retry()
        } catch (error: Exception) {
            if (error is CancellationException) throw error
            Log.w("GalaxySSIRecovery", "Connector recovery deferred: ${error.javaClass.simpleName}")
            Result.retry()
        }
    }
}

/** Uses the same supervisor lease and runtime as foreground execution, never a raw-text shortcut. */
internal class AgentConnectorBackgroundDelivery(
    private val context: Context,
    private val runtimeFactory: (AgentSessionStore) -> MobileNativeAgent = {
        MobileNativeAgent(context, sessionStore = it)
    }
) {
    suspend fun consume(response: AgentConnectorResponse): Boolean {
        if (!AgentConnectorResponseStore.contains(context, response)) return true
        if (AgentTerminalDeliveryStore.isTerminal(context, response.sourceMessageId)) {
            AgentConnectorResponseStore.remove(context, response)
            return true
        }
        val delivery = AgentPendingDeliveryStore.find(context, response.sourceMessageId, response.contactId)
        val identity = AgentTaskIdentityPolicy.canonicalConnectorResponseIdentity(delivery,
            response.conversationId, response.taskId, response.turnId)
        if (identity.turnId.isBlank() || identity.conversationId.isBlank()) return false
        val supervisor = AgentTaskRuntime.supervisor(context)
        val workspace = supervisor.findWorkspace(identity.turnId) ?: return false
        if (!AgentConnectorBackgroundIdentity.matches(response, identity, workspace)) return false
        val conversation = AgentTranscriptStore(context).conversation(identity.conversationId) ?: return false
        if (identity.turnId in supervisor.activeTaskIds()) return false
        val claim = AgentLongTaskRecoveryClaims.tryAcquire(identity.turnId) ?: return false
        try {
            val sessions = SharedPreferencesAgentSessionStore(context, "task:${identity.turnId}")
            if (sessions.load() == null) return false
            var committed = false
            val key = AgentConnectorResponseCodec.identity(response)
            if (workspace.status.isTerminal) {
                // Only replay a result commit that this exact inbox response already checkpointed.
                if (!wasAccepted(workspace, key, checkNotNull(sessions.load()))) return false
                context.finishStructuredAgentHandoff(identity.turnId, response)
                commit(response, identity, delivery, null, AgentRecoveryTranscript.state(checkNotNull(sessions.load())))
                return true
            }
            supervisor.reconcileLateConnectorResponse(identity.turnId, response.sourceMessageId,
                delivery?.takeIf { it.turnId == identity.turnId && it.conversationId == identity.conversationId }
                    ?.turnId.orEmpty())
            val handle = supervisor.resume(identity.turnId, AgentTaskLane.READ_REASONING,
                AgentTaskPriority.BACKGROUND, AgentTaskResumeHook { taskContext, _ ->
                    // Restore only after the lease is held, not from a stale page/runtime cache.
                    val current = taskContext.workspace()
                    val saved = checkNotNull(sessions.load())
                    val accepted = wasAccepted(current, key, saved)
                    // Restoring an executable runtime normalizes approval waits; projection must not do that.
                    val runtime = if (accepted) null else runtimeFactory(sessions).apply {
                        activeConversationContext = AgentConversationContext(identity.conversationId, "", emptyList(),
                            conversation.privateMode, trackingPaused = conversation.trackingPaused)
                        activeConversationTurnId = identity.turnId
                    }
                    runtime?.bindExecutionLoopEventSink(AgentExecutionLoopEventSink(taskContext::persistExecutionLoop))
                    var state = if (accepted) AgentRecoveryTranscript.state(saved) else {
                        checkNotNull(runtime)
                        val source = AgentPendingDeliveryStore.recoverySuccessorForResponse(context,
                            response.sourceMessageId, identity.conversationId, identity.turnId)
                            ?: response.sourceMessageId
                        if (!(runtime.canAcceptConnectorResponse(source, response.contactId,
                            identity.conversationId, identity.turnId, identity.taskId) ||
                            runtime.restoreConflictedConnectorReceipt(source, response.contactId,
                                identity.conversationId, identity.turnId, identity.taskId))) {
                            taskContext.waitForResponse("Awaiting the response bound to this task")
                            return@AgentTaskResumeHook
                        }
                        runtime.acceptConnectorOutcome(response, identity.conversationId,
                            identity.turnId, identity.taskId, source) ?: run {
                            taskContext.waitForResponse("Connector outcome was not accepted")
                            return@AgentTaskResumeHook
                        }
                    }
                    if (runtime != null) {
                        runtime.persistSession()
                        checkpointAccepted(taskContext, key, checkNotNull(sessions.load()))
                    }
                    context.finishStructuredAgentHandoff(identity.turnId, response)
                    if (runtime != null) {
                        val recorder = AgentExecutionRunRecorder(context, runtime)
                        state = finalizeAgentExecution(runtime, identity.turnId, state, recorder::recordAgentRunFromState)
                        runtime.persistSession()
                        checkpointAccepted(taskContext, key, checkNotNull(sessions.load()))
                    }
                    commit(response, identity, delivery, runtime, state)
                    committed = true
                    when (state.phase) {
                        AgentPhase.WAITING_CONFIRMATION -> taskContext.waitForConfirmation(state.pendingAction?.description.orEmpty())
                        AgentPhase.WAITING_RESPONSE -> taskContext.waitForResponse(state.lastActionResult?.message.orEmpty())
                        AgentPhase.PAUSED -> taskContext.pause(state.lastActionResult?.message.orEmpty())
                        AgentPhase.BLOCKED -> taskContext.blockTask(state.plan?.safetyReview?.reason.orEmpty())
                        AgentPhase.CANCELLED -> taskContext.transition(AgentWorkspaceStatus.CANCELLED,
                            AgentTaskEventKinds.CANCELLED, "Task cancelled")
                        AgentPhase.FAILED -> taskContext.transition(AgentWorkspaceStatus.FAILED,
                            AgentTaskEventKinds.FAILED, state.lastActionResult?.message.orEmpty())
                        AgentPhase.COMPLETED -> Unit
                        else -> taskContext.pause("Connector recovery yielded at a durable checkpoint")
                    }
                })
            handle.join()
            return committed
        } finally { claim.close() }
    }

    private fun commit(response: AgentConnectorResponse, identity: AgentConnectorResponseIdentity,
                       delivery: AgentPendingDelivery?, runtime: MobileNativeAgent?, state: AgentUiState) {
        val transcripts = AgentTranscriptStore(context)
        AgentConnectorReplyCommit.run(
            checkpoint = { context.persistAgentWorkspaceSnapshot(identity.turnId, state, runtime, required = true) },
            project = {
                AgentRecoveryTranscript.project(context,
                    checkNotNull(AgentTaskRuntime.supervisor(context).findWorkspace(identity.turnId)), state, transcripts)
                transcripts.recordConnectorUsage(identity.conversationId, response)
            },
            completeDelivery = { AgentPendingDeliveryStore.completeResponse(context, delivery) },
            bindContinuation = {
                val result = state.lastActionResult
                val source = result?.metadata?.get("source_message_id")?.toLongOrNull() ?: 0L
                if (state.phase == AgentPhase.WAITING_RESPONSE && source > 0 &&
                    result?.metadata?.get("awaiting_response") == "true") {
                    AgentPendingDeliveryStore.put(context, AgentPendingDelivery(source, identity.conversationId,
                        identity.turnId, result.metadata["remote_task_id"].orEmpty().ifBlank { identity.turnId },
                        result.metadata["contact_id"].orEmpty()))
                }
            },
            retire = { AgentConnectorResponseStore.removeHandled(context, response, state.phase in setOf(
                AgentPhase.COMPLETED, AgentPhase.FAILED, AgentPhase.CANCELLED, AgentPhase.BLOCKED)) })
    }

    private fun checkpointAccepted(taskContext: AgentTaskContext, key: String, session: AgentSessionSnapshot) {
        taskContext.checkpoint(checkpointId(key), stateJson = JSONObject()
            .put("response_identity", key).put("accepted", true)
            .put("session_id", session.sessionId).put("updated_at", session.updatedAtMillis)
            .put("phase", session.phase.name).put("loop_revision", session.executionLoopSnapshot?.revision ?: -1L)
            .toString())
    }

    private fun wasAccepted(workspace: AgentWorkspace, key: String, session: AgentSessionSnapshot): Boolean = workspace.checkpoints
        .lastOrNull { it.id == checkpointId(key) }?.let {
            runCatching { JSONObject(it.stateJson) }.getOrNull()?.let { json ->
                json.optBoolean("accepted") && json.optString("response_identity") == key &&
                    json.optString("session_id") == session.sessionId &&
                    json.optLong("updated_at", -1L) == session.updatedAtMillis &&
                    json.optString("phase") == session.phase.name &&
                    json.optLong("loop_revision", -2L) == (session.executionLoopSnapshot?.revision ?: -1L)
            }
        } == true

    private fun checkpointId(key: String) = "connector-accepted-$key"
}

package com.galaxyssi.chat

import android.content.Context
import androidx.work.BackoffPolicy
import androidx.work.CoroutineWorker
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.Operation
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import androidx.work.workDataOf
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resume
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.suspendCancellableCoroutine

/** Waiting is not a reply. Only the original source receives the durable final result. */
internal object AgentLocalBrowserDelivery {
    fun settle(context: Context, dispatch: AgentLocalBrowserDispatch,
        result: Result<LocalModelWebToolCompletion>): Boolean {
        val store = AgentLocalBrowserDispatchStore(context)
        val latest = checkNotNull(store.load(dispatch.key))
        if (latest.terminal) return true
        when (store.managedState(dispatch)) {
            AgentManagedBrowserState.DELIVERED -> { store.transition(dispatch, "delivered"); return true }
            AgentManagedBrowserState.STOPPED, AgentManagedBrowserState.OBSOLETE -> {
                AgentLocalCancellationDelivery.settled(context, dispatch.identity, false, true)
                store.transition(dispatch, "cancelled")
                return true
            }
            AgentManagedBrowserState.UNVERIFIED -> return false
            else -> Unit
        }
        if (dispatch.managedOwner != null && result.exceptionOrNull() is AgentModelLoopRecoveryException) return false
        if (!store.owned(dispatch)) {
            store.transition(dispatch, "cancelled")
            return true
        }
        val completion = result.getOrNull()
        if (completion?.waitingForEvent == true) {
            store.transition(dispatch, "waiting")
            return true
        }
        val succeeded = completion != null
        val text = completion?.text ?: context.getString(R.string.cloud_request_failed,
            result.exceptionOrNull()?.message?.take(220) ?: context.getString(R.string.cloud_unknown_error))
        val id = dispatch.identity
        val response = AgentConnectorResponse(id.sourceMessageId, id.contactId, text, id.conversationId,
            id.turnId, id.taskId, success = succeeded)
        if (!AgentConnectorResponseStore.wasRecorded(context, response))
            AgentConnectorResponseBus.publish(context, response)
        check(AgentConnectorResponseStore.wasRecorded(context, response)) { "local_browser_final_not_committed" }
        if (succeeded) AgentObservationContextStore(context).acknowledge(dispatch.observedContextIds)
        AgentResourceHealthStore(context).record("target:${id.contactId}", succeeded,
            System.currentTimeMillis() - dispatch.startedAtMillis)
        store.transition(dispatch, "delivered")
        return true
    }
}

internal object AgentLocalBrowserRecovery {
    fun enqueue(context: Context, record: AgentBrowserUserRequest, replace: Boolean = false): Operation? {
        if (!record.pendingRunWake || record.localDispatchId.isBlank()) return null
        val work = OneTimeWorkRequestBuilder<AgentLocalBrowserRecoveryWorker>().setInputData(workDataOf(
            KEY_REQUEST to record.key, KEY_GENERATION to record.generation))
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.SECONDS).build()
        return WorkManager.getInstance(context.applicationContext).enqueueUniqueWork(
            AgentLongTaskRecoveryScheduler.browserEventWorkName(record),
            if (replace) ExistingWorkPolicy.REPLACE else ExistingWorkPolicy.KEEP, work)
    }

    /** Injected execution is for isolated framework tests; the production worker uses the real local runner. */
    internal suspend fun recover(context: Context, key: String, generation: String,
        execute: (AgentLocalBrowserDispatch, AgentNativeToolCancellationToken) -> LocalModelWebToolCompletion =
            { dispatch, token -> LocalModelWebToolRunner.resume(context.applicationContext, dispatch, token) }): Boolean {
        val app = context.applicationContext
        val browsers = AgentBrowserUserRequestStore(app)
        val record = browsers.load(key)?.takeIf { it.generation == generation && it.pendingRunWake } ?: return true
        if (record.localDispatchId.isBlank()) return true
        val store = AgentLocalBrowserDispatchStore(app)
        val dispatch = store.load(record.localDispatchId) ?: return false
        if (!AgentLocalBrowserDispatchPolicy.matches(dispatch, record)) return false
        // A very fast human return can arrive before the initial loop relinquishes its lease.
        AgentLocalDispatchRegistry.current(dispatch.identity)?.awaitClosed()
        val latest = store.load(dispatch.key) ?: return false
        if (latest.terminal) {
            browsers.acknowledgeRunWake(record)
            return true
        }
        if (latest.managedOwner != null) {
            // This generation's durable STOP cannot be undone by a later control write for the parent.
            if (record.interruptionCode == "browser_owner_stopped") {
                AgentLocalCancellationDelivery.settled(app, latest.identity, false, true)
                store.transition(latest, "cancelled")
                browsers.acknowledgeRunWake(record)
                return true
            }
            when (store.managedState(latest)) {
                AgentManagedBrowserState.DELIVERED -> {
                    store.transition(latest, "delivered"); browsers.acknowledgeRunWake(record); return true
                }
                AgentManagedBrowserState.STOPPED, AgentManagedBrowserState.OBSOLETE -> {
                    AgentLocalBrowserDelivery.settle(app, latest, Result.failure(AgentNativeToolCancelledException()))
                    browsers.acknowledgeRunWake(record)
                    return true
                }
                AgentManagedBrowserState.PAUSED, AgentManagedBrowserState.UNVERIFIED -> return false
                else -> Unit
            }
        }
        store.restorePendingBinding(latest)
        if (!store.owned(latest, pending = true)) {
            if (latest.managedOwner != null) return false
            val workspace = EncryptedAgentWorkspaceStore(app).find(latest.runWorkspaceId)
            val session = SharedPreferencesAgentSessionStore(app, "task:${latest.runWorkspaceId}").load()
            val source = session?.lastActionResult?.metadata?.get("source_message_id")?.toLongOrNull()
            val obsolete = workspace == null || workspace.status.isTerminal || workspace.cancellationRequested ||
                AgentTranscriptStore(app).conversation(latest.identity.conversationId) == null ||
                session?.phase in setOf(AgentPhase.COMPLETED, AgentPhase.CANCELLED, AgentPhase.FAILED) ||
                session?.lastActionResult?.actionId == "agent-paused" ||
                session?.currentPlan != null &&
                    AgentLocalBrowserDispatchPolicy.planBinding(session, latest.identity.actionId) != latest.planBinding ||
                session?.phase == AgentPhase.WAITING_RESPONSE && source != null && source != latest.identity.sourceMessageId
            if (!obsolete) return false
            store.transition(latest, "cancelled")
            browsers.acknowledgeRunWake(record)
            return true
        }
        if (SharedPreferencesAgentSafetySettingsStore(app).load().executionPaused) return false
        val lease = runCatching { AgentLocalDispatchRegistry.register(latest.identity,
            AgentTaskRuntime.cancellationToken(latest.identity.turnId)) }.getOrNull() ?: return false
        return suspendCancellableCoroutine { observer ->
            // WorkManager cancellation detaches this observer; it is not a user STOP of the owned Agent.
            // Its process-owned lease continues to persist/deliver, or a later worker reopens the journal.
            lease.enqueue(AndroidAgentActionExecutor.LOCAL_MODEL_EXECUTOR, request = { token ->
                if (latest.managedOwner != null && store.managedState(latest) != AgentManagedBrowserState.READY)
                    throw AgentModelLoopRecoveryException("managed_browser_not_ready_before_execution")
                check(store.owned(latest, pending = true)) { "local_browser_owner_changed_before_execution" }
                execute(latest, token)
            }, completed = { outcome ->
                val settled = runCatching {
                    if (outcome.exceptionOrNull() is AgentModelLoopRecoveryException && store.managedState(latest) !in
                        setOf(AgentManagedBrowserState.STOPPED, AgentManagedBrowserState.OBSOLETE, AgentManagedBrowserState.DELIVERED)) false
                    else if (!AgentLocalBrowserDelivery.settle(app, latest, outcome)) false
                    else {
                        val current = browsers.load(key)
                        if (current == null || current.generation != generation) true
                        else if (store.load(latest.key)?.state == "cancelled") {
                            browsers.acknowledgeRunWake(current); true
                        } else browsers.acknowledgeObservedRunWake(current)
                    }
                }.getOrElse {
                    android.util.Log.w("GalaxySSILocalBrowser", "Local browser continuation deferred", it)
                    false
                }
                if (observer.isActive) observer.resume(settled)
            }, cancelled = {
                val settled = runCatching {
                    if (latest.managedOwner != null) AgentLocalCancellationDelivery.settled(app, latest.identity, false, true)
                    store.transition(latest, "cancelled")
                    browsers.load(key)?.takeIf { it.generation == generation }?.let(browsers::acknowledgeRunWake)
                    true
                }.getOrElse {
                    android.util.Log.w("GalaxySSILocalBrowser", "Local browser cancellation deferred", it)
                    false
                }
                if (observer.isActive) observer.resume(settled)
            })
        }
    }

    internal const val KEY_REQUEST = "browser_request"
    internal const val KEY_GENERATION = "browser_generation"
}

class AgentLocalBrowserRecoveryWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result {
        val key = inputData.getString(AgentLocalBrowserRecovery.KEY_REQUEST) ?: return Result.failure()
        val generation = inputData.getString(AgentLocalBrowserRecovery.KEY_GENERATION) ?: return Result.failure()
        return try {
            val record = AgentBrowserUserRequestStore(applicationContext).load(key)
            if (record?.generation == generation && (record.runWorkspaceId.isNotBlank() || record.managedOwnerRunId.isNotBlank()))
                runCatching { setForeground(AgentRecoveryNotification.foregroundInfo(applicationContext,
                    record.managedOwnerRunId.ifBlank { record.runWorkspaceId })) }
            if (AgentLocalBrowserRecovery.recover(applicationContext, key, generation)) Result.success() else Result.retry()
        } catch (cancelled: CancellationException) { throw cancelled }
        catch (error: Exception) {
            android.util.Log.w("GalaxySSILocalBrowser", "Local browser wake deferred", error)
            Result.retry()
        }
    }
}

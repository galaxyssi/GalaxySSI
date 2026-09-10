package com.galaxyssi.chat

import android.content.Context
import android.util.Log
import androidx.work.BackoffPolicy
import androidx.work.CoroutineWorker
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CancellationException

internal object AgentMemoryRetractionRecovery {
    fun enqueue(context: Context) = WorkManager.getInstance(context.applicationContext).enqueueUniqueWork(
        "galaxyssi-memory-retraction-recovery-v1", ExistingWorkPolicy.APPEND_OR_REPLACE,
        OneTimeWorkRequestBuilder<AgentMemoryRetractionRecoveryWorker>()
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.SECONDS).build()
    )
}

class AgentMemoryRetractionRecoveryWorker(context: Context, parameters: WorkerParameters) : CoroutineWorker(context, parameters) {
    override suspend fun doWork(): Result = try {
        // A deletion is durable even when global processing is disabled. Never enable it here.
        val index = EncryptedAgentMemoryDeletionIndex(applicationContext)
        var remaining = false
        var madeProgress = false
        AgentMemoryRetractionDeliveryPolicy.requestIfEnabled(
            enabled = { GlobalAgentRepository(applicationContext).settings().enabled },
            pending = { index.pendingRetractions(1).isNotEmpty() },
            request = {
                madeProgress = GlobalSuperAgentRuntime.get(applicationContext)
                    .processPending(100, retractionsOnly = true).processedEventCount > 0
                remaining = index.pendingRetractionCount() > 0
            }
        )
        if (remaining && madeProgress) {
            AgentMemoryRetractionRecovery.enqueue(applicationContext)
            Result.success()
        } else if (remaining) Result.retry() else Result.success()
    } catch (error: Exception) {
        if (error is CancellationException) throw error
        Log.w("GalaxySSIMemory", "Retraction recovery will retry: ${error.javaClass.simpleName}")
        Result.retry()
    }
}

internal object AgentMemoryRetractionDeliveryPolicy {
    fun loadPending(retractionsOnly: Boolean, read: () -> List<GlobalConversationEvent>,
        reportFailure: (Exception) -> Unit): List<GlobalConversationEvent> = try {
        read()
    } catch (error: Exception) {
        if (error is CancellationException || retractionsOnly) throw error
        reportFailure(error)
        emptyList()
    }

    fun requestIfEnabled(enabled: () -> Boolean, pending: () -> Boolean, request: () -> Unit) {
        if (enabled() && pending()) request()
    }

    fun isRetraction(event: GlobalConversationEvent): Boolean =
        event.type == GlobalConversationEventType.MEMORY_DELETED &&
            AgentMemoryRetractionOutbox.isRetraction(event.id) && event.metadata["projection"] == "retract_only"

    fun retainFailure(failure: GlobalEventProcessingFailure): GlobalEventProcessingFailure = failure.copy(
        quarantined = false,
        nextAttemptAtMillis = maxOf(failure.nextAttemptAtMillis,
            failure.lastFailedAtMillis + GlobalEventRetryPolicy.retryDelayMillis(failure.attemptCount))
    )

    fun select(pending: List<GlobalConversationEvent>, ordinary: List<GlobalConversationEvent>,
        failures: List<GlobalEventProcessingFailure>, limit: Int, nowMillis: Long): List<GlobalConversationEvent> {
        val failureById = failures.associateBy { it.eventId }
        return (pending + ordinary).distinctBy { it.id }.filter { event ->
            val failure = failureById[event.id]?.let { if (isRetraction(event)) retainFailure(it) else it }
            GlobalEventRetryPolicy.eligible(failure, nowMillis)
        }.take(limit.coerceIn(1, 250))
    }

}

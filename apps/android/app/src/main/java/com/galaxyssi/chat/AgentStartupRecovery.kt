package com.galaxyssi.chat

import android.content.Context
import android.util.Log
import androidx.work.BackoffPolicy
import androidx.work.CoroutineWorker
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.Operation
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import androidx.work.workDataOf
import java.util.concurrent.TimeUnit

/** Every startup entry point publishes the same durable recovery request. */
internal object AgentStartupRecovery {
    fun enqueue(context: Context): Operation = WorkManager.getInstance(context.applicationContext)
        .enqueueUniqueWork(
            "galaxyssi-startup-recovery-v1",
            ExistingWorkPolicy.KEEP,
            OneTimeWorkRequestBuilder<AgentStartupRecoveryWorker>()
                .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 10L, TimeUnit.SECONDS)
                .build()
        )
}

/** Failed reconciliation must never allow dispatch of an unreconciled checkpoint. */
internal class AgentStartupRecoverySequence(
    private val reconcile: () -> Unit,
    private val dispatch: () -> Unit
) {
    fun run() {
        reconcile()
        dispatch()
    }
}

class AgentStartupRecoveryWorker(context: Context, parameters: WorkerParameters) :
    CoroutineWorker(context, parameters) {
    override suspend fun doWork(): Result = try {
        AgentMemoryRetractionRecovery.enqueue(applicationContext)
        var reconciled = 0
        AgentStartupRecoverySequence(
            reconcile = {
                reconciled = AgentColdBootRecoveryCoordinator.pauseInterruptedTasks(
                    applicationContext, "Task interrupted by a previous app process"
                )
            },
            dispatch = {
                AgentLongTaskRecoveryScheduler.enqueueRecoverable(
                    applicationContext, "durable_startup_recovery"
                )
            }
        ).run()
        runCatching { KnowledgeSemanticRuntime.production(applicationContext).requestIndex() }
            .onFailure { Log.w("GalaxySSIRecovery", "Knowledge indexing enqueue failed: ${it.javaClass.simpleName}") }
        Result.success(workDataOf(
            "reconciled_tasks" to reconciled,
            "boot_count" to android.provider.Settings.Global.getInt(
                applicationContext.contentResolver, android.provider.Settings.Global.BOOT_COUNT, -1),
            "process_instance_id" to AgentProcessIdentity.instanceId
        ))
    } catch (error: Exception) {
        if (error is kotlinx.coroutines.CancellationException) throw error
        Log.w("GalaxySSIRecovery", "Startup recovery will retry: ${error.javaClass.simpleName}")
        Result.retry()
    }
}

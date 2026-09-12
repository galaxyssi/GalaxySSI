package com.galaxyssi.chat

import android.content.Context
import android.util.Log
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext

internal object KnowledgePayloadWork {
    fun enqueue(context: Context) = WorkManager.getInstance(context.applicationContext).enqueueUniquePeriodicWork(
        "galaxyssi-knowledge-payload-maintenance-v1", ExistingPeriodicWorkPolicy.KEEP,
        PeriodicWorkRequestBuilder<KnowledgePayloadWorker>(15, TimeUnit.MINUTES)
            .setInitialDelay(15, TimeUnit.MINUTES)
            .setConstraints(Constraints.Builder().setRequiresDeviceIdle(true).build()).build())

    fun run(context: Context, shouldYield: () -> Boolean): MemorySegmentSweep.Outcome {
        val name = "galaxyssi_knowledge_v2.db"
        if (!context.getDatabasePath(name).isFile) return MemorySegmentSweep.Outcome.COMPLETE
        val db = AgentKnowledgeDatabase.shared(context, name, "galaxyssi_agent_knowledge")
        return MemorySegmentSweep(shouldYield, step = { checkActive ->
            checkActive()
            if (!db.advancePayloadUsage()) return@MemorySegmentSweep false
            val page = db.migratePayloadPage(checkActive)
            if (!page.complete) false else {
                checkActive()
                db.reclaimPayloads(checkActive)?.complete
            }
        }).run()
    }
}

/** Local, checkpointed physical maintenance; never invokes a model or sends memory to a provider. */
class KnowledgePayloadWorker(context: Context, parameters: WorkerParameters) : CoroutineWorker(context, parameters) {
    override suspend fun doWork(): Result = withContext(Dispatchers.IO) {
        try {
            val job = currentCoroutineContext()
            when (KnowledgePayloadWork.run(applicationContext) {
                job.ensureActive(); isStopped || AppForegroundTracker.isForeground()
            }) {
                MemorySegmentSweep.Outcome.COMPLETE -> Result.success()
                MemorySegmentSweep.Outcome.DEFERRED -> Result.retry()
            }
        } catch (failure: Exception) {
            if (failure is CancellationException) throw failure
            Log.w("GalaxySSIKnowledge", "Payload maintenance deferred: ${failure.javaClass.simpleName}")
            Result.retry()
        }
    }
}

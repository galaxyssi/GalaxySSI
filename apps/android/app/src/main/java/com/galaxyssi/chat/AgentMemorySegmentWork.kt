package com.galaxyssi.chat

import android.content.Context
import android.util.Log
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import java.io.File
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext

internal object AgentMemorySegmentWork {
    internal const val NAME = "galaxyssi-memory-segment-maintenance-v1"

    fun enqueue(context: Context, name: String = NAME) = WorkManager.getInstance(context.applicationContext)
        .enqueueUniquePeriodicWork(name, ExistingPeriodicWorkPolicy.KEEP,
            PeriodicWorkRequestBuilder<AgentMemorySegmentWorker>(15, TimeUnit.MINUTES)
                .setInitialDelay(15, TimeUnit.MINUTES)
                .setConstraints(Constraints.Builder().setRequiresDeviceIdle(true).build())
                .build())

    internal fun run(context: Context, shouldYield: () -> Boolean): MemorySegmentSweep.Outcome {
        val path = context.getDatabasePath("${AgentMemoryStorage.DATABASE}.db")
        if (!File(path.absolutePath + ".segments.catalog.db").isFile) return MemorySegmentSweep.Outcome.COMPLETE
        val database = AgentEncryptedDatabase(context, AgentMemoryStorage.DATABASE)
        return MemorySegmentSweep(shouldYield = shouldYield,
            step = { checkActive -> database.tryMaintainMemorySegments(checkActive)?.cycleComplete }).run()
    }
}

/** Local storage upkeep only: no model, global-agent, notification or network dispatch. */
class AgentMemorySegmentWorker(context: Context, parameters: WorkerParameters) : CoroutineWorker(context, parameters) {
    override suspend fun doWork(): Result = withContext(Dispatchers.IO) {
        try {
            val job = currentCoroutineContext()
            when (AgentMemorySegmentWork.run(applicationContext) {
                job.ensureActive()
                isStopped || AppForegroundTracker.isForeground()
            }) {
                MemorySegmentSweep.Outcome.COMPLETE -> Result.success()
                MemorySegmentSweep.Outcome.DEFERRED -> Result.retry()
            }
        } catch (error: Exception) {
            if (error is CancellationException) throw error
            Log.w("GalaxySSIMemory", "Segment maintenance deferred: ${error.javaClass.simpleName}")
            Result.retry()
        }
    }
}

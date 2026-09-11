package com.galaxyssi.chat

import android.content.Context
import android.os.Process
import android.os.SystemClock
import androidx.work.CoroutineWorker
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkInfo
import androidx.work.WorkManager
import androidx.work.WorkQuery
import androidx.work.WorkerParameters
import androidx.work.workDataOf
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** Metadata maintenance is independent of model loading, downloads and inference enablement. */
internal object KnowledgeCountWork {
    internal fun name(namespace: String) = "knowledge-counts-v1-$namespace"
    fun request(context: Context, namespace: String) {
        val manager = WorkManager.getInstance(context)
        val name = name(namespace)
        val pending = manager.getWorkInfos(WorkQuery.Builder.fromUniqueWorkNames(listOf(name))
            .addStates(listOf(WorkInfo.State.ENQUEUED, WorkInfo.State.BLOCKED)).build()).get()
        if (pending.isNotEmpty()) return
        // The controller serializes requests; a running worker gets at most one durable successor.
        manager.enqueueUniqueWork(name, ExistingWorkPolicy.APPEND_OR_REPLACE,
            OneTimeWorkRequestBuilder<KnowledgeCountWorker>().setInputData(workDataOf("namespace" to namespace)).build()).result.get()
    }
    fun cancel(context: Context, namespace: String) {
        WorkManager.getInstance(context).cancelUniqueWork(name(namespace))
    }
}

class KnowledgeCountWorker(context: Context, parameters: WorkerParameters) : CoroutineWorker(context, parameters) {
    override suspend fun doWork(): Result = withContext(Dispatchers.IO) {
        val controller = KnowledgeSemanticRuntime.forWorker(applicationContext, inputData.getString("namespace").orEmpty())
        controller.awaitReady()
        val started = SystemClock.elapsedRealtime()
        val priority = Process.getThreadPriority(Process.myTid())
        controller.runningWork.incrementAndGet()
        try {
            Process.setThreadPriority(Process.THREAD_PRIORITY_BACKGROUND)
            if (!controller.countingEnabled) return@withContext Result.success()
            val database = controller.database()
            var pending: Boolean
            do {
                if (isStopped || !controller.countingEnabled) return@withContext Result.success()
                for (kind in KnowledgeCountSchema.Kind.entries) {
                    if (isStopped || !controller.countingEnabled) return@withContext Result.success()
                    database.transaction { KnowledgeCounts.advance(it, kind) }
                }
                pending = database.access(KnowledgeCounts::pending)
            } while (pending && SystemClock.elapsedRealtime() - started < 15_000)
            controller.refreshCounts(schedule = false)
            if (pending && !isStopped && controller.countingEnabled) controller.requestCounts()
            Result.success()
        } catch (error: Exception) {
            if (error is kotlinx.coroutines.CancellationException) throw error
            controller.update { it.copy(countsError = error.message.orEmpty().take(180)) }
            Result.failure()
        } finally {
            Process.setThreadPriority(priority)
            controller.runningWork.decrementAndGet()
        }
    }
}

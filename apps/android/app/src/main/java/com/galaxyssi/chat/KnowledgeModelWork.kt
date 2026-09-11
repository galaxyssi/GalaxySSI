package com.galaxyssi.chat

import android.content.Context
import android.os.SystemClock
import androidx.work.BackoffPolicy
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
import java.io.IOException
import java.util.concurrent.TimeUnit

internal object KnowledgeModelWork {
    private fun indexName(namespace: String) = "knowledge-index-v1-$namespace"
    private fun downloadName(namespace: String) = "knowledge-model-v1-$namespace"
    fun requestIndex(context: Context, namespace: String) {
        val manager = WorkManager.getInstance(context)
        val name = indexName(namespace)
        val pending = manager.getWorkInfos(WorkQuery.Builder.fromUniqueWorkNames(listOf(name))
            .addStates(listOf(WorkInfo.State.ENQUEUED, WorkInfo.State.BLOCKED)).build()).get()
        if (pending.isNotEmpty()) return
        // Called on the controller's serial executor. A running worker gets at most one durable successor.
        manager.enqueueUniqueWork(name, ExistingWorkPolicy.APPEND_OR_REPLACE,
            OneTimeWorkRequestBuilder<KnowledgeVectorIndexWorker>().setInputData(workDataOf("namespace" to namespace))
                .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 10, TimeUnit.SECONDS).build()).result.get()
    }
    fun download(context: Context, namespace: String, request: String, recover: Boolean = false) {
        WorkManager.getInstance(context).enqueueUniqueWork(downloadName(namespace),
            if (recover) ExistingWorkPolicy.KEEP else ExistingWorkPolicy.REPLACE,
            OneTimeWorkRequestBuilder<KnowledgeEmbeddingDownloadWorker>()
                .setInputData(workDataOf("namespace" to namespace, "request" to request))
                // Validate actual HTTPS reachability, not Google's platform connectivity probe.
                // A completed local artifact can be verified/activated entirely offline.
                .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 10, TimeUnit.SECONDS).build()).result.get()
    }
    fun cancelIndex(context: Context, namespace: String) { WorkManager.getInstance(context).cancelUniqueWork(indexName(namespace)) }
    fun cancelDownload(context: Context, namespace: String) { WorkManager.getInstance(context).cancelUniqueWork(downloadName(namespace)) }
}

class KnowledgeEmbeddingDownloadWorker(context: Context, parameters: WorkerParameters) : CoroutineWorker(context, parameters) {
    override suspend fun doWork(): Result = withContext(Dispatchers.IO) {
        val controller = KnowledgeSemanticRuntime.forWorker(applicationContext, inputData.getString("namespace").orEmpty())
        val request = inputData.getString("request").orEmpty()
        controller.awaitReady()
        if (!controller.acceptsDownload(request)) return@withContext Result.success()
        controller.runningWork.incrementAndGet()
        try {
            controller.update { it.copy(phase = "downloading", error = "") }
            synchronized(controller.artifact) {
                val alreadyVerified = try {
                    controller.artifact.verifyInstalled { isStopped || !controller.acceptsDownload(request) }
                    true
                } catch (_: IOException) { false }
                if (!alreadyVerified) controller.artifact.download(KnowledgeEmbeddingModel.urls,
                    { isStopped || !controller.acceptsDownload(request) }) { bytes ->
                    if (controller.acceptsDownload(request)) controller.update { it.copy(downloaded = bytes) }
                }
            }
            if (!isStopped && controller.acceptsDownload(request)) controller.completeDownload(request).get()
            Result.success()
        } catch (cancelled: java.util.concurrent.CancellationException) {
            if (isStopped) throw cancelled
            Result.success()
        } catch (error: Exception) {
            val retry = error is IOException && error !is KnowledgeModelDownloadRejected && controller.acceptsDownload(request)
            if (controller.acceptsDownload(request)) {
                if (retry) controller.update { it.copy(phase = "error", error = error.message.orEmpty().take(180)) }
                else controller.failDownload(request, error).get()
            }
            if (retry) Result.retry() else Result.failure()
        } finally { controller.runningWork.decrementAndGet() }
    }
}

class KnowledgeVectorIndexWorker(context: Context, parameters: WorkerParameters) : CoroutineWorker(context, parameters) {
    override suspend fun doWork(): Result = withContext(Dispatchers.IO) {
        val controller = KnowledgeSemanticRuntime.forWorker(applicationContext, inputData.getString("namespace").orEmpty())
        controller.awaitReady()
        if (!controller.indexingEnabled) return@withContext Result.success()
        val started = SystemClock.elapsedRealtime()
        val priority = android.os.Process.getThreadPriority(android.os.Process.myTid())
        controller.runningWork.incrementAndGet()
        try {
            android.os.Process.setThreadPriority(android.os.Process.THREAD_PRIORITY_BACKGROUND)
            val ledger = controller.database().vectors(KnowledgeEmbeddingModel.spec)
            ledger.ensureRegistered()
            while (!ledger.changes().bootstrap()) {
                if (isStopped || !controller.indexingEnabled) return@withContext Result.success()
                if (SystemClock.elapsedRealtime() - started >= 15_000) {
                    controller.requestIndex()
                    return@withContext Result.success()
                }
            }
            if (ledger.nextJob() == null) {
                val nativeReady = controller.searchSession()?.advanceIndex { isStopped || !controller.indexingEnabled } != false
                controller.refreshCounts()
                controller.update { it.copy(phase = if (nativeReady) "ready" else "indexing", error = "") }
                if (!nativeReady) controller.requestIndex()
                return@withContext Result.success()
            }
            controller.update { it.copy(phase = "indexing", error = "") }
            var pending = false
            LlamaKnowledgeVectorEncoder.open(applicationContext, controller.modelFile, KnowledgeEmbeddingModel.spec).use { encoder ->
                val indexer = KnowledgeVectorIndexer(ledger, encoder)
                do {
                    if (isStopped || !controller.indexingEnabled) break
                    pending = indexer.runBatch(8) { isStopped || !controller.indexingEnabled }.pending
                    controller.searchSession()?.advanceIndex { isStopped || !controller.indexingEnabled }
                    controller.refreshCounts()
                } while (pending && SystemClock.elapsedRealtime() - started < 15_000)
            }
            if (!isStopped && controller.indexingEnabled) {
                pending = (controller.searchSession()?.advanceIndex { isStopped || !controller.indexingEnabled } == false) || pending
                controller.update { it.copy(phase = if (pending) "indexing" else "ready") }
                if (pending) controller.requestIndex()
            }
            Result.success()
        } catch (error: Exception) {
            if (error is kotlinx.coroutines.CancellationException) throw error
            controller.update { it.copy(phase = "error", error = error.message.orEmpty().take(180)) }
            Result.failure()
        } finally {
            android.os.Process.setThreadPriority(priority)
            controller.runningWork.decrementAndGet()
        }
    }
}

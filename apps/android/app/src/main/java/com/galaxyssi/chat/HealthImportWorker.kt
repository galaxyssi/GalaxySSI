package com.galaxyssi.chat

import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import androidx.work.workDataOf
import java.io.File
import java.util.concurrent.CancellationException

internal object HealthImportScheduler {
    fun enqueue(context: Context, id: String, prepareCapture: Boolean = false) {
        val request = OneTimeWorkRequestBuilder<HealthImportWorker>().setInputData(workDataOf("health_job" to id, "capture_stage" to prepareCapture)).build()
        // Preparation and recognition have separate unique work: submitting as preparation finishes cannot lose the OCR dispatch.
        WorkManager.getInstance(context.applicationContext).enqueueUniqueWork("${if (prepareCapture) "health-capture" else "health-import"}:$id", ExistingWorkPolicy.KEEP, request)
    }
    fun cancel(context: Context, id: String) {
        HealthOriginalStore(context).use { it.updateJob(id) { job -> job.copy(state = HealthImportState.CANCELLED) } }
        WorkManager.getInstance(context.applicationContext).cancelUniqueWork("health-import:$id")
        WorkManager.getInstance(context.applicationContext).cancelUniqueWork("health-capture:$id")
    }
    fun recoverAsync(context: Context) {
        kotlin.concurrent.thread(name = "health-import-recovery", isDaemon = true) {
            runCatching { HealthTableScheduler.recover(context) }
            runCatching { HealthRecordExportScheduler.recover(context) }
            if (!context.getDatabasePath("health_records_v1.db").exists() &&
                !context.getDatabasePath(HealthOriginalStore.LEGACY_DATABASE).exists()) return@thread
            runCatching { HealthOriginalExportScheduler.recover(context) }
            runCatching { HealthOriginalStore(context).use { store ->
                var after: Pair<Long, String>? = null
                do {
                    val jobs = store.pendingJobs(after)
                    jobs.forEach { enqueue(context, it.id, it.captureBatch.isNotBlank() && !it.captureSubmitted) }
                    after = if (jobs.size == 100) jobs.last().let { it.createdAt to it.id } else null
                } while (after != null)
            } }
        }
    }
}

/** Only opaque IDs enter WorkManager. URI, names, OCR and health fields stay encrypted. */
class HealthImportWorker(context: Context, params: WorkerParameters) : Worker(context, params) {
    override fun doWork(): Result {
        val id = inputData.getString("health_job") ?: return Result.failure()
        HealthOriginalStore(applicationContext).use { store ->
            return when (HealthImportPipeline(applicationContext).run(store, id, inputData.getBoolean("capture_stage", false)) { isStopped }) {
                HealthImportOutcome.COMPLETE -> Result.success()
                HealthImportOutcome.RETRY -> Result.retry()
                HealthImportOutcome.FAILED -> Result.failure()
            }
        }
    }
}

internal enum class HealthImportOutcome { COMPLETE, FAILED, RETRY }
private class HealthImportInterrupted : CancellationException()

internal class HealthImportPipeline(private val context: Context, private val recordDatabase: String = "health_records_v1.db") {
    fun run(store: HealthOriginalStore, id: String, prepareCapture: Boolean = false, stopped: () -> Boolean = { false }): HealthImportOutcome {
            val initial = store.job(id) ?: return HealthImportOutcome.FAILED
            if (initial.state in listOf(HealthImportState.CANCELLED, HealthImportState.REVIEW, HealthImportState.TABLE_REVIEW, HealthImportState.ORIGINAL_ONLY, HealthImportState.CAPTURE_READY)) return HealthImportOutcome.COMPLETE
            if (prepareCapture && initial.captureSubmitted) return HealthImportOutcome.COMPLETE
            if (!prepareCapture && initial.captureBatch.isNotBlank() && !initial.captureSubmitted) return HealthImportOutcome.COMPLETE
            fun cancelled() {
                if (store.job(id)?.state == HealthImportState.CANCELLED) throw CancellationException()
                if (stopped()) throw HealthImportInterrupted()
            }
            try {
                cancelled()
                val uri = Uri.parse(initial.sourceUri)
                var name = initial.name
                var size = initial.totalBytes
                if (name.isBlank()) context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE), null, null, null)?.use {
                    if (it.moveToFirst()) { name = it.getString(0).orEmpty(); if (!it.isNull(1)) size = it.getLong(1) }
                }
                val mime = initial.mime.ifBlank { context.contentResolver.getType(uri).orEmpty() }.ifBlank { "application/octet-stream" }
                store.updateJob(id) { it.copy(name = name, mime = mime, totalBytes = size, state = HealthImportState.COPYING, error = "") }
                val existing = store.originalForJob(id)?.takeIf(store::present)
                val original = existing ?: context.contentResolver.openInputStream(uri)?.use { input ->
                    store.importOriginal(id, input, name, mime, if (initial.cameraToken.isBlank()) "file" else "camera", ::cancelled) { copied ->
                        store.updateJob(id) { it.copy(copiedBytes = copied) }
                    }
                } ?: throw HealthImportFailure("source_unavailable")
                if (initial.cameraToken.isNotBlank()) HealthCaptureFiles.file(context, initial.cameraToken).delete()
                store.updateJob(id) { it.copy(originalId = original.id, copiedBytes = original.size, totalBytes = original.size,
                    state = HealthImportState.RECOGNIZING) }
                cancelled()
                if (initial.originalOnly) {
                    store.updateJob(id) { it.copy(state = HealthImportState.ORIGINAL_ONLY) }; return HealthImportOutcome.COMPLETE
                }
                if (prepareCapture) {
                    if (!mime.startsWith("image/")) throw HealthImportFailure("image_unsupported")
                    val quality = HealthPhotoInspector.inspect(store, original)
                    cancelled(); store.inspectCapture(id, quality)
                    return HealthImportOutcome.COMPLETE
                }
                if (HealthTableParser.format(original.name, original.mime) != null) {
                    HealthTableStore(context, recordDatabase).use { tables -> HealthTableImport.stage(store, original, id, tables, ::cancelled) }
                    cancelled(); store.updateJob(id) { it.copy(state = HealthImportState.TABLE_REVIEW, error = "") }
                    return HealthImportOutcome.COMPLETE
                }
                if (!mime.startsWith("image/") && mime != "application/pdf") {
                    store.updateJob(id) { it.copy(state = HealthImportState.ORIGINAL_ONLY) }; return HealthImportOutcome.COMPLETE
                }
                HealthOcrEngine().use { engine ->
                    val current = store.job(id) ?: throw HealthImportFailure("job_missing")
                    if (mime == "application/pdf") {
                        engine.pdf(store, original, current.nextPage, ::cancelled,
                            { count -> store.updateJob(id) { it.copy(pageCount = count) } },
                            { page -> cancelled(); store.savePage(id, page) })
                    } else if (current.nextPage == 0) {
                        store.updateJob(id) { it.copy(pageCount = 1) }
                        val page = engine.image(store, original)
                        cancelled(); store.savePage(id, page)
                    }
                }
                store.updateJob(id) { it.copy(state = HealthImportState.REVIEW, error = "") }
                return HealthImportOutcome.COMPLETE
            } catch (_: HealthImportInterrupted) {
                store.updateJob(id) { it.copy(state = HealthImportState.QUEUED, error = "interrupted") }
                return HealthImportOutcome.RETRY
            } catch (_: CancellationException) {
                if (store.job(id)?.state == HealthImportState.CANCELLED) return HealthImportOutcome.COMPLETE
                store.updateJob(id) { it.copy(state = HealthImportState.FAILED, error = "recognition_cancelled") }
                return HealthImportOutcome.FAILED
            } catch (_: OutOfMemoryError) {
                store.updateJob(id) { it.copy(state = HealthImportState.FAILED, error = "memory_pressure") }
                return HealthImportOutcome.FAILED
            } catch (failure: Exception) {
                val code = when (failure) {
                    is HealthImportFailure -> failure.code
                    is SecurityException -> "source_permission"
                    is android.database.sqlite.SQLiteFullException -> "storage_full"
                    is java.io.FileNotFoundException -> "source_unavailable"
                    else -> "import_failed"
                }
                store.updateJob(id) { it.copy(state = HealthImportState.FAILED, error = code) }
                return HealthImportOutcome.FAILED
            }
    }
}

internal object HealthCaptureFiles {
    fun file(context: Context, token: String): File {
        require(runCatching { java.util.UUID.fromString(token).toString() == token }.getOrDefault(false))
        return File(context.cacheDir, "health-capture/$token.jpg")
    }
}

package com.galaxyssi.chat

import android.content.Context
import java.io.RandomAccessFile
import java.nio.channels.OverlappingFileLockException
import java.util.concurrent.CancellationException
import java.util.concurrent.ConcurrentHashMap

internal fun HealthImportJob.needsPdfPassword() = state == HealthImportState.FAILED &&
    (protectedPdf || error in setOf("pdf_password", "pdf_password_wrong", "pdf_password_interrupted", "pdf_permission", "pdf_password_memory"))
internal fun HealthImportJob.protectedReviewPending() = needsPdfPassword() ||
    state == HealthImportState.PROTECTED_RECOGNIZING || protectedPdf && state != HealthImportState.REVIEW

/** Password work is foreground-only; durable jobs remain recoverable without persisting the secret. */
internal object HealthProtectedPdfImport {
    private val leasedPaths = ConcurrentHashMap.newKeySet<String>()

    // A kernel file lock distinguishes an abandoned checkpoint from a live foreground reader.
    private fun <T : Any> withLease(store: HealthOriginalStore, work: () -> T): T? {
        val file = store.protectedPdfLeaseFile.canonicalFile
        if (!leasedPaths.add(file.path)) return null
        try {
            val parent = requireNotNull(file.parentFile)
            check(parent.isDirectory || parent.mkdirs() || parent.isDirectory)
            return RandomAccessFile(file, "rw").use { lockFile ->
                val lock = try { lockFile.channel.tryLock() } catch (_: OverlappingFileLockException) { null }
                lock?.use { work() }
            }
        } finally { leasedPaths.remove(file.path) }
    }

    fun recoverInterrupted(store: HealthOriginalStore) {
        if (store.protectedPdfRuns().isEmpty()) return
        withLease(store) {
            while (true) {
                val rows = store.protectedPdfRuns()
                if (rows.isEmpty()) break
                rows.forEach { id ->
                    store.updateJob(id) { current -> if (current.state == HealthImportState.PROTECTED_RECOGNIZING)
                        current.copy(state = HealthImportState.FAILED, error = "pdf_password_interrupted", protectedPdf = true) else current }
                }
            }
        }
    }

    fun run(context: Context, store: HealthOriginalStore, id: String, password: CharArray,
            stopped: () -> Boolean, progress: (Int, Int) -> Unit = { _, _ -> }): HealthImportOutcome =
        try { withLease(store) { recognize(context, store, id, password, stopped, progress) } ?: HealthImportOutcome.RETRY }
        finally { password.fill('\u0000') }

    private fun recognize(context: Context, store: HealthOriginalStore, id: String, password: CharArray,
                          stopped: () -> Boolean, progress: (Int, Int) -> Unit): HealthImportOutcome {
        val job = store.updateJob(id) {
            if (it.needsPdfPassword() || it.state == HealthImportState.PROTECTED_RECOGNIZING)
                it.copy(state = HealthImportState.PROTECTED_RECOGNIZING, error = "", protectedPdf = true)
            else it
        }?.takeIf { it.state == HealthImportState.PROTECTED_RECOGNIZING } ?: return HealthImportOutcome.FAILED
        fun cancelled() {
            if (stopped() || store.job(id)?.state != HealthImportState.PROTECTED_RECOGNIZING) throw CancellationException()
        }
        fun failure(code: String) {
            store.updateJob(id) { current -> if (current.state == HealthImportState.PROTECTED_RECOGNIZING)
                current.copy(state = HealthImportState.FAILED, error = code) else current }
        }
        try {
            cancelled()
            val original = store.originalForJob(id)?.takeIf { it.id == job.originalId && it.mime == "application/pdf" && store.present(it) }
                ?: throw HealthImportFailure("source_unavailable")
            HealthPdfTextReader.openProtected(context, store, original, password, ::cancelled).use { pdf ->
                if (!pdf.canExtract) throw HealthImportFailure("pdf_permission")
                val count = pdf.pageCount
                if (count <= 0 || job.nextPage > count) throw HealthImportFailure("pdf_unsupported")
                cancelled()
                store.updateJob(id) { it.copy(pageCount = count) }
                HealthOcrEngine().use { engine ->
                    for (index in job.nextPage until count) {
                        cancelled(); progress(index + 1, count)
                        val page = engine.protectedPdfPage(pdf, index, ::cancelled)
                        cancelled(); store.savePage(id, page)
                    }
                }
            }
            cancelled()
            val done = store.updateJob(id) {
                if (it.state == HealthImportState.PROTECTED_RECOGNIZING) it.copy(state = HealthImportState.REVIEW) else it
            }
            return if (done?.state == HealthImportState.REVIEW) HealthImportOutcome.COMPLETE else HealthImportOutcome.RETRY
        } catch (_: CancellationException) {
            failure("pdf_password_interrupted")
            return HealthImportOutcome.RETRY
        } catch (_: OutOfMemoryError) {
            failure("pdf_password_memory")
            return HealthImportOutcome.FAILED
        } catch (error: Exception) {
            failure(when (error) {
                is HealthImportFailure -> error.code
                is android.database.sqlite.SQLiteFullException -> "storage_full"
                else -> "pdf_unsupported"
            })
            return HealthImportOutcome.FAILED
        }
    }
}

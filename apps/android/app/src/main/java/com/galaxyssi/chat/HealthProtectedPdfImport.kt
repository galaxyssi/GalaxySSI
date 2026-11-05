package com.galaxyssi.chat

import android.content.Context
import java.util.concurrent.CancellationException
import java.util.concurrent.ConcurrentHashMap

internal fun HealthImportJob.needsPdfPassword() = state == HealthImportState.FAILED && when (error) {
    "pdf_password", "pdf_password_wrong", "pdf_password_interrupted", "pdf_permission", "pdf_password_memory" -> true
    else -> false
}

/** Password work is foreground-only; durable jobs remain recoverable without persisting the secret. */
internal object HealthProtectedPdfImport {
    private val running = ConcurrentHashMap.newKeySet<String>()

    fun run(context: Context, store: HealthOriginalStore, id: String, password: CharArray,
            stopped: () -> Boolean, progress: (Int, Int) -> Unit = { _, _ -> }): HealthImportOutcome {
        if (!running.add(id)) {
            password.fill('\u0000')
            return HealthImportOutcome.RETRY
        }
        try {
            val job = store.job(id)?.takeIf { it.needsPdfPassword() } ?: return HealthImportOutcome.FAILED
            fun cancelled() {
                if (stopped() || store.job(id)?.needsPdfPassword() != true) throw CancellationException()
            }
            fun failure(code: String) {
                store.updateJob(id) { current -> if (current.needsPdfPassword()) current.copy(error = code) else current }
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
                val done = store.updateJob(id) { if (it.needsPdfPassword()) it.copy(state = HealthImportState.REVIEW, error = "") else it }
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
        } finally {
            password.fill('\u0000')
            running.remove(id)
        }
    }
}

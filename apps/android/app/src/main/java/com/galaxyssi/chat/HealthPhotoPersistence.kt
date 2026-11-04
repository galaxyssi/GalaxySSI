package com.galaxyssi.chat

import android.content.Context
import java.util.concurrent.Executors

/** A pressed shutter can finish encrypting after its Activity stops; no Activity or plaintext cache file is retained. */
internal object HealthPhotoPersistence {
    private val io = Executors.newSingleThreadExecutor()
    fun save(context: Context, id: String, bytes: ByteArray, complete: (Boolean) -> Unit) {
        val app = context.applicationContext
        io.execute {
            var saved = false
            try {
                HealthOriginalStore(app).use { store ->
                    val job = store.job(id) ?: return@use
                    val original = bytes.inputStream().use { input -> store.importOriginal(id, input, job.name, "image/jpeg", "camera",
                        checkCancelled = { if (store.job(id) == null || store.job(id)?.state == HealthImportState.CANCELLED) throw java.util.concurrent.CancellationException() }) }
                    store.updateJob(id) { it.copy(originalId = original.id, sourceUri = HealthOriginalContentProvider.uri(app, original.id).toString(), state = HealthImportState.QUEUED) }
                    HealthImportScheduler.enqueue(app, id, prepareCapture = true); saved = true
                }
            } catch (_: Throwable) {
                runCatching { HealthOriginalStore(app).use { store -> store.updateJob(id) { it.copy(state = HealthImportState.FAILED, error = "capture_save_failed") } } }
            } finally { bytes.fill(0); runCatching { complete(saved) } }
        }
    }
}

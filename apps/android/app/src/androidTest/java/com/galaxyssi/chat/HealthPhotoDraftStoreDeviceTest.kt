package com.galaxyssi.chat

import android.content.ContentValues
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import androidx.test.platform.app.InstrumentationRegistry
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.UUID
import org.junit.Assert.*
import org.junit.Test

class HealthPhotoDraftStoreDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private fun id() = UUID.randomUUID().toString()
    private fun fixture(test: (String, File, HealthOriginalStore) -> Unit) {
        val name = "health-photo-test-${id()}.db"; val root = File(context.cacheDir, "health-photo-test-${id()}")
        try { HealthOriginalStore(context, name, root).use { test(name, root, it) } }
        finally { context.deleteDatabase(name); root.deleteRecursively() }
    }
    private fun batch(store: HealthOriginalStore) = HealthPhotoBatch(id(), "report", 1).also(store::createCaptureBatch)
    private fun job(owner: HealthPhotoBatch) = HealthImportJob(id(), "content://test/source", 1, mode = owner.mode,
        name = "synthetic-report.png", mime = "image/png", captureBatch = owner.id)
    private fun picture(): ByteArray {
        val bitmap = Bitmap.createBitmap(1200, 800, Bitmap.Config.ARGB_8888)
        try {
            bitmap.eraseColor(Color.WHITE)
            Canvas(bitmap).drawText("Glucose 5.6 mmol/L", 60f, 200f, Paint(Paint.ANTI_ALIAS_FLAG).apply { textSize = 75f; color = Color.BLACK })
            return ByteArrayOutputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it); it.toByteArray() }
        } finally { bitmap.recycle() }
    }
    private fun prepare(store: HealthOriginalStore, owner: HealthPhotoBatch): HealthImportJob {
        val job = job(owner); store.addCaptureJob(owner.id, job)
        val original = picture().inputStream().use { store.importOriginal(job.id, it, job.name, job.mime, "camera") }
        store.updateJob(job.id) { it.copy(originalId = original.id) }
        assertEquals(HealthImportOutcome.COMPLETE, HealthImportPipeline(context).run(store, job.id, prepareCapture = true))
        return store.job(job.id)!!
    }
    @Test fun preparationPreservesAnEncryptedOriginalButDoesNotRecognizeOrSaveMeasurements() = fixture { _, _, store ->
        val owner = batch(store); val prepared = prepare(store, owner)
        assertEquals(HealthImportState.CAPTURE_READY, prepared.state); assertEquals(0, prepared.nextPage)
        assertNull(store.page(prepared.id, 1)); assertNotNull(store.capturePage(prepared.id)!!.quality)
        assertFalse(store.captureBatch(owner.id)!!.submitted)
        assertTrue(store.present(store.original(prepared.originalId)!!))
    }
    @Test fun ordinaryWorkerCannotBypassTheCaptureReviewGate() = fixture { _, _, store ->
        val owner = batch(store); val entry = job(owner); store.addCaptureJob(owner.id, entry)
        assertEquals(HealthImportOutcome.COMPLETE, HealthImportPipeline(context).run(store, entry.id))
        assertEquals(HealthImportState.QUEUED, store.job(entry.id)!!.state); assertNull(store.page(entry.id, 1))
    }
    @Test fun confirmedBatchCanRunRealOcrAndLatePreparationCannotConsumeItsDispatch() = fixture { _, _, store ->
        val owner = batch(store); val prepared = prepare(store, owner)
        assertEquals(listOf(prepared.id), store.submitCaptureBatch(owner.id))
        assertTrue(store.job(prepared.id)!!.captureSubmitted)
        assertEquals(HealthImportOutcome.COMPLETE, HealthImportPipeline(context).run(store, prepared.id, prepareCapture = true))
        assertEquals(HealthImportState.QUEUED, store.job(prepared.id)!!.state)
        assertEquals(HealthImportOutcome.COMPLETE, HealthImportPipeline(context).run(store, prepared.id))
        assertEquals(HealthImportState.REVIEW, store.job(prepared.id)!!.state)
        assertTrue(store.page(prepared.id, 1)!!.lines.any { it.text.contains("Glucose", true) })
        assertTrue(runCatching { store.submitCaptureBatch(owner.id) }.isFailure)
    }
    @Test fun submissionRollsBackEveryJobIfAnyPageIsNotReady() = fixture { _, _, store ->
        val owner = batch(store); val ready = prepare(store, owner); val pending = job(owner)
        store.addCaptureJob(owner.id, pending)
        assertTrue(runCatching { store.submitCaptureBatch(owner.id) }.isFailure)
        assertEquals(HealthImportState.CAPTURE_READY, store.job(ready.id)!!.state)
        assertFalse(store.job(ready.id)!!.captureSubmitted); assertFalse(store.captureBatch(owner.id)!!.submitted)
    }
    @Test fun absentOriginalBlocksSubmissionWithoutLosingTheDraft() = fixture { _, _, store ->
        val owner = batch(store); val ready = prepare(store, owner)
        store.removeOriginalBytes(store.original(ready.originalId)!!)
        assertTrue(runCatching { store.submitCaptureBatch(owner.id) }.isFailure)
        assertEquals(1, store.capturePageCount(owner.id)); assertFalse(store.captureBatch(owner.id)!!.submitted)
    }
    @Test fun moveAndRetakePreserveTheRequestedPageOrderAndKeepUncroppedBytes() = fixture { _, _, store ->
        val owner = batch(store); val first = prepare(store, owner); val second = prepare(store, owner); val third = prepare(store, owner)
        store.moveCapturePage(third.id, -1)
        assertEquals(listOf(first.id, third.id, second.id), store.capturePages(owner.id).map { it.jobId })
        val replacement = job(owner); store.addCaptureJob(owner.id, replacement, third.id)
        assertEquals(listOf(first.id, replacement.id, second.id), store.capturePages(owner.id).map { it.jobId })
        assertNull(store.job(third.id)); assertTrue(store.present(store.original(third.originalId)!!))
        assertEquals(2, store.capturePageNumber(replacement.id))
    }
    @Test fun removedPagesCannotBeRecoveredAsPendingJobs() = fixture { _, _, store ->
        val owner = batch(store); val ready = prepare(store, owner)
        store.removeCapturePage(ready.id)
        assertNull(store.capturePage(ready.id)); assertNull(store.job(ready.id))
        assertTrue(store.pendingJobs().none { it.id == ready.id }); assertTrue(store.present(store.original(ready.originalId)!!))
    }
    @Test fun replacementCannotTakeOverAPageFromAnotherBatch() = fixture { _, _, store ->
        val owner = batch(store); val other = batch(store); val target = job(owner); store.addCaptureJob(owner.id, target)
        val candidate = job(other)
        assertTrue(runCatching { store.addCaptureJob(other.id, candidate, target.id) }.isFailure)
        assertNull(store.job(candidate.id)); assertEquals(listOf(target.id), store.capturePages(owner.id).map { it.jobId })
    }
    @Test fun captureModeIsAppliedAtSubmissionAndSubmittedPagesAreImmutable() = fixture { _, _, store ->
        val owner = batch(store); val ready = prepare(store, owner)
        store.captureMode(owner.id, "device"); store.submitCaptureBatch(owner.id)
        assertEquals("device", store.job(ready.id)!!.mode)
        assertTrue(runCatching { store.captureMode(owner.id, "report") }.isFailure)
        assertTrue(runCatching { store.moveCapturePage(ready.id, 1) }.isFailure)
        assertTrue(runCatching { store.removeCapturePage(ready.id) }.isFailure)
    }
    @Test fun modeChangesFromAnotherConnectionCannotReopenASubmittedBatch() = fixture { name, root, store ->
        val owner = batch(store); val ready = prepare(store, owner)
        val pool = java.util.concurrent.Executors.newFixedThreadPool(2)
        val start = java.util.concurrent.CountDownLatch(1)
        try {
            HealthOriginalStore(context, name, root).use { other ->
                val changing = pool.submit { start.await(); repeat(50) { index -> runCatching { other.captureMode(owner.id, if (index % 2 == 0) "device" else "report") } } }
                val submitting = pool.submit { start.await(); store.submitCaptureBatch(owner.id) }
                start.countDown(); changing.get(20, java.util.concurrent.TimeUnit.SECONDS); submitting.get(20, java.util.concurrent.TimeUnit.SECONDS)
                assertTrue(store.captureBatch(owner.id)!!.submitted)
                assertEquals(store.captureBatch(owner.id)!!.mode, store.job(ready.id)!!.mode)
                assertTrue(runCatching { other.captureMode(owner.id, "device") }.isFailure)
            }
        } finally { pool.shutdownNow() }
    }
    @Test fun submittedDocumentNumbersFollowTheEditedOrderRatherThanCaptureTime() = fixture { _, _, store ->
        val owner = batch(store); val a = prepare(store, owner); val b = prepare(store, owner); val c = prepare(store, owner)
        store.moveCapturePage(c.id, -1)
        assertEquals(listOf(a.id, c.id, b.id), store.submitCaptureBatch(owner.id))
        assertEquals(listOf(1, 2, 3), listOf(a, c, b).map { store.job(it.id)!!.documentPage })
    }
    @Test fun closingAnEmptyDraftDoesNotLeaveAHiddenCaptureButNeverDiscardsSavedPages() = fixture { _, _, store ->
        val owner = batch(store); store.discardEmptyCapture(owner.id); assertNull(store.captureBatch(owner.id))
        val withPage = batch(store); val ready = prepare(store, withPage)
        store.discardEmptyCapture(withPage.id); assertNotNull(store.captureBatch(withPage.id))
        store.removeCapturePage(ready.id); store.discardEmptyCapture(withPage.id); assertNull(store.captureBatch(withPage.id))
        assertNotNull(store.original(ready.originalId))
    }
    @Test fun photoPagePaginationReachesAllFortyFivePagesWithoutReadingAWholeDraftJson() = fixture { _, _, store ->
        val owner = batch(store); repeat(45) { store.addCaptureJob(owner.id, job(owner)) }
        var cursor = -1; val ids = mutableListOf<String>()
        do { val page = store.capturePages(owner.id, cursor); assertTrue(page.size <= 20); ids += page.map { it.jobId }
            cursor = if (page.size == 20) page.last().position else -1
        } while (cursor >= 0)
        assertEquals(45, ids.size); assertEquals(45, ids.distinct().size)
    }
    @Test fun capturePagesAndJobsSurviveReopenAndBindTheOrderingIndex() = fixture { name, root, store ->
        val owner = batch(store); val ready = prepare(store, owner)
        HealthOriginalStore(context, name, root).use { reopened -> assertEquals(owner, reopened.captureBatch(owner.id)); assertNotNull(reopened.capturePage(ready.id)!!.quality) }
        context.openOrCreateDatabase(name, 0, null).use { db ->
            db.rawQuery("SELECT payload FROM capture_pages", null).use { it.moveToFirst(); assertFalse(String(it.getBlob(0), Charsets.ISO_8859_1).contains("luminance")) }
            db.update("capture_pages", ContentValues().apply { put("position", 999) }, "job_id=?", arrayOf(ready.id))
        }
        assertTrue(runCatching { store.capturePage(ready.id) }.isFailure)
    }
    @Test fun catalogVersionOneUpgradePreservesOriginalBytesJobsAndOcrPages() {
        val name = "health-capture-migration-${id()}.db"; val root = File(context.cacheDir, "health-capture-migration-${id()}")
        try {
            lateinit var original: HealthOriginal; lateinit var savedJob: HealthImportJob
            HealthOriginalStore(context, name, root).use { store ->
                savedJob = HealthImportJob(id(), "content://test/source", 1); store.createJob(savedJob)
                original = picture().inputStream().use { store.importOriginal(savedJob.id, it, "report.png", "image/png", "file") }
                store.savePage(savedJob.id, HealthOcrPage(1, 100, 100, listOf(HealthOcrLine("saved before upgrade"))))
            }
            context.openOrCreateDatabase(name, 0, null).use { db ->
                db.execSQL("DROP TABLE capture_pages"); db.execSQL("DROP TABLE capture_batches")
                db.execSQL("DROP TABLE library_export_items"); db.execSQL("DROP TABLE library_exports")
                db.execSQL("CREATE TABLE originals_legacy(id TEXT PRIMARY KEY,imported_at INTEGER NOT NULL,digest_token TEXT UNIQUE NOT NULL,payload BLOB NOT NULL,key_payload BLOB NOT NULL)")
                db.execSQL("INSERT INTO originals_legacy SELECT id,imported_at,digest_token,payload,key_payload FROM originals")
                db.execSQL("DROP TABLE originals"); db.execSQL("ALTER TABLE originals_legacy RENAME TO originals")
                db.execSQL("CREATE INDEX original_page ON originals(imported_at DESC,id DESC)"); db.version = 1
            }
            HealthOriginalStore(context, name, root).use { upgraded ->
                assertEquals(original, upgraded.original(original.id)); assertEquals(1, upgraded.job(savedJob.id)!!.nextPage)
                assertEquals("saved before upgrade", upgraded.page(savedJob.id, 1)!!.lines.single().text)
                assertArrayEquals(picture(), ByteArrayOutputStream().use { output -> upgraded.copyVerified(original, output); output.toByteArray() })
                assertNotNull(batch(upgraded))
            }
        } finally { context.deleteDatabase(name); root.deleteRecursively() }
    }
}

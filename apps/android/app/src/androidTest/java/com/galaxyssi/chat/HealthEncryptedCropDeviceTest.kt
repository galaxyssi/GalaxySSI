package com.galaxyssi.chat

import android.app.KeyguardManager
import android.content.Intent
import android.graphics.BitmapFactory
import android.graphics.Rect
import android.os.FileObserver
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.lifecycle.Lifecycle
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import com.canhub.cropper.CropImageView
import java.io.File
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import org.junit.Assert.*
import org.junit.Assume.assumeFalse
import org.junit.Test

class HealthEncryptedCropDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private fun id() = UUID.randomUUID().toString()

    private data class Page(val batch: HealthPhotoBatch, val job: HealthImportJob, val original: HealthOriginal, val bytes: ByteArray)

    private fun seed(store: HealthOriginalStore, keep: Boolean = true): Page {
        val batch = HealthPhotoBatch(id(), "report", System.currentTimeMillis(), keepOriginal = keep)
        store.createCaptureBatch(batch)
        val job = HealthImportJob(id(), "content://fixture/source", System.currentTimeMillis(), name = "report.png",
            mime = "image/png", captureBatch = batch.id)
        store.addCaptureJob(batch.id, job)
        val bytes = syntheticHealthPaper()
        val original = store.importOriginal(job.id, bytes.inputStream(), job.name, job.mime, "file")
        store.updateJob(job.id) { it.copy(originalId = original.id) }
        assertEquals(HealthImportOutcome.COMPLETE, HealthImportPipeline(context).run(store, job.id, prepareCapture = true))
        return Page(batch, requireNotNull(store.job(job.id)), original, bytes)
    }

    private fun Page.spec(names: HealthOverviewDatabases) =
        HealthCropSpec(original.id, "report-cropped.png", "image/png", batch.id, job.id, fixture = names.fixture)

    private fun fixture(test: (HealthOverviewDatabases, HealthOriginalStore) -> Unit) {
        val names = HealthOverviewDatabases(id())
        try { HealthOriginalStore(context, names.originals, names.originalRoot(context)).use { test(names, it) } }
        finally { clearHealthOverviewFixture(context, names) }
    }

    @Test fun nativeCropStreamsToEncryptedStorageAndReplacesOnlyTheReadyPage() = fixture { names, store ->
        assumeFalse("Native crop requires an unlocked display", context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        val page = seed(store)
        val before = requireNotNull(store.capturePage(page.job.id))
        val cache = File(context.cacheDir, "composer-crops").apply { check(isDirectory || mkdirs()) }
        val plainCreated = AtomicBoolean()
        @Suppress("DEPRECATION")
        val watcher = object : FileObserver(cache.path, FileObserver.CREATE or FileObserver.MOVED_TO) {
            override fun onEvent(event: Int, path: String?) { plainCreated.set(true) }
        }
        val source = HealthOriginalContentProvider.uri(context, page.original.id, names.fixture).toString()
        val item = ComposerAttachmentItem(page.original.id, source, page.original.name, page.original.mime, page.original.size, sendOriginal = true)
        val intent = Intent(context, ComposerAttachmentEditorActivity::class.java)
            .putExtra(ComposerAttachmentEditorActivity.ITEMS, ComposerAttachmentItem.encode(listOf(item)))
            .putExtra("crop_immediately", true).putExtra("health_original_parent", page.original.id)
            .putExtra(HEALTH_CROP_BATCH, page.batch.id).putExtra(HEALTH_CROP_PAGE, page.job.id)
        watcher.startWatching()
        try {
            ActivityScenario.launch<ComposerAttachmentEditorActivity>(intent).use { scenario ->
                await {
                    var ready = false
                    scenario.onActivity { activity -> ready = command(activity.window.decorView,
                        activity.getString(R.string.composer_crop_use))?.isEnabled == true }
                    ready
                }
                scenario.onActivity { activity ->
                    activity.findViewById<CropImageView>(R.id.composerCropImage).cropRect = Rect(180, 160, 700, 1000)
                    assertTrue(requireNotNull(command(activity.window.decorView, activity.getString(R.string.composer_crop_use))).performClick())
                }
                await { scenario.state == Lifecycle.State.DESTROYED }
            }
        } finally { watcher.stopWatching() }
        assertFalse("No plaintext crop should be created even temporarily", plainCreated.get())
        val replaced = store.capturePages(page.batch.id).single()
        assertNotEquals(before.jobId, replaced.jobId)
        assertEquals(before.position, replaced.position)
        assertNull(store.job(before.jobId))
        assertNull(store.page(replaced.jobId, 1))
        val job = requireNotNull(store.job(replaced.jobId))
        assertEquals(HealthImportState.CAPTURE_READY, job.state)
        val original = requireNotNull(store.original(job.originalId))
        assertEquals("crop:${page.original.id}", original.source)
        val crop = store.input(original).use { it.readBytes() }
        val bitmap = requireNotNull(BitmapFactory.decodeByteArray(crop, 0, crop.size))
        try { assertEquals(520, bitmap.width); assertEquals(840, bitmap.height) } finally { bitmap.recycle() }
        assertArrayEquals(page.bytes, store.input(page.original).use { it.readBytes() })
        assertFalse(crop.contentEquals(File(names.originalRoot(context), original.relativePath).readBytes()))
        assertFalse(names.originalRoot(context).walkTopDown().any { it.isFile && it.extension == "partial" })
    }

    @Test fun failedEncodingAndSecondWriterCannotPublishEvenWhenThePipeReceivedACompleteImage() = fixture { names, store ->
        val page = seed(store)
        val before = store.originalCount()
        val done = CountDownLatch(1)
        var outcome: Result<HealthOriginal>? = null
        val output = HealthCropOutput.start(context, page.spec(names)) { _, result -> outcome = result; done.countDown() }
        try {
            assertTrue(runCatching { context.contentResolver.openInputStream(output.uri) }.isFailure)
            requireNotNull(context.contentResolver.openOutputStream(output.uri)).use { writer ->
                assertTrue(runCatching { context.contentResolver.openOutputStream(output.uri) }.isFailure)
                writer.write(page.bytes)
            }
            assertFalse("Closing the encoder pipe must not publish on its own", done.await(180, TimeUnit.MILLISECONDS))
            assertEquals(page.job.id, store.capturePages(page.batch.id).single().jobId)
            output.finishEncoding(false)
            assertTrue(done.await(10, TimeUnit.SECONDS))
            assertTrue(requireNotNull(outcome).isFailure)
            assertEquals(before, store.originalCount())
            assertEquals(page.job.id, store.capturePages(page.batch.id).single().jobId)
        } finally { output.cancel() }
    }

    @Test fun invalidCropAndStalePagePreserveTheOriginalAndDraft() = fixture { names, store ->
        val page = seed(store)
        val spec = page.spec(names)
        val initial = requireNotNull(store.capturePage(page.job.id))
        assertTrue(runCatching { store.saveCrop(id(), "broken".byteInputStream(), spec) }.isFailure)
        assertEquals(initial, store.capturePages(page.batch.id).single())
        val croppedId = id()
        var sourceRead = false
        val valid = object : java.io.FilterInputStream(page.bytes.inputStream()) {
            override fun read(bytes: ByteArray, offset: Int, length: Int): Int {
                val count = super.read(bytes, offset, length)
                if (count < 0 && !sourceRead) {
                    sourceRead = true
                    store.captureMode(page.batch.id, "device")
                }
                return count
            }
        }
        assertTrue(runCatching { valid.use { store.saveCrop(croppedId, it, spec) } }.isFailure)
        assertTrue(sourceRead)
        assertEquals(initial, store.capturePages(page.batch.id).single())
        assertNull(store.originalForJob(croppedId))
        assertArrayEquals(page.bytes, store.input(page.original).use { it.readBytes() })
    }

    @Test fun truncatedCropIsRejectedEvenIfEncoderClaimsSuccess() = fixture { names, store ->
        val page = seed(store)
        val done = CountDownLatch(1)
        var outcome: Result<HealthOriginal>? = null
        val output = HealthCropOutput.start(context, page.spec(names)) { _, result -> outcome = result; done.countDown() }
        try {
            requireNotNull(context.contentResolver.openOutputStream(output.uri, "wt")).use { it.write(page.bytes, 0, page.bytes.size - 12) }
            output.finishEncoding(true)
            assertTrue(done.await(10, TimeUnit.SECONDS))
            assertTrue(requireNotNull(outcome).isFailure)
            assertEquals(page.job.id, store.capturePages(page.batch.id).single().jobId)
            assertEquals(1L, store.originalCount())
        } finally { output.cancel() }
    }

    @Test fun jpegWriterPublishesOnlyAfterConfirmationAndLateCancelledWritesAreDiscarded() = fixture { names, store ->
        val page = seed(store)
        val png = requireNotNull(BitmapFactory.decodeByteArray(page.bytes, 0, page.bytes.size))
        val jpeg = try { java.io.ByteArrayOutputStream().use {
            assertTrue(png.compress(android.graphics.Bitmap.CompressFormat.JPEG, 95, it))
            it.toByteArray()
        } } finally { png.recycle() }
        val spec = page.spec(names).copy(name = "report-cropped.jpg", mime = "image/jpeg")
        val done = CountDownLatch(1)
        var saved: HealthOriginal? = null
        val output = HealthCropOutput.start(context, spec) { _, result -> saved = result.getOrNull(); done.countDown() }
        try {
            requireNotNull(context.contentResolver.openOutputStream(output.uri, "wt")).use { it.write(jpeg) }
            assertFalse(done.await(100, TimeUnit.MILLISECONDS))
            output.finishEncoding(true)
            assertTrue(done.await(10, TimeUnit.SECONDS))
            assertArrayEquals(jpeg, store.input(requireNotNull(saved)).use { it.readBytes() })
            val replaced = store.capturePages(page.batch.id).single()
            assertEquals(saved?.id, store.job(replaced.jobId)?.originalId)
            val late = CountDownLatch(1)
            val abandoned = HealthCropOutput.start(context, spec) { _, _ -> late.countDown() }
            abandoned.cancel()
            assertTrue(late.await(10, TimeUnit.SECONDS))
            requireNotNull(context.contentResolver.openOutputStream(abandoned.uri, "wt")).use { it.write(jpeg) }
            assertEquals(replaced, store.capturePages(page.batch.id).single())
            assertEquals(2L, store.originalCount())
        } finally { output.cancel(); jpeg.fill(0) }
    }

    @Test fun reviewOnlyCropRetainsPrivacyAndOrdinaryCropCreatesASeparateImport() = fixture { names, store ->
        val page = seed(store, keep = false)
        val next = id()
        val derived = store.saveCrop(next, page.bytes.inputStream(), page.spec(names))
        assertTrue(derived.reviewOnly)
        assertNotEquals(page.original.id, derived.id)
        assertFalse(store.present(page.original))
        assertEquals(0L, store.originalCount())
        assertFalse(requireNotNull(store.job(next)).keepOriginal)
        val separate = id()
        val file = store.saveCrop(separate, page.bytes.inputStream(),
            HealthCropSpec(derived.id, "new-review.png", "image/png", keepOriginal = false, fixture = names.fixture))
        assertTrue(file.reviewOnly)
        assertTrue(store.present(derived))
        assertEquals(HealthImportState.QUEUED, store.job(separate)?.state)
        assertEquals(next, store.capturePages(page.batch.id).single().jobId)
    }

    @Test fun databaseFailureAfterWritingTheEncryptedCropRollsBackThePageAndNewOriginal() = fixture { names, store ->
        val page = seed(store)
        val bitmap = requireNotNull(BitmapFactory.decodeByteArray(page.bytes, 0, page.bytes.size))
        val cropped = android.graphics.Bitmap.createBitmap(bitmap, 180, 160, 520, 840)
        val bytes = try { java.io.ByteArrayOutputStream().use {
            assertTrue(cropped.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it))
            it.toByteArray()
        } } finally { bitmap.recycle(); cropped.recycle() }
        val newId = id()
        val old = requireNotNull(store.capturePage(page.job.id))
        store.libraryDatabase.execSQL("CREATE TRIGGER fail_crop_page BEFORE INSERT ON capture_pages BEGIN SELECT RAISE(ABORT,'test failure'); END")
        try {
            assertTrue(runCatching { store.saveCrop(newId, bytes.inputStream(), page.spec(names)) }.exceptionOrNull() is android.database.sqlite.SQLiteConstraintException)
            assertEquals(old, store.capturePages(page.batch.id).single())
            assertEquals(page.job, store.job(page.job.id))
            assertNull(store.job(newId))
            assertNull(store.originalForJob(newId))
            val ledger = HealthCropRecovery(names.originalRoot(context))
            assertFalse(ledger.files(newId).staging.exists())
            assertFalse(ledger.files(newId).destination.exists())
            assertFalse(ledger.marker(newId).exists())
            assertArrayEquals(page.bytes, store.input(page.original).use { it.readBytes() })
        } finally {
            bytes.fill(0)
            store.libraryDatabase.execSQL("DROP TRIGGER fail_crop_page")
        }
    }

    private fun command(root: View, text: String): TextView? {
        if (root is TextView && root.text.toString() == text) return root
        if (root !is ViewGroup) return null
        return (0 until root.childCount).firstNotNullOfOrNull { command(root.getChildAt(it), text) }
    }

    private fun await(condition: () -> Boolean) {
        val deadline = SystemClock.elapsedRealtime() + 15_000
        do {
            if (condition()) return
            SystemClock.sleep(50)
        } while (SystemClock.elapsedRealtime() < deadline)
        fail("Timed out waiting for native health crop")
    }
}

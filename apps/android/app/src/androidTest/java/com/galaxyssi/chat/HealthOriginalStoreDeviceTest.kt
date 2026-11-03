package com.galaxyssi.chat

import android.content.ContentValues
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.pdf.PdfDocument
import android.system.Os
import android.system.OsConstants
import androidx.core.content.FileProvider
import androidx.test.platform.app.InstrumentationRegistry
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.RandomAccessFile
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.CancellationException
import org.junit.Assert.*
import org.junit.Test

class HealthOriginalStoreDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private fun id() = UUID.randomUUID().toString()
    private fun fixture(test: (String, File, HealthOriginalStore) -> Unit) {
        val name = "health-original-test-${id()}.db"
        val root = File(context.cacheDir, "health-original-test-${id()}")
        try { HealthOriginalStore(context, name, root).use { test(name, root, it) } }
        finally { context.deleteDatabase(name); root.deleteRecursively() }
    }
    private fun bytes(size: Int = 240_321) = ByteArray(size) { ((it * 31 + it / 100) % 251).toByte() }
    private fun import(store: HealthOriginalStore, payload: ByteArray, jobId: String = id()) =
        store.importOriginal(jobId, payload.inputStream(), "private-report.bin", "application/octet-stream", "file")
    private fun restored(store: HealthOriginalStore, original: HealthOriginal) = ByteArrayOutputStream().use {
        assertEquals(original.size, store.copyVerified(original, it)); it.toByteArray()
    }
    private fun hash(bytes: ByteArray) = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }

    @Test fun originalIsEncryptedByteFaithfulAndReadableAfterReopen() = fixture { name, root, store ->
        val payload = bytes(); val original = import(store, payload)
        assertEquals(hash(payload), original.sha256)
        assertFalse(File(root, original.relativePath).readBytes().contentEquals(payload))
        HealthOriginalStore(context, name, root).use { reopened -> assertArrayEquals(payload, restored(reopened, reopened.original(original.id)!!)) }
        context.openOrCreateDatabase(name, 0, null).use { db ->
            db.rawQuery("SELECT payload,key_payload FROM originals", null).use {
                assertTrue(it.moveToFirst()); assertFalse(String(it.getBlob(0), Charsets.ISO_8859_1).contains("private-report"))
                assertTrue(it.getBlob(1).size > 32)
            }
        }
    }
    @Test fun proxyDescriptorSupportsAuthenticatedRandomAccessAcrossSegments() = fixture { _, _, store ->
        val payload = bytes(); val original = import(store, payload)
        store.descriptor(original).use { fd ->
            for (offset in listOf(0L, 65_530L, 180_000L, payload.size - 83L)) {
                val expected = payload.copyOfRange(offset.toInt(), minOf(payload.size, offset.toInt() + 400))
                val buffer = ByteArray(expected.size)
                Os.lseek(fd.fileDescriptor, offset, OsConstants.SEEK_SET)
                var read = 0
                while (read < buffer.size) { val n = Os.read(fd.fileDescriptor, buffer, read, buffer.size - read); assertTrue(n > 0); read += n }
                assertArrayEquals(expected, buffer)
            }
        }
    }
    @Test fun duplicateImportsReuseOneOriginalAndStableJobMappings() = fixture { _, root, store ->
        val a = id(); val b = id(); val payload = bytes()
        val first = import(store, payload, a); val duplicate = import(store, payload, b)
        assertEquals(first, duplicate); assertEquals(first, store.originalForJob(a)); assertEquals(first, store.originalForJob(b))
        assertEquals(1, root.walkTopDown().count { it.extension == "ghealth" })
        assertEquals(first, import(store, payload, a))
    }
    @Test fun missingBytesCanBeReimportedWithoutBreakingExistingSourceIdentity() = fixture { _, _, store ->
        val payload = bytes(); val original = store.importOriginal(id(), payload.inputStream(), "cropped.png", "image/png", "crop:${id()}")
        assertTrue(store.removeOriginalBytes(original)); assertFalse(store.present(original))
        val repaired = import(store, payload)
        assertEquals(original.id, repaired.id); assertNotEquals(original.streamId, repaired.streamId)
        assertEquals(original.source, repaired.source); assertEquals(original.name, repaired.name); assertEquals(original.mime, repaired.mime)
        assertArrayEquals(payload, restored(store, repaired))
    }
    @Test fun cancellationRemovesOnlyItsOwnStagingFilesAndDoesNotCommitMetadata() = fixture { _, root, store ->
        var checks = 0
        val result = runCatching { store.importOriginal(id(), bytes().inputStream(), "cancelled", "image/png", "file",
            checkCancelled = { if (++checks >= 3) throw CancellationException() }) }
        assertTrue(result.exceptionOrNull() is CancellationException)
        assertTrue(store.originals().isEmpty()); assertEquals(0, root.walkTopDown().count { it.isFile })
    }
    @Test fun ciphertextTamperingIsAnExplicitIntegrityFailureNotEmptyContent() = fixture { _, root, store ->
        val original = import(store, bytes())
        RandomAccessFile(File(root, original.relativePath), "rw").use { file ->
            file.seek(70_000); val value = file.read(); file.seek(70_000); file.write(value xor 0x40)
        }
        assertTrue(runCatching { restored(store, original) }.isFailure)
        assertEquals(original, store.original(original.id))
    }
    @Test fun truncationCannotPassExportVerification() = fixture { _, root, store ->
        val original = import(store, bytes())
        RandomAccessFile(File(root, original.relativePath), "rw").use { it.setLength(it.length() - 20) }
        assertTrue(runCatching { restored(store, original) }.isFailure)
    }
    @Test fun swappedWrappedKeysCannotDecryptAnotherOriginal() = fixture { name, _, store ->
        val a = import(store, bytes()); val b = import(store, bytes(71_111))
        context.openOrCreateDatabase(name, 0, null).use { db ->
            val key = db.rawQuery("SELECT key_payload FROM originals WHERE id=?", arrayOf(a.id)).use { it.moveToFirst(); it.getBlob(0) }
            db.update("originals", ContentValues().apply { put("key_payload", key) }, "id=?", arrayOf(b.id))
        }
        assertTrue(runCatching { restored(store, b) }.isFailure)
        assertArrayEquals(bytes(), restored(store, a))
    }
    @Test fun pagesAreAtomicEncryptedCheckpointsAndCancellationCannotBeOverwritten() = fixture { name, _, store ->
        val job = HealthImportJob(id(), "content://test/private-source", 1)
        store.createJob(job)
        val page = HealthOcrPage(1, 100, 100, listOf(HealthOcrLine("Glucose 5.6 mmol/L", listOf(0, 0, 800, 500))))
        store.savePage(job.id, page)
        assertEquals(1, store.job(job.id)!!.nextPage); assertEquals(page, store.page(job.id, 1))
        assertTrue(runCatching { store.savePage(job.id, page) }.isFailure)
        assertEquals(1, store.job(job.id)!!.nextPage)
        context.openOrCreateDatabase(name, 0, null).use { db -> db.rawQuery("SELECT payload FROM pages", null).use {
            it.moveToFirst(); assertFalse(String(it.getBlob(0), Charsets.ISO_8859_1).contains("Glucose"))
        } }
        store.updateJob(job.id) { it.copy(state = HealthImportState.CANCELLED) }
        store.updateJob(job.id) { it.copy(state = HealthImportState.QUEUED) }
        store.savePage(job.id, page.copy(page = 2))
        assertEquals(HealthImportState.CANCELLED, store.job(job.id)!!.state); assertNull(store.page(job.id, 2))
        store.updateJob(job.id, restartCancelled = true) { it.copy(state = HealthImportState.QUEUED) }
        assertEquals(HealthImportState.QUEUED, store.job(job.id)!!.state)
    }
    @Test fun indexedTaskPagingAndRecoveryCanReachMoreThanOneHundredImports() = fixture { _, _, store ->
        repeat(125) { store.createJob(HealthImportJob(id(), "content://test/$it", 1)) }
        val ids = mutableListOf<String>(); var before: Pair<Long, String>? = null
        do { val page = store.jobs(before); ids += page.map { it.id }; before = if (page.size == 30) page.last().let { it.createdAt to it.id } else null } while (before != null)
        assertEquals(125, ids.size); assertEquals(125, ids.distinct().size)
        val first = store.pendingJobs(); assertEquals(100, first.size)
        val second = store.pendingJobs(first.last().let { it.createdAt to it.id }); assertEquals(25, second.size)
        assertEquals(125, (first + second).map { it.id }.distinct().size)
    }
    @Test fun originalLibraryPagingDoesNotLoseEqualTimeEntries() = fixture { _, _, store ->
        repeat(35) { import(store, byteArrayOf(it.toByte(), 42)) }
        val first = store.originals(); assertEquals(30, first.size)
        val next = store.originals(first.last().let { it.importedAt to it.id }); assertEquals(5, next.size)
        assertEquals(35, (first + next).map { it.id }.distinct().size)
    }
    @Test fun stoppedWorkersRemainResumableButCancelledJobsStayCancelled() = fixture { _, _, store ->
        val job = HealthImportJob(id(), "content://test/source", 1); store.createJob(job)
        assertEquals(HealthImportOutcome.RETRY, HealthImportPipeline(context).run(store, job.id) { true })
        assertEquals(HealthImportState.QUEUED, store.job(job.id)!!.state)
        store.updateJob(job.id) { it.copy(state = HealthImportState.CANCELLED) }
        assertEquals(HealthImportOutcome.COMPLETE, HealthImportPipeline(context).run(store, job.id))
        assertEquals(HealthImportState.CANCELLED, store.job(job.id)!!.state)
        assertTrue(store.originals().isEmpty())
    }
    @Test fun completedPageResumesWithoutReopeningARevokedSourceOrRepeatingOcr() = fixture { _, _, store ->
        val job = HealthImportJob(id(), "content://missing/provider", 1, name = "report.png", mime = "image/png")
        store.createJob(job); val original = import(store, bytes(50), job.id)
        store.updateJob(job.id) { it.copy(originalId = original.id, pageCount = 1) }
        store.savePage(job.id, HealthOcrPage(1, 100, 100, listOf(HealthOcrLine("Glucose 5.6 mmol/L"))))
        assertEquals(HealthImportOutcome.COMPLETE, HealthImportPipeline(context).run(store, job.id))
        assertEquals(HealthImportState.REVIEW, store.job(job.id)!!.state); assertEquals(1, store.job(job.id)!!.nextPage)
    }
    @Test fun realLocalImageOcrProducesReviewSuggestionsWithoutWritingHealthRecords() = fixture { _, _, store ->
        val bitmap = Bitmap.createBitmap(1400, 600, Bitmap.Config.ARGB_8888)
        bitmap.eraseColor(Color.WHITE); drawReport(Canvas(bitmap))
        val payload = ByteArrayOutputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it); it.toByteArray() }
        bitmap.recycle()
        val original = store.importOriginal(id(), payload.inputStream(), "synthetic-report.png", "image/png", "file")
        HealthOcrEngine().use { engine ->
            val page = engine.image(store, original)
            assertTrue(page.lines.joinToString(" ") { it.text }.contains("Glucose", true))
            val drafts = HealthOcrCandidates.suggest(HealthImportJob(id(), "content://test/source", 1), original, page)
            assertTrue(drafts.any { it.metric == HealthMetric.GLUCOSE && it.values["glucose"] == "5.6" })
            assertTrue(drafts.all { !it.evidence!!.confirmed && it.measuredAt == 0L })
        }
    }
    @Test fun encryptedMultipagePdfActuallyRendersAndResumesFromItsCheckpoint() = fixture { _, _, store ->
        val bytes = ByteArrayOutputStream().use { output ->
            val document = PdfDocument()
            try {
                repeat(2) { index -> val page = document.startPage(PdfDocument.PageInfo.Builder(1400, 600, index + 1).create())
                    page.canvas.drawColor(Color.WHITE); drawReport(page.canvas); document.finishPage(page) }
                document.writeTo(output)
            } finally { document.close() }
            output.toByteArray()
        }
        val original = store.importOriginal(id(), bytes.inputStream(), "synthetic.pdf", "application/pdf", "file")
        HealthOcrEngine().use { engine ->
            val pages = mutableListOf<HealthOcrPage>(); var count = 0
            engine.pdf(store, original, 1, {}, { count = it }, pages::add)
            assertEquals(2, count); assertEquals(listOf(2), pages.map { it.page })
            assertTrue(pages.single().lines.any { it.text.contains("Glucose", true) })
        }
    }
    @Test fun realImportPipelineArchivesUnsupportedFilesWithoutPretendingToExtractThem() = fixture { _, _, store ->
        val token = id(); val file = HealthCaptureFiles.file(context, token)
        try {
            file.parentFile!!.mkdirs(); file.writeBytes(bytes(400))
            val uri = FileProvider.getUriForFile(context, "${context.packageName}.files", file)
            val job = HealthImportJob(id(), uri.toString(), 1, name = "records.csv", mime = "text/csv")
            store.createJob(job)
            assertEquals(HealthImportOutcome.COMPLETE, HealthImportPipeline(context).run(store, job.id))
            val saved = store.job(job.id)!!
            assertEquals(HealthImportState.ORIGINAL_ONLY, saved.state); assertEquals(0, saved.nextPage)
            assertArrayEquals(bytes(400), restored(store, store.original(saved.originalId)!!))
        } finally { file.delete() }
    }
    @Test fun realPhotoPipelineKeepsByteFaithfulOriginalBeforeRemovingTheCameraStagingFile() = fixture { _, _, store ->
        val token = id(); val file = HealthCaptureFiles.file(context, token)
        try {
            file.parentFile!!.mkdirs()
            val bitmap = Bitmap.createBitmap(1400, 600, Bitmap.Config.ARGB_8888)
            bitmap.eraseColor(Color.WHITE); drawReport(Canvas(bitmap))
            file.outputStream().use { bitmap.compress(Bitmap.CompressFormat.JPEG, 95, it) }; bitmap.recycle()
            val payload = file.readBytes()
            val uri = FileProvider.getUriForFile(context, "${context.packageName}.files", file)
            val job = HealthImportJob(token, uri.toString(), System.currentTimeMillis(), cameraToken = token,
                name = "synthetic-photo.jpg", mime = "image/jpeg")
            store.createJob(job)
            assertEquals(HealthImportOutcome.COMPLETE, HealthImportPipeline(context).run(store, job.id))
            assertFalse(file.exists()); assertEquals(HealthImportState.REVIEW, store.job(job.id)!!.state)
            val original = store.originalForJob(job.id)!!
            assertEquals("camera", original.source); assertArrayEquals(payload, restored(store, original))
            assertTrue(store.page(job.id, 1)!!.lines.any { it.text.contains("Glucose", true) })
        } finally { file.delete() }
    }
    private fun drawReport(canvas: Canvas) {
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.BLACK; textSize = 70f }
        canvas.drawText("Glucose 5.6 mmol/L", 60f, 130f, paint)
        canvas.drawText("Total cholesterol 4.8 mmol/L", 60f, 280f, paint)
        canvas.drawText("Hemoglobin 142 g/L", 60f, 430f, paint)
    }
}

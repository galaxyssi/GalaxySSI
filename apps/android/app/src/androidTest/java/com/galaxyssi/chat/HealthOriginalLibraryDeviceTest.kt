package com.galaxyssi.chat

import android.content.ContentValues
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.pdf.PdfDocument
import androidx.test.platform.app.InstrumentationRegistry
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.RandomAccessFile
import java.util.UUID
import java.util.zip.ZipInputStream
import org.junit.Assert.*
import org.junit.Test

class HealthOriginalLibraryDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private fun id() = UUID.randomUUID().toString()
    private fun fixture(test: (String, File, File, HealthOriginalStore, HealthOriginalLibraryStore) -> Unit) {
        val name = "health-library-test-${id()}.db"; val root = File(context.cacheDir, "health-library-test-${id()}"); val exports = File(context.cacheDir, "health-export-test-${id()}")
        try { HealthOriginalStore(context, name, root).use { originals -> test(name, root, exports, originals, HealthOriginalLibraryStore(context, originals, exports)) } }
        finally { context.deleteDatabase(name); root.deleteRecursively(); exports.deleteRecursively() }
    }
    private fun import(store: HealthOriginalStore, n: Int, name: String = "report-$n.bin", mime: String = "application/octet-stream") =
        store.importOriginal(id(), "private health fixture $n".toByteArray().inputStream(), name, mime, "file")
    private fun select(library: HealthOriginalLibraryStore, originals: List<HealthOriginal>): HealthOriginalExportSession {
        val session = library.createSelection(); originals.chunked(30).forEach { library.select(session.id, it.map { it.id }, true) }; return library.prepare(session.id)
    }
    private fun zip(library: HealthOriginalLibraryStore, session: HealthOriginalExportSession): Map<String, ByteArray> {
        val output = ByteArrayOutputStream(); HealthOriginalArchive.save(library, session, output)
        return ZipInputStream(output.toByteArray().inputStream()).use { input -> buildMap {
            while (true) { val entry = input.nextEntry ?: break; put(entry.name, input.readBytes()); input.closeEntry() }
        } }
    }
    @Test fun indexedKindAndDatePagesKeepNinetyFiveOriginalsWithoutDuplication(): Unit = fixture { _, _, _, originals, _ ->
        repeat(95) { import(originals, it, "report-$it.pdf", if (it % 2 == 0) "application/pdf" else "image/jpeg") }
        var cursor: Pair<Long, String>? = null; val seen = linkedSetOf<String>()
        do { val page = originals.library(HealthLibraryFilter(), cursor); assertTrue(page.originals.size <= 30); page.originals.forEach { assertTrue(seen.add(it.id)) }; cursor = page.next } while (cursor != null)
        assertEquals(95, seen.size)
        var pdf = 0; cursor = null
        do { val page = originals.library(HealthLibraryFilter(HealthOriginalKind.PDF), cursor); pdf += page.originals.size; assertTrue(page.originals.all { it.mime == "application/pdf" }); cursor = page.next } while (cursor != null)
        assertEquals(48, pdf)
    }
    @Test fun dateFilteringUsesHalfOpenBoundsAndDoesNotDecryptOutsideRows(): Unit = fixture { _, _, _, originals, _ ->
        val file = import(originals, 1); val time = file.importedAt
        assertEquals(file.id, originals.library(HealthLibraryFilter(from = time, until = time + 1)).originals.single().id)
        assertTrue(originals.library(HealthLibraryFilter(from = time + 1)).originals.isEmpty())
        originals.libraryDatabase.update("originals", ContentValues().apply { put("payload", byteArrayOf(0, 1)) }, "id=?", arrayOf(file.id))
        assertTrue(originals.library(HealthLibraryFilter(from = time + 1)).originals.isEmpty())
        assertTrue(runCatching { originals.library(HealthLibraryFilter()) }.isFailure)
    }
    @Test fun alteredTypeIndexCannotSilentlyRelabelEncryptedMetadata(): Unit = fixture { _, _, _, originals, _ ->
        val file = import(originals, 1)
        originals.libraryDatabase.update("originals", ContentValues().apply { put("kind", "PDF") }, "id=?", arrayOf(file.id))
        assertTrue(runCatching { originals.library(HealthLibraryFilter(HealthOriginalKind.PDF)) }.isFailure)
    }
    @Test fun selectionsAreIdempotentScopedAndDurableWithoutBundleArrays(): Unit = fixture { name, root, exports, originals, library ->
        val files = (0..64).map { import(originals, it) }; val a = library.createSelection(); val b = library.createSelection()
        files.chunked(30).forEach { library.select(a.id, it.map { it.id }, true) }; library.select(a.id, listOf(files[0].id), true)
        assertEquals(65L, library.count(a.id)); assertEquals(0L, library.count(b.id)); assertEquals(30, library.selected(a.id, files.take(30)).size)
        HealthOriginalStore(context, name, root).use { reopened -> assertEquals(65L, HealthOriginalLibraryStore(context, reopened, exports).count(a.id)) }
        library.select(a.id, listOf(files[0].id), false); assertEquals(64L, library.count(a.id)); library.clearSelection(a.id); assertEquals(0L, library.count(a.id))
    }
    @Test fun emptyAndMissingSelectionsCannotQueueAnArchive(): Unit = fixture { _, _, _, originals, library ->
        assertTrue(runCatching { library.prepare(library.createSelection().id) }.isFailure)
        val original = import(originals, 1); originals.removeOriginalBytes(original)
        val s = select(library, listOf(original)); assertEquals(1L, s.missing); assertTrue(runCatching { library.queue(s.id) }.isFailure)
    }
    @Test fun frozenPreviewIsPagedAndCannotBeMutatedBehindTheConfirmation(): Unit = fixture { _, _, _, originals, library ->
        val files = (0..64).map { import(originals, it) }; val s = select(library, files)
        assertEquals(65L, s.count); assertEquals(files.sumOf { it.size }, s.sourceBytes)
        val seen = linkedSetOf<String>(); var after = ""
        do { val page = library.items(s.id, after); page.take(30).forEach { assertTrue(seen.add(it.id)) }; after = if (page.size > 30) page[29].id else "" } while (after.isNotBlank())
        assertEquals(65, seen.size); assertTrue(runCatching { library.select(s.id, listOf(files[0].id), false) }.isFailure)
        library.edit(s.id); library.select(s.id, listOf(files[0].id), false); assertEquals(64L, library.prepare(s.id).count)
    }
    @Test fun encryptedGeneratedArchivePreservesEveryOriginalAndAStreamingManifest(): Unit = fixture { name, root, exports, originals, library ->
        val files = (0..34).map { import(originals, it, "same-name.heif", "image/heif") }; val s = select(library, files); library.queue(s.id)
        assertEquals(HealthOriginalArchiveOutcome.COMPLETE, HealthOriginalArchive.generate(originals, library, s.id))
        val generated = library.session(s.id)!!; assertEquals(HealthOriginalExportState.GENERATED, generated.state)
        assertFalse(String(library.file(generated).readBytes(), Charsets.ISO_8859_1).contains("private health fixture"))
        HealthOriginalStore(context, name, root).use { reopened ->
            val restored = HealthOriginalLibraryStore(context, reopened, exports); val archive = zip(restored, restored.session(s.id)!!)
            assertEquals(36, archive.size)
            files.forEachIndexed { i, file -> assertArrayEquals("private health fixture $i".toByteArray(), archive[HealthOriginalArchiveNames.entry(file)]) }
            val manifest = archive.getValue("manifest.ndjson").toString(Charsets.UTF_8).trim().lines()
            assertEquals(36, manifest.size); assertFalse(org.json.JSONObject(manifest.first()).getBoolean("contains_measurements"))
            assertEquals(files.map { it.sha256 }.toSet(), manifest.drop(1).map { org.json.JSONObject(it).getString("sha256") }.toSet())
        }
        assertEquals(HealthOriginalArchiveOutcome.COMPLETE, HealthOriginalArchive.generate(originals, library, s.id)); assertEquals(generated.attempt, library.session(s.id)!!.attempt)
    }
    @Test fun generatedAndSavedAreDistinctAndReopeningDoesNotPretendToSave(): Unit = fixture { _, _, _, originals, library ->
        val s = select(library, listOf(import(originals, 0))); library.queue(s.id); HealthOriginalArchive.generate(originals, library, s.id)
        val ready = library.session(s.id)!!; zip(library, ready); assertEquals(HealthOriginalExportState.GENERATED, library.session(s.id)!!.state)
        val output = ByteArrayOutputStream()
        val saved = HealthOriginalArchive.saveVerified(library, ready, { output }, { output.toByteArray().inputStream() }, { fail("Unexpected cleanup") })
        assertEquals(HealthOriginalExportState.SAVED, library.session(s.id)!!.state)
        assertTrue(saved.verifiedSaveAt > 0)
        assertTrue(saved.pendingSave.isEmpty())
    }
    @Test fun truncatedDestinationNeverCreatesAReceiptAndTheGeneratedZipCanBeRetried(): Unit = fixture { _, _, _, originals, library ->
        val s = select(library, listOf(import(originals, 0)))
        library.queue(s.id)
        assertEquals(HealthOriginalArchiveOutcome.COMPLETE, HealthOriginalArchive.generate(originals, library, s.id))
        val ready = library.session(s.id)!!
        val output = ByteArrayOutputStream()
        var cleanup = false
        assertTrue(runCatching { HealthOriginalArchive.saveVerified(library, ready, { output },
            { output.toByteArray().copyOf(output.size() - 1).inputStream() }, { cleanup = true }) }.isFailure)
        assertTrue(cleanup)
        val failed = library.session(s.id)!!
        assertEquals(HealthOriginalExportState.GENERATED, failed.state)
        assertTrue(failed.saveFailed)
        assertEquals(0L, failed.verifiedSaveAt)
        assertTrue(library.file(failed).isFile)
        output.reset()
        val saved = HealthOriginalArchive.saveVerified(library, failed, { output },
            { output.toByteArray().inputStream() }, { fail("Unexpected cleanup") })
        assertFalse(saved.saveFailed)
        assertTrue(saved.verifiedSaveAt > 0)
        assertArrayEquals(library.input(saved).use { it.readBytes() }, output.toByteArray())
        assertTrue(runCatching { HealthOriginalArchive.saveVerified(library, saved, { ByteArrayOutputStream() },
            { ByteArray(0).inputStream() }, {}) }.isFailure)
        val failedResave = library.session(s.id)!!
        assertEquals(HealthOriginalExportState.SAVED, failedResave.state)
        assertEquals(saved.verifiedSaveAt, failedResave.verifiedSaveAt)
        assertTrue(failedResave.saveFailed)
    }
    @Test fun interruptedAndStaleSaveAttemptsCannotInventAReceipt(): Unit = fixture { name, root, exports, originals, library ->
        val s = select(library, listOf(import(originals, 0)))
        library.queue(s.id)
        assertEquals(HealthOriginalArchiveOutcome.COMPLETE, HealthOriginalArchive.generate(originals, library, s.id))
        val ready = library.session(s.id)!!
        val stale = library.beginSave(ready)
        HealthOriginalStore(context, name, root).use { reopened ->
            val store = HealthOriginalLibraryStore(context, reopened, exports)
            val interrupted = store.history().single()
            assertEquals(stale, interrupted.pendingSave)
            assertEquals(HealthOriginalExportState.GENERATED, interrupted.state)
            assertEquals(0L, interrupted.verifiedSaveAt)
            assertFalse(HealthOriginalArchive.isSaving(s.id))
            val retry = store.beginSave(interrupted)
            assertNotEquals(retry, stale)
            assertTrue(runCatching { store.finishSave(interrupted, stale, verified = true) }.isFailure)
            assertEquals(retry, store.session(s.id)!!.pendingSave)
            val output = ByteArrayOutputStream()
            val done = HealthOriginalArchive.saveVerified(store, interrupted, { output },
                { output.toByteArray().inputStream() }, { fail("Unexpected cleanup") })
            assertEquals(done, store.history().single())
            assertEquals(HealthOriginalExportState.SAVED, done.state)
        }
    }
    @Test fun historyIsIndexedAndPagedAcrossEqualTimestampsWithoutShowingUnsubmittedDrafts(): Unit = fixture { name, root, exports, originals, library ->
        val original = import(originals, 0)
        val time = 1_790_000_000_000L
        val sessions = (1..67).map { select(library, listOf(original)).copy(createdAt = time) }
        sessions.forEach { session ->
            originals.libraryDatabase.update("library_exports", ContentValues().apply {
                put("created_at", time)
                put("payload", originals.libraryPack("export", session.id, session.json()))
            }, "id=?", arrayOf(session.id))
        }
        library.createSelection()
        val first = library.history()
        assertEquals(31, first.size)
        val second = library.history(first[29].let { it.createdAt to it.id })
        val third = library.history(second[29].let { it.createdAt to it.id })
        assertEquals(sessions.sortedByDescending { it.id }, first.take(30) + second.take(30) + third)
        assertTrue(originals.libraryDatabase.rawQuery("EXPLAIN QUERY PLAN SELECT id FROM library_exports WHERE state<>'SELECTING' " +
            "ORDER BY created_at DESC,id DESC LIMIT 31", null).use { cursor ->
            generateSequence { if (cursor.moveToNext()) cursor.getString(3) else null }.any { it.contains("library_export_history") }
        })
        originals.libraryDatabase.execSQL("DROP INDEX library_export_history")
        originals.libraryDatabase.version = 3
        HealthOriginalStore(context, name, root).use { reopened ->
            val upgraded = HealthOriginalLibraryStore(context, reopened, exports)
            assertEquals(4, reopened.libraryDatabase.version)
            assertEquals(first, upgraded.history())
            assertTrue(reopened.libraryDatabase.rawQuery("SELECT 1 FROM sqlite_master WHERE name='library_export_history'", null).use { it.moveToFirst() })
        }
        val legacy = sessions.first().copy(state = HealthOriginalExportState.SAVED).json().apply {
            remove("pending_save"); remove("verified_save_at"); remove("save_failed")
        }
        assertEquals(R.string.health_library_legacy_save, HealthOriginalExportSession.from(legacy).title())
    }
    @Test fun sharedArchiveUpgradeKeepsHistoryAndItsVerifiedReceipt(): Unit = fixture { name, root, exports, originals, library ->
        val s = select(library, listOf(import(originals, 0)))
        library.queue(s.id)
        assertEquals(HealthOriginalArchiveOutcome.COMPLETE, HealthOriginalArchive.generate(originals, library, s.id))
        val output = ByteArrayOutputStream()
        val saved = HealthOriginalArchive.saveVerified(library, library.session(s.id)!!, { output },
            { output.toByteArray().inputStream() }, { fail("Unexpected cleanup") })
        val sharedName = "$name-shared.db"
        try {
            HealthRecordStore(context, sharedName).use { records ->
                HealthOriginalStore(context, name, root, records).use { migrated ->
                    assertEquals(saved, HealthOriginalLibraryStore(context, migrated, exports).history().single())
                    records.tableDatabase.execSQL("DROP INDEX library_export_history")
                    records.tableDatabase.version = 8
                }
            }
            HealthRecordStore(context, sharedName).use { records ->
                HealthOriginalStore(context, name, root, records).use { migrated ->
                    assertEquals(HealthRecordStore.SCHEMA_VERSION, records.tableDatabase.version)
                    val history = HealthOriginalLibraryStore(context, migrated, exports)
                    assertEquals(saved, history.history().single())
                    assertTrue(records.tableDatabase.rawQuery("SELECT 1 FROM sqlite_master WHERE name='library_export_history'", null).use { it.moveToFirst() })
                }
            }
        } finally { context.deleteDatabase(sharedName) }
    }
    @Test fun missingSourceAfterConfirmationFailsInsteadOfProducingAPartialSuccess(): Unit = fixture { _, _, _, originals, library ->
        val file = import(originals, 0); val s = select(library, listOf(file)); library.queue(s.id); originals.removeOriginalBytes(file)
        assertEquals(HealthOriginalArchiveOutcome.FAILED, HealthOriginalArchive.generate(originals, library, s.id))
        val failed = library.session(s.id)!!; assertEquals("original_missing", failed.error); assertFalse(library.file(failed).exists())
    }
    @Test fun reimportedSourceRequiresNewConfirmationButRetainsOriginalIdentity(): Unit = fixture { _, _, _, originals, library ->
        val file = import(originals, 0); val s = select(library, listOf(file)); originals.removeOriginalBytes(file)
        val repaired = import(originals, 0); assertEquals(file.id, repaired.id); assertNotEquals(file.streamId, repaired.streamId)
        library.queue(s.id); assertEquals(HealthOriginalArchiveOutcome.FAILED, HealthOriginalArchive.generate(originals, library, s.id)); assertEquals("original_changed", library.session(s.id)!!.error)
        library.edit(s.id); library.prepare(s.id); library.queue(s.id); assertEquals(HealthOriginalArchiveOutcome.COMPLETE, HealthOriginalArchive.generate(originals, library, s.id))
    }
    @Test fun corruptedOriginalFailsWithoutDeletingOrOverwritingSourceRecords(): Unit = fixture { _, root, _, originals, library ->
        val file = import(originals, 0); val s = select(library, listOf(file)); library.queue(s.id)
        RandomAccessFile(File(root, file.relativePath), "rw").use { it.seek(45); val byte = it.read(); it.seek(45); it.write(byte xor 1) }
        assertEquals(HealthOriginalArchiveOutcome.FAILED, HealthOriginalArchive.generate(originals, library, s.id)); assertNotNull(originals.original(file.id)); assertTrue(originals.present(file))
        assertEquals(1L, library.session(s.id)!!.count)
    }
    @Test fun stoppedGenerationResumesFromTheFrozenPlanWithANewAuthenticatedAttempt(): Unit = fixture { _, _, exports, originals, library ->
        val s = select(library, (0..2).map { import(originals, it) }); library.queue(s.id)
        assertEquals(HealthOriginalArchiveOutcome.RETRY, HealthOriginalArchive.generate(originals, library, s.id) { true })
        val interrupted = library.session(s.id)!!; assertEquals(HealthOriginalExportState.QUEUED, interrupted.state)
        assertEquals(HealthOriginalArchiveOutcome.COMPLETE, HealthOriginalArchive.generate(originals, library, s.id)); val ready = library.session(s.id)!!
        assertNotEquals(interrupted.attempt, ready.attempt); assertEquals(1, exports.listFiles().orEmpty().size); assertEquals(4, zip(library, ready).size)
    }
    @Test fun cancellationCannotBeRevivedByAnAlreadyQueuedWorker(): Unit = fixture { _, _, exports, originals, library ->
        val s = select(library, listOf(import(originals, 0))); library.queue(s.id); library.cancel(s.id)
        assertEquals(HealthOriginalArchiveOutcome.COMPLETE, HealthOriginalArchive.generate(originals, library, s.id)); assertEquals(HealthOriginalExportState.CANCELLED, library.session(s.id)!!.state)
        assertTrue(exports.listFiles().orEmpty().isEmpty())
    }
    @Test fun tamperedGeneratedCiphertextCannotBeMarkedSaved(): Unit = fixture { _, _, _, originals, library ->
        val s = select(library, listOf(import(originals, 0))); library.queue(s.id); HealthOriginalArchive.generate(originals, library, s.id); val ready = library.session(s.id)!!
        RandomAccessFile(library.file(ready), "rw").use { it.setLength(it.length() - 1) }
        assertTrue(runCatching { zip(library, ready) }.isFailure); assertEquals(HealthOriginalExportState.GENERATED, library.session(s.id)!!.state)
    }
    @Test fun selectedManifestPayloadDoesNotContainPlaintextFilenames(): Unit = fixture { _, _, _, originals, library ->
        val s = select(library, listOf(import(originals, 0, "private-diagnosis-report.pdf", "application/pdf")))
        originals.libraryDatabase.rawQuery("SELECT snapshot FROM library_export_items WHERE session_id=?", arrayOf(s.id)).use { it.moveToFirst(); assertFalse(String(it.getBlob(0), Charsets.ISO_8859_1).contains("private-diagnosis")) }
    }
    @Test fun imageThumbnailsAreBoundedMutableAndClearableWithoutPlaintextFiles(): Unit = fixture { _, root, _, originals, _ ->
        val bitmap = Bitmap.createBitmap(600, 300, Bitmap.Config.ARGB_8888).apply { eraseColor(Color.MAGENTA) }
        val bytes = ByteArrayOutputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it); it.toByteArray() }; bitmap.recycle()
        val original = originals.importOriginal(id(), bytes.inputStream(), "photo.png", "image/png", "file")
        val thumbnail = requireNotNull(HealthOriginalThumbnail.load(originals, original)); assertTrue(thumbnail.width <= 192 && thumbnail.height <= 192); assertTrue(thumbnail.isMutable)
        assertEquals(Color.MAGENTA, thumbnail.getPixel(thumbnail.width / 2, thumbnail.height / 2)); HealthOriginalThumbnail.clear(thumbnail); assertTrue(thumbnail.isRecycled)
        assertTrue(root.walkTopDown().filter { it.isFile }.all { it.extension == "ghealth" })
    }
    @Test fun pdfFirstPageThumbnailUsesAuthenticatedSeekableInput(): Unit = fixture { _, _, _, originals, _ ->
        val bytes = ByteArrayOutputStream().use { output ->
            val pdf = PdfDocument()
            try { val page = pdf.startPage(PdfDocument.PageInfo.Builder(600, 800, 1).create()); page.canvas.drawColor(Color.CYAN); pdf.finishPage(page); pdf.writeTo(output) }
            finally { pdf.close() }
            output.toByteArray()
        }
        val original = originals.importOriginal(id(), bytes.inputStream(), "report.pdf", "application/pdf", "file")
        val thumbnail = requireNotNull(HealthOriginalThumbnail.load(originals, original)); assertTrue(thumbnail.width <= 192 && thumbnail.height <= 192)
        assertEquals(Color.CYAN, thumbnail.getPixel(thumbnail.width / 2, thumbnail.height / 2)); HealthOriginalThumbnail.clear(thumbnail)
    }
    @Test fun unknownFilesHaveNoInventedVisualThumbnail(): Unit = fixture { _, _, _, originals, _ -> assertNull(HealthOriginalThumbnail.load(originals, import(originals, 0))) }
    @Test fun retryDispatchCannotBeConsumedByThePreviousFinishingWorker(): Unit = fixture { _, _, _, originals, library ->
        val s = select(library, listOf(import(originals, 0))); val first = library.queue(s.id)
        val (attempt, key) = library.claim(s.id, first.dispatch)!!; key.fill(0); library.failed(attempt, "archive_failed")
        val second = library.queue(s.id); assertNotEquals(first.dispatch, second.dispatch)
        assertNull(library.claim(s.id, first.dispatch)); assertEquals(HealthOriginalExportState.QUEUED, library.session(s.id)!!.state)
        assertEquals(HealthOriginalArchiveOutcome.COMPLETE, HealthOriginalArchive.generate(originals, library, s.id, second.dispatch))
    }
    @Test fun failureFromAnOldDispatchCannotStopANewRetry(): Unit = fixture { _, _, _, originals, library ->
        val s = select(library, listOf(import(originals, 0))); val first = library.queue(s.id)
        library.cannotStart(s.id, first.dispatch); assertEquals(HealthOriginalExportState.FAILED, library.session(s.id)!!.state)
        val second = library.queue(s.id); library.cannotStart(s.id, first.dispatch)
        assertEquals(second.dispatch, library.session(s.id)!!.dispatch); assertEquals(HealthOriginalExportState.QUEUED, library.session(s.id)!!.state)
    }
    @Test fun multiSegmentCiphertextIsByteFaithfulAndRejectsMidstreamTampering(): Unit = fixture { _, _, _, originals, library ->
        val bytes = ByteArray(2 * 1024 * 1024 + 113).also { java.util.Random(19).nextBytes(it) }
        val original = originals.importOriginal(id(), bytes.inputStream(), "large.bin", "application/octet-stream", "file")
        val s = select(library, listOf(original)); library.queue(s.id); HealthOriginalArchive.generate(originals, library, s.id); val ready = library.session(s.id)!!
        assertTrue(library.file(ready).length() > 1024 * 1024); assertArrayEquals(bytes, zip(library, ready).getValue(HealthOriginalArchiveNames.entry(original)))
        RandomAccessFile(library.file(ready), "rw").use { it.seek(65_580); val value = it.read(); it.seek(65_580); it.write(value xor 1) }
        assertTrue(runCatching { zip(library, ready) }.isFailure); assertEquals(HealthOriginalExportState.GENERATED, library.session(s.id)!!.state)
    }
    @Test fun abandonedAttemptIsRecoveredAfterCatalogReopenWithoutAppendingToItsPartial(): Unit = fixture { name, root, exports, originals, library ->
        val s = select(library, listOf(import(originals, 1))); library.queue(s.id)
        val (abandoned, key) = library.claim(s.id)!!; key.fill(0)
        val partial = library.file(abandoned, true); partial.parentFile!!.mkdirs(); partial.writeBytes(byteArrayOf(1, 2, 3))
        HealthOriginalStore(context, name, root).use { reopened ->
            val recovered = HealthOriginalLibraryStore(context, reopened, exports); assertTrue(s.id in recovered.active())
            assertEquals(HealthOriginalArchiveOutcome.COMPLETE, HealthOriginalArchive.generate(reopened, recovered, s.id))
            val ready = recovered.session(s.id)!!; assertNotEquals(abandoned.attempt, ready.attempt); assertEquals(2, zip(recovered, ready).size)
            assertFalse(partial.exists()); assertFalse(s.id in recovered.active())
        }
    }
    @Test fun failedDestinationCopyKeepsGeneratedArtifactAvailableForExplicitRetry(): Unit = fixture { _, _, _, originals, library ->
        val s = select(library, listOf(import(originals, 1))); library.queue(s.id); HealthOriginalArchive.generate(originals, library, s.id); val ready = library.session(s.id)!!
        val broken = object : java.io.OutputStream() { override fun write(value: Int) { throw java.io.IOException("isolated destination failure") } }
        assertTrue(runCatching { HealthOriginalArchive.save(library, ready, broken) }.isFailure)
        assertEquals(HealthOriginalExportState.GENERATED, library.session(s.id)!!.state); assertTrue(library.file(ready).isFile)
        assertEquals(2, zip(library, ready).size)
    }
    @Test fun unicodeLongNamesRetainOriginalFormatAndExactBytesInTheZip(): Unit = fixture { _, _, _, originals, library ->
        val file = import(originals, 7, "a".repeat(174) + "\ud83d\ude00" + "b".repeat(12) + ".heif", "image/heif")
        val s = select(library, listOf(file)); library.queue(s.id); HealthOriginalArchive.generate(originals, library, s.id)
        val archive = zip(library, library.session(s.id)!!); val entry = archive.keys.single { it.startsWith("originals/") }
        assertTrue(entry.endsWith(".heif")); assertArrayEquals("private health fixture 7".toByteArray(), archive[entry])
    }
    @Test fun versionTwoMigrationPreservesOriginalsAndBackfillsIndexedKinds() {
        val name = "health-library-migration-${id()}.db"; val root = File(context.cacheDir, "health-library-migration-${id()}")
        try {
            lateinit var saved: HealthOriginal
            HealthOriginalStore(context, name, root).use { saved = import(it, 1, "source.csv", "text/csv") }
            context.openOrCreateDatabase(name, 0, null).use { db ->
                db.execSQL("DROP TABLE library_export_items"); db.execSQL("DROP TABLE library_exports")
                db.execSQL("CREATE TABLE originals_legacy(id TEXT PRIMARY KEY,imported_at INTEGER NOT NULL,digest_token TEXT UNIQUE NOT NULL,payload BLOB NOT NULL,key_payload BLOB NOT NULL)")
                db.execSQL("INSERT INTO originals_legacy SELECT id,imported_at,digest_token,payload,key_payload FROM originals")
                db.execSQL("DROP TABLE originals"); db.execSQL("ALTER TABLE originals_legacy RENAME TO originals")
                db.execSQL("CREATE INDEX original_page ON originals(imported_at DESC,id DESC)"); db.version = 2
            }
            HealthOriginalStore(context, name, root).use { upgraded ->
                assertEquals(saved, upgraded.library(HealthLibraryFilter(HealthOriginalKind.TABLE)).originals.single()); assertEquals(4, upgraded.libraryDatabase.version)
                assertEquals(saved, upgraded.original(saved.id)); assertEquals(0L, HealthOriginalLibraryStore(context, upgraded).count(id()))
            }
        } finally { context.deleteDatabase(name); root.deleteRecursively() }
    }
}

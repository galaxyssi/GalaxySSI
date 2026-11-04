package com.galaxyssi.chat

import android.content.ContentValues
import androidx.core.content.FileProvider
import androidx.test.platform.app.InstrumentationRegistry
import com.google.crypto.tink.subtle.AesGcmHkdfStreaming
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.OutputStream
import java.io.RandomAccessFile
import java.util.UUID
import org.apache.commons.compress.archivers.zip.ZipFile
import org.apache.commons.compress.utils.SeekableInMemoryByteChannel
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class HealthRecordExportDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val time = 1_790_000_000_000L
    private fun id() = UUID.randomUUID().toString()
    private data class Fixture(val recordsName: String, val exportsName: String, val root: File,
        val records: HealthRecordStore, val originals: HealthOriginalStore, val exports: HealthRecordExportStore)
    private fun fixture(test: (Fixture) -> Unit) {
        val prefix = "health-record-export-test-${id()}"; val root = File(context.cacheDir, prefix)
        val names = listOf("$prefix-records.db", "$prefix-originals.db", "$prefix-exports.db")
        try {
            HealthRecordStore(context, names[0]).use { records -> HealthOriginalStore(context, names[1], File(root, "originals")).use { originals ->
                HealthRecordExportStore(context, names[2], File(root, "exports")).use { exports -> test(Fixture(names[0], names[2], root, records, originals, exports)) }
            } }
        } finally { names.forEach(context::deleteDatabase); root.deleteRecursively() }
    }
    private fun save(f: Fixture, n: Int = 1, metric: HealthMetric = HealthMetric.WEIGHT, evidence: HealthEvidence? = null, note: String = "") =
        (f.records.save(HealthDraft(metric, metric.requiredFields.associateWith { (n + 1).toString() }, metric.units.first(), time + n,
            note = note, evidence = evidence)) as HealthSaveResult.Saved).record
    private fun evidence(original: HealthOriginal, hash: String = original.sha256) = HealthEvidence(original.id, id(), "value", hash, 1, "private source text", confirmed = true)
    private fun prepare(f: Fixture, scope: HealthRecordExportScope = HealthRecordExportScope()): HealthRecordExportSession {
        val session = f.exports.create(scope)
        assertEquals(HealthOriginalArchiveOutcome.COMPLETE, HealthRecordExportPipeline.prepare(f.records, f.originals, f.exports, session.id, session.dispatch))
        return requireNotNull(f.exports.session(session.id))
    }
    private fun generate(f: Fixture, scope: HealthRecordExportScope = HealthRecordExportScope(format = HealthRecordExportFormat.JSON)): HealthRecordExportSession {
        val s = prepare(f, scope); assertEquals(HealthRecordExportState.REVIEW, s.state)
        val queued = f.exports.queue(s.id)
        assertEquals(HealthOriginalArchiveOutcome.COMPLETE, HealthRecordExportPipeline.generate(f.exports, s.id, queued.dispatch))
        return requireNotNull(f.exports.session(s.id)).also { assertEquals(HealthRecordExportState.GENERATED, it.state) }
    }
    private fun bytes(f: Fixture, s: HealthRecordExportSession): ByteArray = ByteArrayOutputStream().use { output ->
        assertEquals(s.artifactBytes, HealthRecordExportPipeline.save(f.exports, s, output)); output.toByteArray()
    }
    @Test fun ninetyFiveMixedRecordsAreSnapshottedInBoundedKeysetPages(): Unit = fixture { f ->
        val saved = (0..94).map { save(f, it, if (it % 2 == 0) HealthMetric.WEIGHT else HealthMetric.STEPS) }
        val s = prepare(f); assertEquals(95L, s.count); assertEquals(95L, s.rows); assertEquals(95L, s.scanned)
        val seen = linkedSetOf<String>(); var after = 0L
        do { val page = f.exports.items(s.id, after); assertTrue(page.size <= 31); page.take(30).forEach { assertTrue(seen.add(it.record.id)) }; after = if (page.size > 30) page[29].sequence else 0 } while (after > 0)
        assertEquals(saved.map { it.id }.toSet(), seen)
    }
    @Test fun metricDateAndOriginalFiltersExcludeUnrelatedCorruptRows(): Unit = fixture { f ->
        val original = f.originals.importOriginal(id(), "report".byteInputStream(), "report.bin", "application/octet-stream", "file")
        val wanted = save(f, 4, evidence = evidence(original)); val bad = save(f, 5, HealthMetric.STEPS)
        f.records.tableDatabase.update("observations", ContentValues().apply { put("payload", byteArrayOf(1, 2)) }, "id=?", arrayOf(bad.id))
        val s = prepare(f, HealthRecordExportScope(setOf(HealthMetric.WEIGHT), time + 4, time + 5, originalId = original.id))
        assertEquals(wanted.id, f.exports.items(s.id).single().record.id)
    }
    @Test fun deletedRecordsAndUnconfirmedDraftsNeverEnterAnExport(): Unit = fixture { f ->
        val removed = save(f); f.records.delete(removed.id, removed.revision)
        f.records.saveDraft(HealthDraft(HealthMetric.WEIGHT, mapOf("weight" to "55"), measuredAt = time))
        val s = prepare(f); assertEquals(HealthRecordExportState.FAILED, s.state); assertEquals("no_records", s.error)
    }
    @Test fun nonSelfRowsAreExcludedWithoutStoppingLaterPages(): Unit = fixture { f ->
        val rows = (0..34).map { save(f, it) }
        rows.drop(1).forEach { record ->
            val raw = record.copy(profileId = "other-person").json().toString().toByteArray()
            try { f.records.tableDatabase.update("observations", ContentValues().apply {
                put("payload", AgentStorageCipher.encryptBinary(raw, "${f.recordsName}|health|${record.id}|${record.revision}".toByteArray()))
            }, "id=?", arrayOf(record.id)) } finally { raw.fill(0) }
        }
        val s = prepare(f); assertEquals(35L, s.scanned); assertEquals(1L, s.count); assertEquals(rows.first().id, f.exports.items(s.id).single().record.id)
    }
    @Test fun previewFreezesTheRevisionEvenAfterTheLiveRecordIsEditedAndDeleted(): Unit = fixture { f ->
        val first = save(f, note = "initial"); val s = prepare(f, HealthRecordExportScope(format = HealthRecordExportFormat.JSON, annotations = true))
        val edited = (f.records.save(first.editable().copy(note = "later")) as HealthSaveResult.Saved).record; f.records.delete(edited.id, edited.revision)
        val q = f.exports.queue(s.id); HealthRecordExportPipeline.generate(f.exports, q.id, q.dispatch)
        val json = JSONObject(bytes(f, f.exports.session(s.id)!!).toString(Charsets.UTF_8)).getJSONArray("records").getJSONObject(0)
        assertEquals(first, HealthObservation.from(json)); assertNull(f.records.record(first.id))
    }
    @Test fun missingOriginalBytesDoNotBlockLinkedMeasurementExport(): Unit = fixture { f ->
        val original = f.originals.importOriginal(id(), "report".byteInputStream(), "report.bin", "application/octet-stream", "file")
        save(f, evidence = evidence(original)); f.originals.removeOriginalBytes(original)
        val ready = generate(f, HealthRecordExportScope(originalId = original.id, format = HealthRecordExportFormat.JSON))
        assertEquals(1L, ready.sourceWarnings)
        assertEquals("MISSING", JSONObject(bytes(f, ready).toString(Charsets.UTF_8)).getJSONArray("records").getJSONObject(0).getString("source_status_at_preview"))
    }
    @Test fun mismatchedSourceHashesAreDisclosedInsteadOfDeletingData(): Unit = fixture { f ->
        val original = f.originals.importOriginal(id(), "report".byteInputStream(), "report.bin", "application/octet-stream", "file")
        save(f, evidence = evidence(original, "f".repeat(64)))
        val s = prepare(f); assertEquals(1L, s.sourceWarnings); assertEquals(HealthExportSourceStatus.HASH_MISMATCH, f.exports.items(s.id).single().sourceStatus)
    }
    @Test fun previewDetectsAnObservationMutationDuringStreaming(): Unit = fixture { f ->
        repeat(35) { save(f, it) }; val s = f.exports.create(HealthRecordExportScope()); var changed = false
        val result = HealthRecordExportPipeline.prepare(f.records, f.originals, f.exports, s.id, s.dispatch) {
            if (!changed && f.exports.session(s.id)!!.count >= 30) { changed = true; save(f, 100) }; false
        }
        assertEquals(HealthOriginalArchiveOutcome.FAILED, result); assertEquals("records_changed", f.exports.session(s.id)!!.error)
    }
    @Test fun stoppedPreparationCanRestartWithoutDuplicatingPartialSnapshotRows(): Unit = fixture { f ->
        repeat(35) { save(f, it) }; val s = f.exports.create(HealthRecordExportScope())
        assertEquals(HealthOriginalArchiveOutcome.RETRY, HealthRecordExportPipeline.prepare(f.records, f.originals, f.exports, s.id, s.dispatch) { f.exports.session(s.id)!!.count >= 30 })
        val attempt = f.exports.session(s.id)!!.attempt
        assertEquals(HealthOriginalArchiveOutcome.COMPLETE, HealthRecordExportPipeline.prepare(f.records, f.originals, f.exports, s.id, s.dispatch))
        assertEquals(35L, f.exports.session(s.id)!!.count); assertNotEquals(attempt, f.exports.session(s.id)!!.attempt)
    }
    @Test fun cancellationAndStaleDispatchesCannotReviveAnExport(): Unit = fixture { f ->
        save(f); val s = f.exports.create(HealthRecordExportScope()); f.exports.cancel(s.id)
        HealthRecordExportPipeline.prepare(f.records, f.originals, f.exports, s.id, s.dispatch); assertEquals(HealthRecordExportState.CANCELLED, f.exports.session(s.id)!!.state)
        val next = f.exports.retryPreparation(s.id); assertNull(f.exports.claimPrepare(s.id, s.dispatch))
        f.exports.externalFailure(s.id, s.dispatch, "old_failure"); assertEquals(next.dispatch, f.exports.session(s.id)!!.dispatch)
    }
    @Test fun aFailedGenerationRetryRejectsThePreviousWorkersDispatch(): Unit = fixture { f ->
        save(f); val q = f.exports.queue(prepare(f).id); val (active, key) = f.exports.claimGenerate(q.id, q.dispatch)!!; key.fill(0)
        f.exports.failed(active, "generation_failed"); val next = f.exports.queue(q.id)
        assertNull(f.exports.claimGenerate(q.id, q.dispatch)); f.exports.externalFailure(q.id, q.dispatch, "old_failure")
        assertEquals(next.dispatch, f.exports.session(q.id)!!.dispatch)
    }
    @Test fun generationInterruptionUsesANewKeyAndDeletesOnlyItsOwnAbandonedAttempt(): Unit = fixture { f ->
        save(f); val q = f.exports.queue(prepare(f).id)
        assertEquals(HealthOriginalArchiveOutcome.RETRY, HealthRecordExportPipeline.generate(f.exports, q.id, q.dispatch, stopped = { true }))
        val previous = f.exports.session(q.id)!!; val other = f.exports.artifacts.file(id(), id()).apply { parentFile!!.mkdirs(); writeBytes(byteArrayOf(1)) }
        val obsolete = f.exports.artifacts.file(q.id, previous.attempt).apply { writeBytes(byteArrayOf(1)) }
        assertEquals(HealthOriginalArchiveOutcome.COMPLETE, HealthRecordExportPipeline.generate(f.exports, q.id, q.dispatch))
        assertNotEquals(previous.attempt, f.exports.session(q.id)!!.attempt); assertFalse(obsolete.exists()); assertTrue(other.exists())
    }
    @Test fun encryptedSnapshotsAndArtifactsSurviveReopenWithoutPlaintextNotes(): Unit = fixture { f ->
        save(f, note = "private-export-marker"); val s = generate(f, HealthRecordExportScope(format = HealthRecordExportFormat.JSON, annotations = true))
        assertFalse(f.exports.artifacts.file(s.id, s.attempt).readBytes().toString(Charsets.ISO_8859_1).contains("private-export-marker"))
        context.openOrCreateDatabase(f.exportsName, 0, null).use { db -> db.rawQuery("SELECT payload FROM export_records", null).use { rows ->
            assertTrue(rows.moveToFirst()); assertFalse(rows.getBlob(0).toString(Charsets.ISO_8859_1).contains("private-export-marker"))
        } }
        HealthRecordExportStore(context, f.exportsName, File(f.root, "exports")).use { reopened ->
            val restored = reopened.session(s.id)!!; assertEquals(s, restored)
            ByteArrayOutputStream().use { output -> HealthRecordExportPipeline.save(reopened, restored, output); assertTrue(output.toString("UTF-8").contains("private-export-marker")) }
        }
    }
    @Test fun annotationsAreOmittedBeforeTheSnapshotIsPersistedUnlessExplicitlyEnabled(): Unit = fixture { f ->
        save(f, note = "not-selected"); val s = prepare(f); assertEquals("", f.exports.items(s.id).single().record.draft.note)
    }
    @Test fun csvGenerationOnAndroidPreservesComponentsAndGuardsFormulaLikeNotes(): Unit = fixture { f ->
        f.records.save(HealthDraft(HealthMetric.BLOOD_PRESSURE, mapOf("systolic" to "120", "diastolic" to "80", "pulse" to "64"), "mmHg", time, note = "=SUM(A1)"))
        val ready = generate(f, HealthRecordExportScope(format = HealthRecordExportFormat.CSV, annotations = true))
        val csv = bytes(f, ready).toString(Charsets.UTF_8)
        assertEquals('\uFEFF', csv.first()); assertTrue(csv.contains("\"\t=SUM(A1)\"")); assertTrue(csv.contains("csv_tab_escaped_fields")); assertEquals(3L, ready.rows)
    }
    @Test fun xlsxWriterActuallyRunsOnAndroidAndFlushesAcrossRecordPages(): Unit = fixture { f ->
        repeat(65) { save(f, it) }; val ready = generate(f, HealthRecordExportScope(format = HealthRecordExportFormat.XLSX))
        val texts = ZipFile(SeekableInMemoryByteChannel(bytes(f, ready))).use { zip -> buildList {
            val entries = zip.entries
            while (entries.hasMoreElements()) { val entry = entries.nextElement(); if (entry.name.startsWith("xl/worksheets/")) add(zip.getInputStream(entry).use { it.readBytes().toString(Charsets.UTF_8) }) }
        } }.joinToString("\n")
        assertTrue(texts.contains("inlineStr")); assertFalse(texts.contains("<f>"))
        var after = 0L; var count = 0
        do { val page = f.exports.items(ready.id, after); page.take(30).forEach { assertTrue(texts.contains(it.record.id)); count++ }; after = if (page.size > 30) page[29].sequence else 0 } while (after > 0)
        assertEquals(65, count)
    }
    @Test fun generatedIsNotSavedAndAFailedDestinationCanBeRetried(): Unit = fixture { f ->
        save(f); val s = generate(f)
        assertTrue(runCatching { HealthRecordExportPipeline.save(f.exports, s, object : OutputStream() { override fun write(value: Int) { error("destination full") } }) }.isFailure)
        assertEquals(HealthRecordExportState.GENERATED, f.exports.session(s.id)!!.state); assertTrue(bytes(f, s).isNotEmpty())
        f.exports.saved(s); assertEquals(HealthRecordExportState.SAVED, f.exports.session(s.id)!!.state)
    }
    @Test fun exportedXlsxPassesTheAppsAuthenticatedPackageAndWorkbookReader(): Unit = fixture { f ->
        save(f); val ready = generate(f, HealthRecordExportScope(format = HealthRecordExportFormat.XLSX))
        val original = f.originals.importOriginal(id(), bytes(f, ready).inputStream(), "export.xlsx", HealthRecordExportFormat.XLSX.mime, "file")
        val inspected = HealthXlsxReader.inspect(f.originals, original)
        assertEquals(listOf("Metadata", "Records 1"), inspected.first.map { it.name }); assertFalse(inspected.second)
    }
    @Test fun artifactTamperingAndUnexpectedSnapshotCountsFailExplicitly(): Unit = fixture { f ->
        save(f); val s = generate(f)
        RandomAccessFile(f.exports.artifacts.file(s.id, s.attempt), "rw").use { it.setLength(it.length() - 1) }
        assertTrue(runCatching { bytes(f, s) }.isFailure); assertEquals(HealthRecordExportState.GENERATED, f.exports.session(s.id)!!.state)
        val plan = prepare(f); context.openOrCreateDatabase(f.exportsName, 0, null).use { it.delete("export_records", "export_id=?", arrayOf(plan.id)) }
        val q = f.exports.queue(plan.id); assertEquals(HealthOriginalArchiveOutcome.FAILED, HealthRecordExportPipeline.generate(f.exports, q.id, q.dispatch))
        assertEquals(HealthRecordExportState.FAILED, f.exports.session(q.id)!!.state)
    }
    @Test fun snapshotRowsAreAuthenticatedToTheirIdentityAndSequence(): Unit = fixture { f ->
        save(f, 1); save(f, 2); val s = prepare(f)
        context.openOrCreateDatabase(f.exportsName, 0, null).use { db ->
            val blob = db.rawQuery("SELECT payload FROM export_records WHERE export_id=? AND sequence=1", arrayOf(s.id)).use { it.moveToFirst(); it.getBlob(0) }
            db.update("export_records", ContentValues().apply { put("payload", blob) }, "export_id=? AND sequence=2", arrayOf(s.id))
        }
        assertTrue(runCatching { f.exports.items(s.id) }.isFailure)
    }
    @Test fun historyIsKeysetPagedWithoutDuplicatingEqualTimestamps(): Unit = fixture { f ->
        repeat(65) { f.exports.create(HealthRecordExportScope()) }; var cursor: Pair<Long, String>? = null; val seen = hashSetOf<String>()
        do { val page = f.exports.history(cursor); assertTrue(page.size <= 31); page.take(30).forEach { assertTrue(seen.add(it.id)) }; cursor = if (page.size > 30) page[29].let { it.createdAt to it.id } else null } while (cursor != null)
        assertEquals(65, seen.size)
    }
    @Test fun sharedArtifactReaderAcceptsThePreviousOriginalZipCipherParameters(): Unit = fixture { f ->
        val key = ByteArray(32) { it.toByte() }; val aad = "legacy-original-archive".toByteArray(); val artifactId = id(); val attempt = id()
        val destination = f.exports.artifacts.file(artifactId, attempt); destination.parentFile!!.mkdirs()
        val raw = ByteArray(140_000) { (it % 251).toByte() }
        try {
            AesGcmHkdfStreaming(key, "HmacSha256", 32, 64 * 1024, 0).newEncryptingStream(destination.outputStream(), aad).use { it.write(raw) }
            assertArrayEquals(raw, f.exports.artifacts.input(artifactId, attempt, key, aad).use { it.readBytes() })
        } finally { key.fill(0); raw.fill(0) }
    }
    @Test fun originalOnlyImportBypassesBothOcrAndTableParsing(): Unit = fixture { f ->
        for ((name, mime) in listOf("bad.png" to "image/png", "bad.xlsx" to "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", "bad.bin" to "application/octet-stream")) {
            val source = HealthCaptureFiles.file(context, id()).apply { parentFile!!.mkdirs(); writeText("not an image or table") }
            try {
                val uri = FileProvider.getUriForFile(context, "${context.packageName}.files", source)
                val job = HealthImportJob(id(), uri.toString(), time, name = name, mime = mime, originalOnly = true)
                f.originals.createJob(job); assertEquals(HealthImportOutcome.COMPLETE, HealthImportPipeline(context, f.recordsName).run(f.originals, job.id))
                val stored = f.originals.job(job.id)!!; assertTrue(stored.originalOnly); assertEquals(HealthImportState.ORIGINAL_ONLY, stored.state); assertEquals(0, stored.pageCount)
                assertArrayEquals(source.readBytes(), f.originals.input(f.originals.original(stored.originalId)!!).use { it.readBytes() })
            } finally { source.delete() }
        }
        assertEquals(0L, f.records.count())
    }
    @Test fun legacyImportJobsDoNotSilentlyBecomeOriginalOnly(): Unit = fixture { _ ->
        val old = HealthImportJob(id(), "content://fixture/source", time).json().apply { remove("original_only") }
        assertFalse(HealthImportJob.from(old).originalOnly)
    }
}

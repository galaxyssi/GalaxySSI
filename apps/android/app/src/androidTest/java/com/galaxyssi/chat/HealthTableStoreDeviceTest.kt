package com.galaxyssi.chat

import android.content.ContentValues
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.UUID
import java.util.concurrent.CancellationException
import org.junit.Assert.*
import org.junit.Test

class HealthTableStoreDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private fun id() = UUID.randomUUID().toString()
    private val headers = listOf("time", "systolic", "diastolic", "unit")
    private fun raw(number: Long, systolic: String = "124") = HealthTableRow(number, mapOf("time" to "2026-09-01T08:10:00Z",
        "systolic" to systolic, "diastolic" to "82", "unit" to "mmHg"))
    private fun original() = HealthOriginal(id(), id(), "private.csv", "text/csv", 100, "a".repeat(64), 1, "unused", "file")
    private fun fixture(test: (String, HealthTableStore) -> Unit) {
        val name = "health-table-test-${id()}.db"
        try { HealthTableStore(context, name).use { test(name, it) } } finally { context.deleteDatabase(name) }
    }
    private fun prepare(store: HealthTableStore, rows: List<HealthTableRow>, original: HealthOriginal = original()): String {
        val batch = id(); store.begin(batch, original, "csv"); rows.chunked(30).forEach { store.append(batch, it) }
        store.finishReading(batch, headers)
        val value = store.batch(batch)!!
        store.mapping(batch, value.mappingRevision, value.mapping.copy(zone = "UTC"), true)
        return batch
    }
    private fun complete(store: HealthTableStore, id: String) { while (store.step(id)) Unit }
    private fun save(store: HealthTableStore, id: String) {
        complete(store, id); store.confirmSave(id, store.batch(id)!!.mappingRevision); complete(store, id)
    }
    @Test fun previewClassifiesValidDuplicateMissingAndInvalidSeparately() = fixture { name, store ->
        val batch = prepare(store, listOf(raw(1), raw(2), raw(3, ""), raw(4, "=100+24")))
        complete(store, batch)
        val counts = store.counts(batch)
        assertEquals(1L, counts[HealthTableRowState.VALID]); assertEquals(1L, counts[HealthTableRowState.DUPLICATE])
        assertEquals(1L, counts[HealthTableRowState.MISSING]); assertEquals(1L, counts[HealthTableRowState.INVALID])
        HealthRecordStore(context, name).use { assertEquals(0L, it.count()) }
        save(store, batch)
        HealthRecordStore(context, name).use { assertEquals(1L, it.count()); assertEquals("table", it.page().records.single().source) }
    }
    @Test fun savingResumesAcrossReopenWithoutDuplicatingAlreadyCommittedRows() = fixture { name, store ->
        val batch = prepare(store, (1L..81L).map { raw(it, (100 + it).toString()) })
        complete(store, batch); store.confirmSave(batch, store.batch(batch)!!.mappingRevision)
        assertTrue(store.step(batch)); assertEquals(30L, store.batch(batch)!!.cursor)
        HealthRecordStore(context, name).use { assertEquals(30L, it.count()) }
        HealthTableStore(context, name).use { reopened ->
            assertTrue(batch in reopened.active()); complete(reopened, batch)
            assertEquals(HealthTableState.SAVED, reopened.batch(batch)!!.state)
            assertEquals(81L, reopened.counts(batch)[HealthTableRowState.SAVED])
        }
        assertFalse(store.step(batch))
        HealthRecordStore(context, name).use { assertEquals(81L, it.count()) }
    }
    @Test fun batchUndoPreservesPreexistingDuplicatesAndSubsequentlyEditedRows() = fixture { name, store ->
        val existingBatch = prepare(store, listOf(raw(1))); save(store, existingBatch)
        val batch = prepare(store, listOf(raw(1), raw(2, "130"), raw(3, "140")))
        save(store, batch)
        HealthRecordStore(context, name).use { records ->
            assertEquals(3L, records.count())
            val edit = records.page().records.single { it.draft.values["systolic"] == "130" }
            assertTrue(records.save(edit.editable().copy(note = "later user edit")) is HealthSaveResult.Saved)
        }
        store.undo(batch); complete(store, batch)
        assertEquals(1L, store.counts(batch)[HealthTableRowState.UNDONE])
        assertEquals(1L, store.counts(batch)[HealthTableRowState.EDITED])
        assertEquals(1L, store.counts(batch)[HealthTableRowState.DUPLICATE])
        HealthRecordStore(context, name).use { records ->
            assertEquals(2L, records.count()); assertTrue(records.page().records.any { it.draft.note == "later user edit" })
        }
    }
    @Test fun originalRowIdentityDeduplicatesTheSameSourceAcrossImportJobs() = fixture { name, store ->
        val source = original()
        val first = prepare(store, listOf(raw(1)), source); save(store, first)
        val second = prepare(store, listOf(raw(1, "130")), source); complete(store, second)
        assertEquals(1L, store.counts(second)[HealthTableRowState.DUPLICATE])
        HealthRecordStore(context, name).use { assertEquals(1L, it.count()); assertEquals("124", it.page().records.single().draft.values["systolic"]) }
    }
    @Test fun concurrentRecordArrivalBetweenValidationAndSaveDoesNotRollbackOtherRows() = fixture { name, store ->
        val batch = prepare(store, listOf(raw(1), raw(2, "130")))
        complete(store, batch)
        val draft = HealthTablePolicy.evaluate(store.batch(batch)!!, raw(1)).draft!!
        HealthRecordStore(context, name).use { assertTrue(it.save(draft) is HealthSaveResult.Saved) }
        store.confirmSave(batch, store.batch(batch)!!.mappingRevision); complete(store, batch)
        assertEquals(1L, store.counts(batch)[HealthTableRowState.DUPLICATE])
        assertEquals(1L, store.counts(batch)[HealthTableRowState.SAVED])
        HealthRecordStore(context, name).use { assertEquals(2L, it.count()) }
    }
    @Test fun aFailedChunkRollsBackObservationsOwnershipAndCheckpointTogether() = fixture { name, store ->
        val batch = prepare(store, listOf(raw(1), raw(2, "130")))
        complete(store, batch); store.confirmSave(batch, store.batch(batch)!!.mappingRevision)
        context.openOrCreateDatabase(name, 0, null).use { db ->
            db.execSQL("CREATE TRIGGER health_table_test_failure BEFORE INSERT ON observations WHEN (SELECT COUNT(*) FROM observations)>0 BEGIN SELECT RAISE(ABORT,'test'); END")
        }
        assertTrue(runCatching { store.step(batch) }.isFailure)
        assertEquals(0L, store.batch(batch)!!.cursor); assertEquals(0L, store.counts(batch)[HealthTableRowState.SAVED])
        HealthRecordStore(context, name).use { assertEquals(0L, it.count()) }
        context.openOrCreateDatabase(name, 0, null).use { it.execSQL("DROP TRIGGER health_table_test_failure") }
        complete(store, batch)
        HealthRecordStore(context, name).use { assertEquals(2L, it.count()) }
    }
    @Test fun changedMappingInvalidatesPriorCountsAndRequiresFreshValidation() = fixture { _, store ->
        val batch = prepare(store, listOf(raw(1)))
        complete(store, batch); val before = store.batch(batch)!!
        store.mapping(batch, before.mappingRevision, before.mapping.copy(unitColumn = "", unit = "kPa"), false)
        assertEquals(HealthTableState.MAPPING, store.batch(batch)!!.state)
        assertEquals(0L, store.counts(batch)[HealthTableRowState.VALID])
        assertTrue(runCatching { store.confirmSave(batch, before.mappingRevision) }.isFailure)
        assertTrue(runCatching { store.mapping(batch, before.mappingRevision, before.mapping, true) }.isFailure)
    }
    @Test fun cancellingValidationDoesNotCreateMeasurementsAndCanBeRemapped() = fixture { name, store ->
        val batch = prepare(store, (1L..70L).map { raw(it, (100 + it).toString()) })
        assertTrue(store.step(batch)); store.pause(batch); assertFalse(store.step(batch))
        assertEquals(HealthTableState.MAPPING, store.batch(batch)!!.state)
        HealthRecordStore(context, name).use { assertEquals(0L, it.count()) }
    }
    @Test fun rowPagingHasStableOrderAndNoTotalRowTruncation() = fixture { _, store ->
        val batch = prepare(store, (1L..125L).map { raw(it) }); complete(store, batch)
        var after = 0L; val numbers = arrayListOf<Long>()
        while (true) { val page = store.page(batch, after); if (page.isEmpty()) break
            assertTrue(page.size <= 30); numbers += page.map { it.row.number }; after = page.last().row.number
        }
        assertEquals((1L..125L).toList(), numbers)
    }
    @Test fun rowAndBatchPayloadsAreEncryptedAndIdentityBound() = fixture { name, store ->
        val batch = prepare(store, listOf(raw(1), raw(2)))
        context.openOrCreateDatabase(name, 0, null).use { db ->
            db.rawQuery("SELECT payload FROM health_tables", null).use { it.moveToFirst(); assertFalse(String(it.getBlob(0), Charsets.ISO_8859_1).contains("private.csv")) }
            val payload = db.rawQuery("SELECT payload FROM health_table_rows WHERE number=1", null).use { it.moveToFirst(); it.getBlob(0) }
            assertFalse(String(payload, Charsets.ISO_8859_1).contains("systolic"))
            db.update("health_table_rows", ContentValues().apply { put("payload", payload) }, "number=2", null)
        }
        assertTrue(runCatching { store.page(batch) }.isFailure)
    }
    @Test fun schemaTwoUpgradeKeepsOriginalObservationsAndAddsStructuredTables() {
        val name = "health-table-v2-${id()}.db"
        try {
            val original = original()
            val evidence = HealthEvidence(original.id, id(), "row-1", original.sha256, 1, "124/82", confirmed = true, kind = "table", tableRow = 1)
            val draft = HealthDraft(values = mapOf("systolic" to "124", "diastolic" to "82"),
                measuredAt = 1_780_000_000_000L, evidence = evidence)
            val first = seedLegacyHealthObservation(context, name, 2, draft)
            HealthTableStore(context, name).use { migrated -> assertTrue(migrated.active().isEmpty()) }
            HealthRecordStore(context, name).use {
                assertEquals(listOf(first), it.page().records)
                assertEquals(first.id, it.recordForEvidence(draft)?.id)
            }
        } finally {
            context.deleteDatabase(name)
        }
    }
    @Test fun allInvalidAndDuplicateOnlyBatchesCannotInventMeasurements() = fixture { name, store ->
        val batch = prepare(store, listOf(raw(1, ""), raw(2, "<120")))
        complete(store, batch); store.confirmSave(batch, store.batch(batch)!!.mappingRevision); complete(store, batch)
        assertEquals(HealthTableState.SAVED, store.batch(batch)!!.state)
        assertEquals(0L, store.counts(batch)[HealthTableRowState.SAVED])
        HealthRecordStore(context, name).use { assertEquals(0L, it.count()) }
    }
    @Test fun undoAlsoResumesAtTheLastCommittedChunk() = fixture { name, store ->
        val batch = prepare(store, (1L..72L).map { raw(it, (100 + it).toString()) }); save(store, batch)
        store.undo(batch); assertTrue(store.step(batch))
        HealthRecordStore(context, name).use { assertEquals(42L, it.count()) }
        HealthTableStore(context, name).use { complete(it, batch); assertEquals(HealthTableState.UNDONE, it.batch(batch)!!.state) }
        HealthRecordStore(context, name).use { assertEquals(0L, it.count()) }
    }
    @Test fun structuredReadingResumesFromEncryptedRowsAndKeepsTheOriginalByteFaithful() = fixture { name, tables ->
        val originalDb = "health-table-original-${id()}.db"; val root = File(context.cacheDir, "health-table-original-${id()}")
        try { HealthOriginalStore(context, originalDb, root).use { originals ->
            val text = "time,systolic,diastolic,unit\n" + (1..85).joinToString("\n") { "2026-09-01T08:10:00Z,${100 + it},82,mmHg" }
            val job = id(); val original = originals.importOriginal(job, text.byteInputStream(), "readings.csv", "text/csv", "file")
            var checks = 0
            assertTrue(runCatching { HealthTableImport.stage(originals, original, job, tables) { if (++checks == 44) throw CancellationException() } }.isFailure)
            assertEquals(30L, tables.batch(job)!!.rows)
            HealthTableStore(context, name).use { reopened ->
                val done = HealthTableImport.stage(originals, original, job, reopened)
                assertEquals(85L, done.rows); assertEquals(HealthTableState.MAPPING, done.state)
                assertEquals(listOf("time", "systolic", "diastolic", "unit"), done.headers)
            }
            assertEquals(text, originals.input(original).bufferedReader().use { it.readText() })
            HealthRecordStore(context, name).use { assertEquals(0L, it.count()) }
        } } finally { context.deleteDatabase(originalDb); root.deleteRecursively() }
    }
    @Test fun structureSizeIsCheckedBeforeReadingAndLeavesTheOriginalAlone() = fixture { _, store ->
        val originalDb = "health-table-original-${id()}.db"; val root = File(context.cacheDir, "health-table-original-${id()}")
        try { HealthOriginalStore(context, originalDb, root).use { originals ->
            val result = runCatching { HealthTableImport.stage(originals, original().copy(size = HealthTableParser.MAX_BYTES + 1), id(), store) }
            assertEquals("table_size", (result.exceptionOrNull() as HealthImportFailure).code)
        } } finally { context.deleteDatabase(originalDb); root.deleteRecursively() }
    }
    @Test fun aLateValidationWorkerCannotConsumeTheSavePhase() = fixture { name, store ->
        val batch = prepare(store, listOf(raw(1)))
        val revision = store.batch(batch)!!.mappingRevision
        complete(store, batch); store.confirmSave(batch, revision)
        assertFalse(store.step(batch, HealthTableState.VALIDATING, revision))
        assertEquals(HealthTableState.SAVING, store.batch(batch)!!.state); assertEquals(0L, store.batch(batch)!!.cursor)
        HealthRecordStore(context, name).use { assertEquals(0L, it.count()) }
        complete(store, batch)
        HealthRecordStore(context, name).use { assertEquals(1L, it.count()) }
    }
    @Test fun staleMappingWorkersCannotValidateAnUpdatedMapping() = fixture { _, store ->
        val batch = prepare(store, listOf(raw(1)))
        val old = store.batch(batch)!!; store.pause(batch)
        store.mapping(batch, old.mappingRevision, old.mapping.copy(unitColumn = "", unit = "kPa"), true)
        assertFalse(store.step(batch, HealthTableState.VALIDATING, old.mappingRevision))
        assertEquals(0L, store.batch(batch)!!.cursor)
        complete(store, batch)
        assertEquals(HealthTableState.READY, store.batch(batch)!!.state)
    }
    @Test fun missingSourceRowsStopTheChunkInsteadOfSilentlyDroppingMeasurements() = fixture { name, store ->
        val batch = prepare(store, listOf(raw(1), raw(2, "130"), raw(3, "140")))
        context.openOrCreateDatabase(name, 0, null).use { it.delete("health_table_rows", "number=2", null) }
        assertTrue(runCatching { store.step(batch) }.isFailure)
        assertEquals(0L, store.batch(batch)!!.cursor)
        HealthRecordStore(context, name).use { assertEquals(0L, it.count()) }
    }
}

package com.galaxyssi.chat

import android.content.ContentValues
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import org.junit.Assert.*
import org.junit.Test

class HealthCatalogStoreDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val time = 1_790_000_000_000L
    private fun id() = UUID.randomUUID().toString()
    private fun draft(value: String) = HealthDraft(HealthMetric.CRP, mapOf("crp" to value), "mg/L", time)
    private fun fixture(test: (String, HealthRecordStore) -> Unit) {
        val name = "health-catalog-${id()}.db"
        try { HealthRecordStore(context, name).use { test(name, it) } } finally { context.deleteDatabase(name) }
    }
    @Test fun everyCatalogMetricUsesTheSameEncryptedPersistentRecordSystem() = fixture { name, store ->
        HealthMetric.entries.forEachIndexed { index, metric ->
            val raw = if (metric.form == HealthResultForm.QUALITATIVE) "negative" else "50"
            val input = HealthDraft(metric, metric.fields.associateWith { raw }, metric.units.first(), time - index * 1000)
            assertTrue(metric.name, store.save(input) is HealthSaveResult.Saved)
        }
        HealthRecordStore(context, name).use { reopened ->
            assertEquals(HealthMetric.entries.size.toLong(), reopened.count())
            HealthMetric.entries.forEach { metric -> assertEquals(metric, reopened.page(metric = metric).records.single().draft.metric) }
        }
    }
    @Test fun qualitativeResultsRetainTheirLabelAndAbsenceOfPhysicalUnitsAfterReopen() = fixture { name, store ->
        val saved = (store.save(HealthDraft(HealthMetric.URINE_PROTEIN, mapOf("urine_protein" to "\u5f31\u9633\u6027"), measuredAt = time)) as HealthSaveResult.Saved).record
        HealthRecordStore(context, name).use {
            val record = it.record(saved.id)!!; assertEquals("\u5f31\u9633\u6027", record.draft.values["urine_protein"])
            assertEquals("", record.draft.unit); assertNull(HealthResult.parse(record.draft.values["urine_protein"]!!, record.draft.metric.form)!!.exactNumber)
        }
    }
    @Test fun boundsAndRangesAreNotCollapsedIntoExactNumbersOrEachOther() = fixture { _, store ->
        for (raw in listOf("<1", "<=1", "1", "1 - 1", "1-2")) assertTrue(store.save(draft(raw)) is HealthSaveResult.Saved)
        assertEquals(5L, store.count())
        assertTrue(store.save(draft("\u2264 1.0")) is HealthSaveResult.Duplicate)
        assertTrue(store.save(draft("1.00~2.00")) is HealthSaveResult.Duplicate)
    }
    @Test fun rawNotationAndReportedReferenceAreEncryptedNotPlainDatabaseFields() = fixture { name, store ->
        val saved = (store.save(draft("< 00.10").copy(reference = "private-reference-marker")) as HealthSaveResult.Saved).record
        context.openOrCreateDatabase(name, 0, null).use { db -> db.rawQuery("SELECT payload FROM observations", null).use {
            assertTrue(it.moveToFirst()); val text = String(it.getBlob(0), Charsets.ISO_8859_1)
            assertFalse(text.contains("private-reference-marker")); assertFalse(text.contains("reported_values"))
        } }
        HealthRecordStore(context, name).use { reopened -> assertEquals(saved, reopened.record(saved.id)) }
    }
    @Test fun editsKeepIdentityAndOriginalNotationWhileReferenceHistoryRemainsAuditable() = fixture { _, store ->
        val first = (store.save(draft("< 00.10").copy(reference = "<5")) as HealthSaveResult.Saved).record
        val second = (store.save(first.editable().copy(reference = "<4")) as HealthSaveResult.Saved).record
        assertEquals(first.id, second.id); assertEquals(2, second.revision)
        assertEquals(listOf("<4", "<5"), store.history(first.id).map { it.draft.reference })
        assertTrue(store.history(first.id).all { it.draft.reportedValues["crp"] == "< 00.10" })
    }
    @Test fun oldPayloadsWithoutTypedMetadataStillDecodeAndEditWithoutSchemaReset() = fixture { name, store ->
        val first = (store.save(draft("1.2")) as HealthSaveResult.Saved).record
        val json = first.json(); val values = json.getJSONObject("draft")
        listOf("results", "reported_values", "reference").forEach(values::remove)
        val bytes = json.toString().toByteArray(); val cipher = try {
            AgentStorageCipher.encryptBinary(bytes, "$name|health|${first.id}|1".toByteArray())
        } finally { bytes.fill(0) }
        try { store.tableDatabase.update("observations", ContentValues().apply { put("payload", cipher) }, "id=?", arrayOf(first.id)) }
        finally { cipher.fill(0) }
        HealthRecordStore(context, name).use { reopened ->
            val legacy = reopened.record(first.id)!!; assertEquals("1.2", legacy.draft.values["crp"])
            assertTrue(legacy.draft.reportedValues.isEmpty()); assertEquals("", legacy.draft.reference)
            assertTrue(reopened.save(legacy.editable().copy(note = "confirmed")) is HealthSaveResult.Saved)
        }
    }
    @Test fun catalogRecordFiltersUseThirtyRowKeysetPagesWithoutRepeats() = fixture { _, store ->
        repeat(95) { index -> store.save(HealthDraft(HealthMetric.STEPS, mapOf("steps" to "$index"), measuredAt = time - index * 1000)) }
        store.save(draft("<1"))
        var cursor: HealthPageCursor? = null; val ids = linkedSetOf<String>()
        do {
            val page = store.page(after = cursor, metrics = setOf(HealthMetric.STEPS))
            assertTrue(page.records.size <= 30); page.records.forEach { assertTrue(ids.add(it.id)); assertEquals(HealthMetric.STEPS, it.draft.metric) }
            cursor = page.next
        } while (cursor != null)
        assertEquals(95, ids.size); assertTrue(store.page(metrics = emptySet()).records.isEmpty())
    }
    @Test fun unmatchedOrUnrelatedCatalogResultsAreNotDecryptedAsFallback() = fixture { _, store ->
        val hidden = (store.save(draft("<1")) as HealthSaveResult.Saved).record
        store.save(HealthDraft(HealthMetric.STEPS, mapOf("steps" to "0"), measuredAt = time))
        store.tableDatabase.update("observations", ContentValues().apply { put("payload", byteArrayOf(0, 1)) }, "id=?", arrayOf(hidden.id))
        assertEquals(1, store.page(metrics = setOf(HealthMetric.STEPS)).records.size)
        assertTrue(store.page(metrics = emptySet()).records.isEmpty())
        assertTrue(runCatching { store.page() }.isFailure)
    }
    @Test fun multipleMetricStreamsMergeBeforePayloadDecryptionAndKeepGlobalCursorOrdering() = fixture { _, store ->
        repeat(95) { index -> store.save(HealthDraft(HealthMetric.STEPS, mapOf("steps" to "$index"), measuredAt = time - index * 1000)) }
        repeat(41) { index -> store.save(draft("<1").copy(measuredAt = time - index * 1500)) }
        store.save(HealthDraft(HealthMetric.WEIGHT, mapOf("weight" to "68"), measuredAt = time))
        val rows = arrayListOf<HealthObservation>(); var cursor: HealthPageCursor? = null
        do { val page = store.page(after = cursor, metrics = setOf(HealthMetric.STEPS, HealthMetric.CRP))
            assertTrue(page.records.size <= 30); rows += page.records; cursor = page.next
        } while (cursor != null)
        assertEquals(136, rows.size); assertEquals(136, rows.map { it.id }.toSet().size)
        assertEquals(rows.sortedWith(compareByDescending<HealthObservation> { it.draft.measuredAt }.thenByDescending { it.id }), rows)
        assertTrue(rows.all { it.draft.metric in setOf(HealthMetric.STEPS, HealthMetric.CRP) })
        assertEquals(30, store.page(metrics = HealthMetric.entries.toSet()).records.size)
        assertTrue(store.page(metric = HealthMetric.WEIGHT, metrics = setOf(HealthMetric.STEPS)).records.isEmpty())
    }
    @Test fun unknownUnitAndEmptyLabelCannotCreateAQualitativeRecord() = fixture { _, store ->
        val input = HealthDraft(HealthMetric.URINE_PROTEIN, mapOf("urine_protein" to ""), measuredAt = time)
        assertTrue(runCatching { store.save(input) }.isFailure)
        assertTrue(runCatching { store.save(input.copy(values = mapOf("urine_protein" to "negative"), unit = "mg/L")) }.isFailure)
        assertEquals(0L, store.count())
    }
    @Test fun typedResultOrReportedNotationMismatchCannotBeAcceptedAsAnObservation() = fixture { _, store ->
        val record = (store.save(draft("<1")) as HealthSaveResult.Saved).record
        val json = record.json(); json.getJSONObject("draft").getJSONObject("reported_values").put("crp", "2")
        assertTrue(runCatching { HealthObservation.from(json) }.isFailure)
    }
    @Test fun laboratoryQualitativeLabelsAndNumericValuesKeepDistinctUnitRequirements() = fixture { name, store ->
        val label = (store.save(draft("not detected").copy(unit = "")) as HealthSaveResult.Saved).record
        assertTrue(runCatching { store.save(draft("<0.1").copy(unit = "")) }.isFailure)
        HealthRecordStore(context, name).use { reopened -> assertEquals("", reopened.record(label.id)!!.draft.unit); assertEquals(1L, reopened.count()) }
    }
    @Test fun tableSaveAndUndoPreserveQualitativeSemanticsReferenceAndOwnership() = fixture { name, records ->
        HealthTableStore(context, name).use { tables ->
            val batch = id(); val original = HealthOriginal(id(), id(), "urine.csv", "text/csv", 100, "a".repeat(64), 1, "unused", "file")
            val headers = listOf("time", "urine_protein", "reference")
            tables.begin(batch, original, "csv"); tables.append(batch, listOf(HealthTableRow(1, mapOf("time" to "2026-09-01T08:00:00Z", "urine_protein" to "negative", "reference" to "negative (report)"))))
            tables.finishReading(batch, headers)
            tables.mapping(batch, 0, HealthTablePolicy.suggest(headers, HealthMetric.URINE_PROTEIN).copy(zone = "UTC"), true)
            while (tables.step(batch)) Unit
            assertEquals(1L, tables.counts(batch)[HealthTableRowState.VALID])
            tables.confirmSave(batch, tables.batch(batch)!!.mappingRevision); while (tables.step(batch)) Unit
            val saved = records.page().records.single(); assertEquals("negative", saved.draft.values["urine_protein"]); assertEquals("negative (report)", saved.draft.reference)
            tables.undo(batch); while (tables.step(batch)) Unit
            assertEquals(0L, records.count()); assertEquals(2, records.history(saved.id).size)
        }
    }
}

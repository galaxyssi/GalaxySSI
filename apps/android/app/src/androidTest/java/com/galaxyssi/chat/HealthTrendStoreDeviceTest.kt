package com.galaxyssi.chat

import android.content.ContentValues
import android.os.CancellationSignal
import androidx.test.platform.app.InstrumentationRegistry
import java.time.LocalDate
import java.time.ZoneId
import java.util.UUID
import java.util.concurrent.CancellationException
import org.junit.Assert.*
import org.junit.Test

class HealthTrendStoreDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private fun id() = UUID.randomUUID().toString()
    private fun spec(metric: HealthMetric = HealthMetric.STEPS) = HealthTrendSpec(metric, LocalDate.of(2026, 10, 1), LocalDate.of(2026, 10, 7), ZoneId.of("UTC"), metric.units.first())
    private fun draft(s: HealthTrendSpec, n: Int, value: String = "${n + 1}", unit: String = s.unit) = HealthDraft(s.metric,
        s.metric.requiredFields.associateWith { value }, unit, s.from + n * 60_000L + 1)
    private fun fixture(test: (HealthRecordStore) -> Unit) {
        val name = "health-trend-${id()}.db"
        try { HealthRecordStore(context, name).use(test) } finally { context.deleteDatabase(name) }
    }
    @Test fun indexedWindowChunksKeepAllNinetyFiveRecordsWithoutRepeats() = fixture { store ->
        val s = spec(); repeat(95) { store.save(draft(s, it)) }; var cursor: HealthPageCursor? = null; val ids = linkedSetOf<String>()
        do { val page = store.trendChunk(s, cursor); assertTrue(page.records.size <= 30); page.records.forEach { assertTrue(ids.add(it.id)) }; cursor = page.next } while (cursor != null)
        assertEquals(95, ids.size); assertEquals(95L, HealthTrendRepository.load(store, s).eligible)
    }
    @Test fun outOfWindowOtherMetricAndDeletedRecordsDoNotContribute() = fixture { store ->
        val s = spec(); store.save(draft(s, 0)); store.save(draft(s, 1).copy(measuredAt = s.from - 1)); store.save(draft(s, 2).copy(measuredAt = s.until))
        store.save(draft(spec(HealthMetric.WEIGHT), 0, "68"))
        val deleted = (store.save(draft(s, 3)) as HealthSaveResult.Saved).record; assertTrue(store.delete(deleted.id, deleted.revision))
        assertEquals(1L, HealthTrendRepository.load(store, s).eligible)
    }
    @Test fun pointRecordPagingFiltersUnitsBeforeReturningThirtyVisibleRows() = fixture { store ->
        val s = spec(HealthMetric.WEIGHT); repeat(95) { store.save(draft(s, it, unit = if (it % 2 == 0) "kg" else "lb")) }
        val rows = arrayListOf<HealthObservation>(); var cursor: HealthPageCursor? = null
        do { val page = store.trendRecords(s, cursor, true); assertTrue(page.records.size <= 30); rows += page.records; cursor = page.next } while (cursor != null)
        assertEquals(48, rows.size); assertEquals(48, rows.map { it.id }.toSet().size); assertTrue(rows.all { it.draft.unit == "kg" })
        val summary = HealthTrendRepository.load(store, s); assertEquals(48L, summary.eligible); assertEquals(47L, summary.otherUnits)
    }
    @Test fun nonNumericResultsRemainAvailableInAllRecordsButNotPointContributors() = fixture { store ->
        val s = spec(HealthMetric.CRP)
        for ((index, value) in listOf("1", "<1", "1-2", "negative").withIndex()) store.save(draft(s, index, value))
        assertEquals(4, store.trendRecords(s).records.size); assertEquals(1, store.trendRecords(s, numericOnly = true).records.size)
        val summary = HealthTrendRepository.load(store, s); assertEquals(3L, summary.nonNumeric); assertEquals(1L, summary.eligible)
    }
    @Test fun originalSourcesUseStableIdsAndSupportMoreThanOnePickerPage() = fixture { store ->
        val s = spec(); val origins = (1..35).map { id() }
        origins.forEachIndexed { index, origin -> store.save(draft(s, index).copy(evidence = HealthEvidence(origin, id(), "reading", "a".repeat(64), 1, "fixture", confirmed = true))) }
        val first = store.trendSourceIds(s); assertEquals(31, first.size)
        val second = store.trendSourceIds(s, first[29]); assertEquals(35, (first.take(30) + second).toSet().size)
        val filtered = s.copy(source = HealthTrendSource(originalId = origins[3]))
        assertEquals(1L, HealthTrendRepository.load(store, filtered).eligible)
        assertEquals(origins[3], store.trendRecords(filtered).records.single().draft.evidence!!.originalId)
        assertEquals(0L, HealthTrendRepository.load(store, s.copy(source = HealthTrendSource(manualOnly = true))).eligible)
    }
    @Test fun cancellationStopsScanningWithoutModifyingAnyObservations() = fixture { store ->
        val s = spec(); repeat(95) { store.save(draft(s, it)) }; var calls = 0
        assertTrue(runCatching { HealthTrendRepository.load(store, s, cancelled = { if (++calls > 17) throw CancellationException() }) }.exceptionOrNull() is CancellationException)
        assertEquals(95L, store.count()); assertEquals(95L, HealthTrendRepository.load(store, s).eligible)
    }
    @Test fun cancelledSqlQueriesAreNotRetriedOrConvertedIntoZeroData() = fixture { store ->
        val s = spec(); store.save(draft(s, 0)); val signal = CancellationSignal().apply { cancel() }
        assertTrue(runCatching { store.trendChunk(s, signal = signal) }.isFailure); assertEquals(1L, store.count())
    }
    @Test fun recordEditsAndDeletionAreReflectedByTheNextUncachedLoad() = fixture { store ->
        val s = spec(); val first = (store.save(draft(s, 0, "100")) as HealthSaveResult.Saved).record
        assertEquals("100", HealthTrendRepository.load(store, s).points.single().value.toPlainString())
        val edit = (store.save(first.editable().copy(values = mapOf("steps" to "200"))) as HealthSaveResult.Saved).record
        assertEquals("200", HealthTrendRepository.load(store, s).points.single().value.toPlainString())
        assertTrue(store.delete(edit.id, edit.revision)); assertTrue(HealthTrendRepository.load(store, s).points.isEmpty()); assertEquals(3, store.history(first.id).size)
    }
    @Test fun corruptedHistoryOutsideTheSelectedWindowIsNotDecrypted() = fixture { store ->
        val s = spec(); store.save(draft(s, 0)); val hidden = (store.save(draft(s, 1).copy(measuredAt = s.from - 1)) as HealthSaveResult.Saved).record
        store.tableDatabase.update("observations", ContentValues().apply { put("payload", byteArrayOf(0, 1)) }, "id=?", arrayOf(hidden.id))
        assertEquals(1L, HealthTrendRepository.load(store, s).eligible); assertEquals(2L, store.count())
    }
    @Test fun corruptionInsideTheSelectedWindowFailsVisiblyWithoutResettingData() = fixture { store ->
        val s = spec(); val bad = (store.save(draft(s, 0)) as HealthSaveResult.Saved).record
        store.tableDatabase.update("observations", ContentValues().apply { put("payload", byteArrayOf(0, 1)) }, "id=?", arrayOf(bad.id))
        assertTrue(runCatching { HealthTrendRepository.load(store, s) }.isFailure); assertEquals(1L, store.count())
    }
    @Test fun queryScopeIntentsRoundTripWithoutCopyingMeasurementValues() {
        val s = spec(HealthMetric.GLUCOSE).copy(source = HealthTrendSource(originalId = id()), aggregation = HealthTrendAggregation.MAXIMUM)
        val intent = android.content.Intent().putHealthTrend(s); assertEquals(s, intent.healthTrendSpec())
        assertFalse(intent.extras!!.containsKey("values")); assertFalse(intent.extras!!.containsKey("reported_values"))
        intent.putExtra("health_unit", "invented"); assertNull(intent.healthTrendSpec())
    }
    @Test fun perMetricVersionsChangeOnlyAfterConfirmedMutationsNotDraftsDuplicatesOrConflicts() = fixture { store ->
        val s = spec(); val original = store.metricVersion(s.metric)
        store.saveDraft(draft(s, 0)); assertEquals(original, store.metricVersion(s.metric))
        val saved = (store.save(draft(s, 0)) as HealthSaveResult.Saved).record; val changed = store.metricVersion(s.metric)
        assertNotEquals(original, changed); assertTrue(store.save(draft(s, 0)) is HealthSaveResult.Duplicate); assertEquals(changed, store.metricVersion(s.metric))
        assertEquals(HealthSaveResult.Conflict, store.save(saved.editable().copy(revision = 9))); assertEquals(changed, store.metricVersion(s.metric))
        store.save(draft(spec(HealthMetric.WEIGHT), 0, "68")); assertEquals(changed, store.metricVersion(s.metric))
        assertTrue(store.delete(saved.id, saved.revision)); assertNotEquals(changed, store.metricVersion(s.metric))
    }
    @Test fun changesDuringAStreamPreventPublicationOfAMixedRevisionSummary() = fixture { store ->
        val s = spec(); repeat(95) { store.save(draft(s, it)) }; var changed = false
        val failure = runCatching { HealthTrendRepository.load(store, s, progress = {
            if (!changed) { changed = true; store.save(draft(s, 100, "1000")) }
        }) }.exceptionOrNull()
        assertTrue(failure.toString(), failure is HealthTrendChangedException)
        assertEquals(96L, HealthTrendRepository.load(store, s).eligible)
    }
    @Test fun unrelatedMetricChangesDoNotInvalidateTheSelectedTrend() = fixture { store ->
        val s = spec(); repeat(35) { store.save(draft(s, it)) }; var changed = false
        val result = HealthTrendRepository.load(store, s, progress = { if (!changed) { changed = true; store.save(draft(spec(HealthMetric.WEIGHT), 0, "68")) } })
        assertEquals(35L, result.eligible); assertEquals(store.metricVersion(s.metric), result.version)
    }
    @Test fun aPlottedRecordRevisionRemainsReadableAfterCorrectionAndSoftDeletion() = fixture { store ->
        val s = spec(); val first = (store.save(draft(s, 0, "100")) as HealthSaveResult.Saved).record
        val point = HealthTrendRepository.load(store, s).points.single(); assertEquals(first.revision, point.recordRevision)
        val edit = (store.save(first.editable().copy(values = mapOf("steps" to "200"))) as HealthSaveResult.Saved).record
        assertEquals("100", store.revision(point.recordId, point.recordRevision)!!.draft.values["steps"])
        assertEquals("200", store.record(first.id)!!.draft.values["steps"])
        assertTrue(store.delete(edit.id, edit.revision)); assertNotNull(store.revision(first.id, 1)); assertNull(store.revision(first.id, 3))
    }
    @Test fun changingAMetricRotatesBothOldAndNewMetricVersions() = fixture { store ->
        val s = spec(); val first = (store.save(draft(s, 0)) as HealthSaveResult.Saved).record
        val beforeOld = store.metricVersion(s.metric); val beforeNew = store.metricVersion(HealthMetric.WEIGHT)
        assertTrue(store.save(first.editable().copy(metric = HealthMetric.WEIGHT, values = mapOf("weight" to "68"), unit = "kg", reportedValues = emptyMap())) is HealthSaveResult.Saved)
        assertNotEquals(beforeOld, store.metricVersion(s.metric)); assertNotEquals(beforeNew, store.metricVersion(HealthMetric.WEIGHT))
    }
    @Test fun schemaThreeUpgradeKeepsDataAndAddsMetricClockMetadata() {
        val s = spec()
        val name = "health-trend-v3-${id()}.db"
        try {
            val first = seedLegacyHealthObservation(context, name, 3, draft(s, 0))
            HealthRecordStore(context, name).use { reopened ->
                assertEquals(first, reopened.record(first.id)); assertEquals(1, reopened.history(first.id).size)
                assertEquals("", reopened.metricVersion(s.metric)); assertEquals(HealthRecordStore.SCHEMA_VERSION, reopened.tableDatabase.version)
                val edit = reopened.save(first.editable().copy(note = "verified"))
                assertTrue(edit is HealthSaveResult.Saved); assertTrue(reopened.metricVersion(s.metric).isNotBlank())
            }
        } finally { context.deleteDatabase(name) }
    }
    @Test fun committedChangesNotifyOnlyTheirOwnDatabaseScope() = fixture { store ->
        val name = java.io.File(store.tableDatabase.path).name; val calls = java.util.concurrent.atomic.AtomicInteger()
        val latch = java.util.concurrent.CountDownLatch(1)
        val observer = object : android.database.ContentObserver(android.os.Handler(android.os.Looper.getMainLooper())) {
            override fun onChange(selfChange: Boolean) { calls.incrementAndGet(); latch.countDown() }
        }
        context.contentResolver.registerContentObserver(HealthRecordStore.changes(context, name), false, observer)
        try {
            val s = spec(); store.save(draft(s, 0)); assertTrue(latch.await(5, java.util.concurrent.TimeUnit.SECONDS))
            store.save(draft(s, 0)); store.saveDraft(draft(s, 1)); InstrumentationRegistry.getInstrumentation().waitForIdleSync(); android.os.SystemClock.sleep(100)
            assertEquals(1, calls.get())
        } finally { context.contentResolver.unregisterContentObserver(observer) }
    }
}

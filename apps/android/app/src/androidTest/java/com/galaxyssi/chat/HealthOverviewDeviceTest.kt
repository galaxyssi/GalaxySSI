package com.galaxyssi.chat

import android.content.ContentValues
import android.content.Context
import androidx.test.platform.app.InstrumentationRegistry
import java.time.LocalDate
import java.time.ZoneId
import java.util.UUID
import org.junit.Assert.*
import org.junit.Test

internal fun overviewOcrJob(context: Context, names: HealthOverviewDatabases, time: Long): Pair<HealthImportJob, HealthOriginal> {
    val id = UUID.randomUUID().toString()
    return HealthOriginalStore(context, names.originals, names.originalRoot(context)).use { store ->
        store.createJob(HealthImportJob(id, "content://overview.test/report", time))
        val original = store.importOriginal(id, "local report".byteInputStream(), "test.pdf", "application/pdf", "file")
        store.savePage(id, HealthOcrPage(1, 100, 100, listOf(HealthOcrLine("120/80", listOf(0, 0, 40, 40)))))
        val ready = store.updateJob(id) { it.copy(state = HealthImportState.REVIEW, originalId = original.id) }!!
        ready to original
    }
}

internal fun clearHealthOverviewFixture(context: Context, names: HealthOverviewDatabases) {
    check(names.fixture != null)
    listOf(names.records, names.originals, names.reminders, names.privacy, names.backups).forEach(context::deleteDatabase)
    context.deleteSharedPreferences(names.prefs)
    names.originalRoot(context).deleteRecursively()
}

class HealthOverviewDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val zone = ZoneId.of("UTC")
    private val now = LocalDate.of(2024, 11, 4).atTime(10, 0).atZone(zone).toInstant().toEpochMilli()
    private fun fixture(test: (HealthOverviewDatabases, HealthRecordStore) -> Unit) {
        val names = HealthOverviewDatabases(UUID.randomUUID().toString())
        try { HealthRecordStore(context, names.records).use { test(names, it) } }
        finally { clearHealthOverviewFixture(context, names) }
    }
    private fun load(names: HealthOverviewDatabases, store: HealthRecordStore) = HealthOverviewRepository.load(context, store, names, now, zone)
    private fun steps(store: HealthRecordStore, time: Long, value: String) =
        (store.save(HealthDraft(HealthMetric.STEPS, mapOf("steps" to value), "steps", time)) as HealthSaveResult.Saved).record
    @Test fun latestConfirmedMetricExcludesOtherProfilesFutureValuesAndDeletedRows() = fixture { names, store ->
        val expected = steps(store, now - HealthReminderPolicy.DAY, "4000")
        val foreign = steps(store, now - 1000, "9000")
        val payload = foreign.copy(profileId = "other").json().toString().toByteArray()
        try { store.tableDatabase.update("observations", ContentValues().apply {
            put("payload", AgentStorageCipher.encryptBinary(payload, "${names.records}|health|${foreign.id}|${foreign.revision}".toByteArray()))
        }, "id=?", arrayOf(foreign.id)) } finally { payload.fill(0) }
        steps(store, now + 1000, "8000")
        val removed = steps(store, now - 2000, "7000"); store.delete(removed.id, removed.revision)
        val snapshot = load(names, store)
        val steps = snapshot.metrics.single { it.metric == HealthMetric.STEPS }
        assertEquals(expected.id, steps.record!!.id)
        assertEquals(HealthOverviewFreshness.STALE, steps.freshness)
        assertEquals(5, snapshot.metrics.count { it.freshness == HealthOverviewFreshness.MISSING })
    }
    @Test fun ocrReviewNeverBecomesAConfirmedMetricAndCompletedEvidenceIsNotCountedAgain() = fixture { names, store ->
        val (job, original) = overviewOcrJob(context, names, now - 2000)
        val snapshot = load(names, store)
        assertFalse(snapshot.hasRecords)
        assertEquals(HealthOverviewReviewKind.OCR, (snapshot.attention.single() as HealthOverviewAttention.Review).kind)
        val evidence = HealthEvidence(original.id, job.id, "bp", original.sha256, 1, "120/80", confirmed = true)
        val draft = HealthDraft(values = mapOf("systolic" to "120", "diastolic" to "80"), measuredAt = now - 1000, evidence = evidence)
        val saved = (store.save(draft) as HealthSaveResult.Saved).record
        assertTrue(load(names, store).attention.isEmpty())
        assertTrue(store.delete(saved.id, saved.revision))
        assertTrue(load(names, store).attention.isEmpty())
        store.saveDraft(draft.copy(evidence = evidence.copy(candidateId = "second", confirmed = false)))
        assertEquals(job.id, (load(names, store).attention.single() as HealthOverviewAttention.Review).jobId)
    }
    @Test fun tableReviewUsesTheActualBatchStateAndNeverCountsTheImportAsMeasurement() = fixture { names, store ->
        val id = UUID.randomUUID().toString()
        HealthOriginalStore(context, names.originals, names.originalRoot(context)).use { originals ->
            originals.createJob(HealthImportJob(id, "content://overview.test/table", now))
            val original = originals.importOriginal(id, "time,steps".byteInputStream(), "table.csv", "text/csv", "file")
            originals.updateJob(id) { it.copy(state = HealthImportState.TABLE_REVIEW, originalId = original.id) }
            HealthTableStore(context, names.records).use { tables ->
                tables.begin(id, original, "csv")
                assertTrue(load(names, store).attention.isEmpty())
                tables.append(id, listOf(HealthTableRow(1, mapOf("time" to "2024-11-04T08:00:00Z", "steps" to "1000"))))
                tables.finishReading(id, listOf("time", "steps"))
                val snapshot = load(names, store)
                assertFalse(snapshot.hasRecords)
                assertEquals(HealthOverviewReviewKind.TABLE, (snapshot.attention.single() as HealthOverviewAttention.Review).kind)
                val mapping = HealthTableMapping(HealthMetric.STEPS, mapOf("steps" to "steps"), "time", unit = "steps")
                tables.mapping(id, tables.batch(id)!!.mappingRevision, mapping, validate = true)
                tables.step(id)
                val ready = requireNotNull(tables.batch(id))
                assertEquals(HealthTableState.READY, ready.state)
                tables.confirmSave(id, ready.mappingRevision)
                tables.step(id)
                assertEquals(HealthTableState.SAVED, tables.batch(id)!!.state)
                val saved = load(names, store)
                assertTrue(saved.attention.isEmpty())
                assertTrue(saved.hasRecords)
            }
        }
    }
    @Test fun sleepSummaryAndCurrentAlertHonorVersionAndAuthorization() = fixture { names, store ->
        val record = seedHealthSleep(store, now, zone)
        HealthReminderStore(context, names.reminders).use {
            it.save(it.settings().copy(sleepChanges = true), now)
            assertTrue(HealthSleepAlertEngine.evaluate(context, it, now, zone, names.records, names.privacy))
        }
        val initial = load(names, store)
        assertEquals(360, initial.derived.sleep!!.mean!!.toInt())
        assertNotNull(initial.derived.alert)
        store.save(record.editable().copy(values = mapOf("sleep_duration" to "8")))
        assertNull(load(names, store).derived.alert)
        HealthPrivacyStore(context, names.privacy).use { privacy ->
            privacy.change(HealthPrivacyOption.CONFIRMED_METRICS, false, privacy.policy().version)
            val blocked = load(names, store)
            assertFalse(blocked.derived.permitted)
            assertNull(blocked.derived.sleep)
            assertNotNull(blocked.metrics.single { it.metric == HealthMetric.SLEEP_DURATION }.record)
            assertTrue(privacy.page().entries.any { it.scope.purpose == HealthAccessPurpose.OVERVIEW })
        }
    }
}

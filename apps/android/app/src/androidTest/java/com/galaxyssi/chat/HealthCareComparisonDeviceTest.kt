package com.galaxyssi.chat

import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class HealthCareComparisonDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private fun fixture(test: (HealthOverviewDatabases, HealthRecordStore, HealthCareStore) -> Unit) {
        val names = HealthOverviewDatabases(UUID.randomUUID().toString())
        try {
            HealthRecordStore(context, names.records).use { records -> HealthCareStore(context, names.care).use { care ->
                care.configure(true, care.settings().version); test(names, records, care)
            } }
        } finally { listOf(names.records, names.care, names.privacy, names.reminders).forEach(context::deleteDatabase) }
    }
    private fun save(records: HealthRecordStore, value: String, at: Long) = (records.save(HealthDraft(HealthMetric.GLUCOSE,
        mapOf("glucose" to value), "mmol/L", at, condition = "fasting", reference = "4-6")) as HealthSaveResult.Saved).record
    private fun evaluate(names: HealthOverviewDatabases, care: HealthCareStore): HealthCareConcern {
        HealthCareEngine.evaluate(context, names)
        return care.forMetric(HealthMetric.GLUCOSE)!!
    }
    @Test fun newReadingAndPriorConfirmedContextSurviveReopenWithoutClosingConcern(): Unit = fixture { names, records, care ->
        val now = System.currentTimeMillis()
        val old = save(records, "6.3", now - 86_400_000)
        val initial = evaluate(names, care)
        val confirmed = HealthCareContext(HealthCareRecordRef(old.id, old.revision), HealthCareTruth.YES, HealthCareTruth.NO,
            HealthCareTruth.NO, HealthCareSpecimen.LAB_PLASMA, 8, HealthCareTruth.NO, now)
        care.confirmContext(initial.id, initial.revision, confirmed)
        evaluate(names, care)
        val next = save(records, "5.4", now - 1000)
        val updated = evaluate(names, care)
        assertEquals(initial.id, updated.id); assertEquals(HealthCareStage.REASSESS, updated.stage)
        assertEquals(confirmed, updated.assessment.comparison!!.previousContext)
        assertNull(updated.context); assertNull(updated.target); assertTrue(updated.actions.isEmpty())
        assertEquals(HealthCareRecordRef(next.id, next.revision), updated.assessment.sample!!.record)
        HealthCareStore(context, names.care).use { assertEquals(updated, it.concern(updated.id)) }
        assertEquals(updated, evaluate(names, care))
        val prompt = JSONObject(HealthCareDiscussionPolicy.snapshot(updated)).getJSONObject("result_comparison")
        assertEquals("6.3", prompt.getJSONObject("before").getJSONObject("values").getString("glucose"))
        assertEquals("5.4", prompt.getJSONObject("after").getJSONObject("values").getString("glucose"))
        assertFalse(prompt.getBoolean("clinical_direction_verified"))
        context.openOrCreateDatabase(names.care, 0, null).use { db ->
            db.rawQuery("SELECT payload FROM concerns", null).use {
                assertTrue(it.moveToFirst()); assertFalse(it.getBlob(0).toString(Charsets.UTF_8).contains("previous_context"))
            }
        }
    }
    @Test fun deletingPreviousMeasurementRemovesItFromActiveModelSnapshot(): Unit = fixture { names, records, care ->
        val now = System.currentTimeMillis()
        val old = save(records, "6.3", now - 86_400_000); evaluate(names, care)
        save(records, "5.4", now - 1000)
        assertNotNull(evaluate(names, care).assessment.comparison)
        assertTrue(records.delete(old.id, old.revision))
        val updated = evaluate(names, care)
        assertNull(updated.assessment.comparison)
        assertTrue(JSONObject(HealthCareDiscussionPolicy.snapshot(updated)).isNull("result_comparison"))
        assertEquals(HealthCareStage.REASSESS, updated.stage)
    }
    @Test fun changingAnOldResultCannotMasqueradeAsARepeatTest(): Unit = fixture { names, records, care ->
        val old = save(records, "6.3", System.currentTimeMillis() - 1000); evaluate(names, care)
        assertTrue(records.save(old.editable().copy(values = mapOf("glucose" to "5.4"))) is HealthSaveResult.Saved)
        val updated = evaluate(names, care)
        assertEquals(HealthCareComparisonKind.RECORD_CORRECTION, updated.assessment.comparison!!.kind)
        assertEquals(0, HealthCareComparisonPolicy.handoff(updated.assessment, updated.context)!!.getJSONArray("arithmetic_changes_only").length())
        assertNull(care.nextDue())
    }
    @Test fun anchorOutsideRecentPageUsesIndexedLookupInsteadOfLosingThePriorAssessment(): Unit = fixture { names, records, care ->
        val now = System.currentTimeMillis()
        val old = save(records, "6.3", now - 40 * 86_400_000L); evaluate(names, care)
        repeat(35) { save(records, "5.4", now - (35 - it) * 86_400_000L) }
        val updated = evaluate(names, care)
        assertEquals(old.id, updated.assessment.comparison!!.before.record.id)
        assertEquals(36L, records.count())
        assertEquals(updated, evaluate(names, care))
    }
}

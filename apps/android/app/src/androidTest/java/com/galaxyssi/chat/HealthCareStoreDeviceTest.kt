package com.galaxyssi.chat

import android.content.ContentValues
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import org.junit.Assert.*
import org.junit.Test

class HealthCareStoreDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val now get() = System.currentTimeMillis() - 60_000
    private fun fixture(test: (HealthOverviewDatabases, HealthCareStore) -> Unit) {
        val names = HealthOverviewDatabases(UUID.randomUUID().toString())
        try { HealthCareStore(context, names.care).use { test(names, it) } }
        finally { listOf(names.care, names.records, names.privacy).forEach { context.deleteDatabase(it) } }
    }
    private fun reading(metric: HealthMetric = HealthMetric.GLUCOSE) = HealthObservation(UUID.randomUUID().toString(), 1,
        HealthDraft(metric, metric.fields.associateWith { "6.3" }, metric.units.first(), now, reference = "4-6"), now)
    private fun add(store: HealthCareStore, metric: HealthMetric = HealthMetric.GLUCOSE, stamp: String = UUID.randomUUID().toString()): HealthCareConcern {
        val settings = store.settings().let { if (it.enabled) it else store.configure(true, it.version) }
        val r = reading(metric)
        val a = HealthCareAssessment(HealthCareRecordRef(r.id, 1), r.draft.measuredAt, "6.3", r.draft.unit, "4-6", setOf(HealthCareSignal.REPORT_HIGH))
        return store.applyEvaluation(metric, stamp, settings.version, store.forMetric(metric)?.revision, a, now)!!
    }
    @Test fun reviewIsExplicitlyOptInAndSettingsSurviveReopen(): Unit = fixture { names, store ->
        assertFalse(store.settings().enabled)
        val settings = store.configure(true, "")
        HealthCareStore(context, names.care).use { assertEquals(settings, it.settings()) }
        assertTrue(runCatching { store.configure(false, "") }.exceptionOrNull() is HealthCareConflict)
    }
    @Test fun issuesAndHistoryAreEncryptedAndDurable(): Unit = fixture { names, store ->
        val issue = add(store)
        val updated = store.update(issue.id, issue.revision, "fixture_review") { it.copy(reviewNote = "sensitive-health-fixture", reviewedBy = "fixture") }
        HealthCareStore(context, names.care).use {
            assertEquals(updated, it.concern(issue.id)); assertEquals(listOf(updated, issue), it.history(issue.id))
        }
        context.openOrCreateDatabase(names.care, 0, null).use { db ->
            listOf("concerns", "history").forEach { table -> db.rawQuery("SELECT payload FROM $table", null).use { rows ->
                while (rows.moveToNext()) assertFalse(rows.getBlob(0).toString(Charsets.ISO_8859_1).contains("sensitive-health-fixture"))
            } }
        }
    }
    @Test fun repeatedEvaluationsDoNotDuplicateTheConcernOrHistory(): Unit = fixture { _, store ->
        val issue = add(store, stamp = "same-input")
        repeat(10) { assertEquals(issue, store.applyEvaluation(issue.metric, "same-input", store.settings().version,
            issue.revision, issue.assessment, now + 1000)) }
        assertEquals(1, store.page().items.size); assertEquals(1, store.history(issue.id).size)
    }
    @Test fun staleWorkersCannotOverwriteConfirmedContextOrUserActions(): Unit = fixture { _, store ->
        val issue = add(store)
        store.update(issue.id, issue.revision, "user_pause") { it.copy(stage = HealthCareStage.PAUSED) }
        assertTrue(runCatching { store.applyEvaluation(issue.metric, "new-input", store.settings().version,
            issue.revision, issue.assessment, now) }.exceptionOrNull() is HealthCareConflict)
        assertEquals(HealthCareStage.PAUSED, store.concern(issue.id)!!.stage)
    }
    @Test fun disabledConsentRejectsAnAlreadyComputedAssessment(): Unit = fixture { _, store ->
        val issue = add(store); val settings = store.settings(); store.configure(false, settings.version)
        assertTrue(runCatching { store.applyEvaluation(issue.metric, "new-input", settings.version,
            issue.revision, issue.assessment, now) }.exceptionOrNull() is HealthCareConflict)
    }
    @Test fun pagedIssuesAndRevisionHistoryHaveNoTotalTruncation(): Unit = fixture { _, store ->
        HealthMetric.entries.forEach { add(store, it) }
        var after: HealthCareCursor? = null; val seen = hashSetOf<String>()
        do { val page = store.page(after, limit = 5); assertTrue(page.items.size <= 5)
            page.items.forEach { assertTrue(seen.add(it.id)) }; after = page.next
        } while (after != null)
        assertEquals(HealthMetric.entries.size, seen.size)
        var item = store.forMetric(HealthMetric.GLUCOSE)!!
        repeat(65) { i -> item = store.update(item.id, item.revision, "fixture_edit") { it.copy(reviewNote = "revision $i") } }
        var revision = Int.MAX_VALUE; val history = hashSetOf<Int>()
        do { val page = store.history(item.id, revision); assertTrue(page.size <= 30)
            page.forEach { assertTrue(history.add(it.revision)) }; revision = page.lastOrNull()?.revision ?: 0
        } while (revision > 0)
        assertEquals(66, history.size)
    }
    @Test fun indexTamperingCannotRedirectAnAuthenticatedConcern(): Unit = fixture { names, store ->
        val issue = add(store)
        context.openOrCreateDatabase(names.care, 0, null).use { db ->
            db.update("concerns", ContentValues().apply { put("stage", HealthCareStage.CLOSED.name) }, "id=?", arrayOf(issue.id))
        }
        assertTrue(runCatching { store.concern(issue.id) }.isFailure)
    }
    @Test fun encryptedPayloadsCannotBeSwappedBetweenIssues(): Unit = fixture { names, store ->
        val first = add(store); val second = add(store, HealthMetric.HBA1C)
        context.openOrCreateDatabase(names.care, 0, null).use { db ->
            val bytes = db.rawQuery("SELECT payload FROM concerns WHERE id=?", arrayOf(first.id)).use { it.moveToFirst(); it.getBlob(0) }
            db.update("concerns", ContentValues().apply { put("payload", bytes) }, "id=?", arrayOf(second.id))
        }
        assertTrue(runCatching { store.concern(second.id) }.isFailure)
        assertEquals(first, store.concern(first.id))
    }
    @Test fun aProposedDeadlineDoesNotBecomeAnActiveReminder(): Unit = fixture { _, store ->
        val issue = add(store)
        val action = HealthCareAction(UUID.randomUUID().toString(), HealthCareActionKind.RECHECK, "Synthetic follow-up",
            "Fixture only", "Fixture clinician plan", dueFrom = now, dueUntil = now + 10000)
        val draft = store.update(issue.id, issue.revision, "plan_proposed") { it.copy(actions = listOf(action)) }
        assertNull(store.nextDue()); assertTrue(store.due(now + 1).isEmpty())
        val confirmed = store.update(issue.id, draft.revision, "plan_confirmed") {
            it.copy(actions = listOf(action.copy(state = HealthCareActionState.CONFIRMED, confirmedAt = now)))
        }
        assertEquals(listOf(confirmed), store.due(now + 1))
        store.update(issue.id, confirmed.revision, "pause") { it.copy(stage = HealthCareStage.PAUSED) }
        assertNull(store.nextDue())
    }
    @Test fun confirmedContextTriggersReassessmentAndDeletionDoesNotImmediatelyResurrect(): Unit = fixture { names, store ->
        store.configure(true, "")
        HealthRecordStore(context, names.records).use { records ->
            records.save(HealthDraft(HealthMetric.GLUCOSE, mapOf("glucose" to "6.3"), "mmol/L", now, reference = "4-6"))
        }
        HealthCareEngine.evaluate(context, names)
        val issue = store.forMetric(HealthMetric.GLUCOSE)!!
        assertNull(issue.assessment.guideline)
        val c = HealthCareContext(issue.assessment.record!!, HealthCareTruth.YES, HealthCareTruth.NO, HealthCareTruth.NO,
            HealthCareSpecimen.LAB_PLASMA, 8, confirmedAt = now)
        store.confirmContext(issue.id, issue.revision, c)
        assertEquals(1, HealthCareEngine.evaluate(context, names))
        val assessed = store.concern(issue.id)!!
        assertNotNull(assessed.assessment.guideline)
        assertEquals(0, HealthCareEngine.evaluate(context, names))
        store.delete(assessed.id, assessed.revision)
        assertEquals(0, HealthCareEngine.evaluate(context, names))
        assertNull(store.forMetric(HealthMetric.GLUCOSE)); assertTrue(store.history(issue.id).isEmpty())
    }
    @Test fun localDerivedDataRevocationStopsProactiveAssessment(): Unit = fixture { names, store ->
        store.configure(true, "")
        HealthRecordStore(context, names.records).use {
            it.save(HealthDraft(HealthMetric.GLUCOSE, mapOf("glucose" to "6.3"), "mmol/L", now, reference = "4-6"))
        }
        HealthPrivacyStore(context, names.privacy).use { it.change(HealthPrivacyOption.CONFIRMED_METRICS, false, it.policy().version) }
        assertEquals(0, HealthCareEngine.evaluate(context, names)); assertTrue(store.page().items.isEmpty())
    }
}

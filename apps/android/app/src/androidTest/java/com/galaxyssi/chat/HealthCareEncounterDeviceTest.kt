package com.galaxyssi.chat

import android.content.ContentValues
import android.database.sqlite.SQLiteDatabase
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import org.junit.Assert.*
import org.junit.Test

internal fun removeHealthEncounterTestTables(db: SQLiteDatabase) {
    removeHealthInstructionTestTables(db)
    db.execSQL("DROP TABLE encounter_documents")
    db.execSQL("DROP TABLE encounter_events")
    db.execSQL("DROP TABLE encounters")
}

class HealthCareEncounterDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val draft = HealthCareEncounterDraft("Synthetic consultation", "Synthetic clinic", note = "private-visit-fixture-note")
    private fun fixture(test: (HealthOverviewDatabases, HealthCareStore, HealthCareConcern) -> Unit) {
        val names = HealthOverviewDatabases(UUID.randomUUID().toString())
        try {
            val issue = HealthCareFollowUpTestFixture.confirmed(context, names)
            HealthCareStore(context, names.care).use { test(names, it, issue) }
        } finally { listOf(names.care, names.records, names.privacy, names.profile, names.reminders).forEach(context::deleteDatabase) }
    }
    private fun save(store: HealthCareStore, issue: HealthCareConcern, details: HealthCareEncounterDraft = draft,
        id: String = UUID.randomUUID().toString(), prior: Int? = null, operation: String = UUID.randomUUID().toString(),
        now: Long = System.currentTimeMillis()) = store.saveEncounter(issue.id, issue.revision, id, prior, details, operation, now)

    @Test fun storedSelfReportReopensWithoutChangingPlanOrHealthConclusion(): Unit = fixture { names, store, issue ->
        val result = save(store, issue)
        val next = store.concern(issue.id)!!
        assertEquals(issue.stage, next.stage); assertEquals(issue.assessment, next.assessment); assertEquals(issue.actions, next.actions)
        assertEquals(issue.target, next.target); assertTrue(store.reminders(issue.id).isEmpty())
        HealthCareStore(context, names.care).use {
            assertEquals(result.encounter, it.encounter(result.encounter.id))
            assertEquals(listOf(result.encounter), it.encounters(issue.id).items)
            assertEquals(result, save(it, issue, id = result.encounter.id, operation = result.operationId))
            assertEquals(next, it.concern(issue.id))
        }
    }
    @Test fun reusedOperationAndStaleEditorsCannotChangeOwnershipOrContent(): Unit = fixture { _, store, issue ->
        val first = save(store, issue)
        assertThrows(HealthCareConflict::class.java) { save(store, issue, draft.copy(note = "Different"), first.encounter.id, operation = first.operationId) }
        assertThrows(HealthCareConflict::class.java) { save(store, issue.copy(id = UUID.randomUUID().toString()), id = first.encounter.id, operation = first.operationId) }
        assertThrows(HealthCareConflict::class.java) { save(store, issue, id = first.encounter.id, prior = first.encounter.revision) }
        assertThrows(HealthCareConflict::class.java) { save(store, store.concern(issue.id)!!, id = first.encounter.id) }
        assertEquals(1, store.encounters(issue.id).items.size)
    }
    @Test fun pagesAreBoundedAndConcurrentEditsInvalidateMutableListCursor(): Unit = fixture { _, store, issue ->
        val saved = (0 until 65).map { index -> save(store, store.concern(issue.id)!!, draft.copy(note = "Synthetic visit $index")).encounter }
        val first = store.encounters(issue.id)
        assertEquals(30, first.items.size)
        val second = store.encounters(issue.id, first.next!!, expectedRevision = first.concernRevision)
        val third = store.encounters(issue.id, second.next!!, expectedRevision = second.concernRevision)
        assertEquals(saved.reversed(), first.items + second.items + third.items); assertNull(third.next)
        assertThrows(IllegalArgumentException::class.java) { store.encounters(issue.id, first.next) }
        save(store, store.concern(issue.id)!!, draft.copy(note = "Changed"), saved.first().id, saved.first().revision)
        assertThrows(HealthCareConflict::class.java) { store.encounters(issue.id, first.next, expectedRevision = first.concernRevision) }
        listOf(0, 31, 1000).forEach { limit -> assertThrows(IllegalArgumentException::class.java) { store.encounters(issue.id, limit = limit) } }
    }
    @Test fun immutableHistoryPagesSurviveLaterEditsAndClockSkew(): Unit = fixture { _, store, issue ->
        var previous = save(store, issue).encounter
        val saved = mutableListOf(previous)
        repeat(35) { index ->
            previous = save(store, store.concern(issue.id)!!, draft.copy(note = "History $index"), previous.id,
                previous.revision, now = issue.updatedAt + 1000 - index).encounter
            saved += previous
        }
        val first = store.encounterHistory(issue.id, previous.id)
        save(store, store.concern(issue.id)!!, draft.copy(note = "Later"), previous.id, previous.revision)
        val second = store.encounterHistory(issue.id, previous.id, first.next!!)
        assertEquals(saved.reversed(), first.items + second.items); assertNull(second.next)
        assertTrue(store.encounterHistory(UUID.randomUUID().toString(), previous.id).items.isEmpty())
    }
    @Test fun contentAndDatesAreEncryptedAndIndexTamperingFailsClosed(): Unit = fixture { names, store, issue ->
        val saved = save(store, issue, draft.copy(plannedAt = 1_900_000_000_123L)).encounter
        context.openOrCreateDatabase(names.care, 0, null).use { db ->
            listOf("encounters", "encounter_events").forEach { table -> db.rawQuery("SELECT payload FROM $table", null).use { row ->
                assertTrue(row.moveToFirst()); val raw = row.getBlob(0).toString(Charsets.ISO_8859_1)
                assertFalse(raw.contains(draft.note)); assertFalse(raw.contains(draft.facility)); assertFalse(raw.contains("1900000000123"))
            } }
            db.update("encounters", ContentValues().apply { put("concern_id", UUID.randomUUID().toString()) }, "id=?", arrayOf(saved.id))
        }
        assertThrows(IllegalStateException::class.java) { store.encounter(saved.id) }
    }
    @Test fun writeFailureRollsBackConcernHistoryAndEncounter(): Unit = fixture { names, store, issue ->
        val before = store.history(issue.id)
        context.openOrCreateDatabase(names.care, 0, null).use { it.execSQL(
            "CREATE TRIGGER fail_encounter BEFORE INSERT ON encounter_events BEGIN SELECT RAISE(ABORT, 'synthetic failure'); END") }
        try {
            assertThrows(android.database.sqlite.SQLiteException::class.java) { save(store, issue) }
            assertEquals(issue, store.concern(issue.id)); assertEquals(before, store.history(issue.id)); assertTrue(store.encounters(issue.id).items.isEmpty())
        } finally { context.openOrCreateDatabase(names.care, 0, null).use { it.execSQL("DROP TRIGGER fail_encounter") } }
    }
    @Test fun deletingVisitPurgesItsHistoryAndPreventsOldRetryFromRevivingIt(): Unit = fixture { _, store, issue ->
        val saved = save(store, issue)
        store.deleteEncounter(issue.id, saved.encounter.revision, saved.encounter.id, saved.encounter.revision, System.currentTimeMillis())
        assertNull(store.encounter(saved.encounter.id)); assertTrue(store.encounters(issue.id).items.isEmpty())
        assertTrue(store.encounterHistory(issue.id, saved.encounter.id).items.isEmpty())
        assertThrows(HealthCareConflict::class.java) { save(store, issue, id = saved.encounter.id, operation = saved.operationId) }
    }
    @Test fun ignoredCurrentRowWriteRollsBackTheReceiptAndConcern(): Unit = fixture { names, store, issue ->
        val before = store.history(issue.id)
        context.openOrCreateDatabase(names.care, 0, null).use { it.execSQL(
            "CREATE TRIGGER ignore_encounter BEFORE INSERT ON encounters BEGIN SELECT RAISE(IGNORE); END") }
        try {
            assertThrows(IllegalStateException::class.java) { save(store, issue) }
            assertEquals(issue, store.concern(issue.id)); assertEquals(before, store.history(issue.id)); assertTrue(store.encounters(issue.id).items.isEmpty())
            context.openOrCreateDatabase(names.care, 0, null).use { db -> db.rawQuery("SELECT COUNT(*) FROM encounter_events", null).use {
                assertTrue(it.moveToFirst()); assertEquals(0, it.getInt(0))
            } }
        } finally { context.openOrCreateDatabase(names.care, 0, null).use { it.execSQL("DROP TRIGGER ignore_encounter") } }
    }
    @Test fun deletingConcernPurgesAllVisitRows(): Unit = fixture { names, store, issue ->
        save(store, issue); store.delete(issue.id, store.concern(issue.id)!!.revision)
        context.openOrCreateDatabase(names.care, 0, null).use { db ->
            listOf("encounters", "encounter_events").forEach { table -> db.rawQuery("SELECT COUNT(*) FROM $table", null).use {
                assertTrue(it.moveToFirst()); assertEquals(0, it.getInt(0))
            } }
        }
        assertThrows(HealthCareConflict::class.java) { store.encounters(issue.id) }
    }
    @Test fun schemaElevenMigrationKeepsFeedbackWithoutInventingVisits(): Unit = fixture { names, store, issue ->
        val feedback = store.recordActionFeedback(issue.id, issue.revision, issue.actions.first().id, HealthCareFeedbackKind.PARTIAL,
            "Synthetic previous feedback", UUID.randomUUID().toString(), System.currentTimeMillis())
        val before = store.concern(issue.id)!!
        store.close()
        context.openOrCreateDatabase(names.care, 0, null).use { removeHealthEncounterTestTables(it); it.version = 11 }
        HealthCareStore(context, names.care).use {
            assertEquals(before, it.concern(issue.id)); assertEquals(listOf(feedback), it.feedback(issue.id).items)
            assertTrue(it.encounters(issue.id).items.isEmpty()); save(it, before)
        }
        context.openOrCreateDatabase(names.care, 0, null).use { assertEquals(19, it.version) }
    }
}

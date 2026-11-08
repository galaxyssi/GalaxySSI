package com.galaxyssi.chat

import android.content.ContentValues
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import org.junit.Assert.*
import org.junit.Test

class HealthCareFeedbackDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private fun fixture(test: (HealthOverviewDatabases, HealthCareStore, HealthCareConcern) -> Unit) {
        val names = HealthOverviewDatabases(UUID.randomUUID().toString())
        try {
            val issue = HealthCareFollowUpTestFixture.confirmed(context, names)
            HealthCareStore(context, names.care).use { test(names, it, issue) }
        } finally { listOf(names.care, names.records, names.privacy, names.reminders).forEach(context::deleteDatabase) }
    }
    private fun save(store: HealthCareStore, issue: HealthCareConcern, kind: HealthCareFeedbackKind = HealthCareFeedbackKind.PARTIAL,
        id: String = UUID.randomUUID().toString(), note: String = "Synthetic feedback, not a clinical result",
        at: Long = System.currentTimeMillis(), actionId: String = issue.actions.first().id) =
        store.recordActionFeedback(issue.id, issue.revision, actionId, kind, note, id, at)
    private fun schedule(names: HealthOverviewDatabases, store: HealthCareStore, issue: HealthCareConcern) =
        store.scheduleReminder(issue.id, issue.actions.first().id, issue.revision, null,
            HealthPrivacyStore(context, names.privacy).use { it.policy() }, issue.inputVersion,
            System.currentTimeMillis() + 60000, System.currentTimeMillis())

    @Test fun partialAndBarrierKeepReminderAndCompletionCancelsAtomically(): Unit = fixture { names, store, issue ->
        val reminder = schedule(names, store, issue)
        var current = issue
        listOf(HealthCareFeedbackKind.PARTIAL, HealthCareFeedbackKind.BARRIER).forEach { kind ->
            save(store, current, kind); current = store.concern(issue.id)!!
            assertEquals(HealthCareActionState.CONFIRMED, current.actions.first().state)
            assertEquals(reminder, store.reminder(reminder.actionId))
            assertEquals(issue.assessment, current.assessment)
        }
        save(store, current, HealthCareFeedbackKind.COMPLETED)
        assertEquals(HealthCareReminderState.CANCELLED, store.reminder(reminder.actionId)!!.state)
        assertEquals(HealthCareActionState.CONFIRMED, store.concern(issue.id)!!.actions.last().state)
        assertEquals(3, store.feedback(issue.id).items.size)
    }
    @Test fun duplicateOperationReturnsSameReceiptAfterReopenWithoutNewRevision(): Unit = fixture { names, store, issue ->
        val first = save(store, issue)
        HealthCareStore(context, names.care).use { reopened ->
            assertEquals(first, save(reopened, issue, id = first.feedback.id, at = System.currentTimeMillis() + 1000))
            assertEquals(issue.revision + 1, reopened.concern(issue.id)!!.revision)
            assertEquals(listOf(first), reopened.feedback(issue.id).items)
        }
    }
    @Test fun reusedOperationCannotChangeNoteKindActionOrConcern(): Unit = fixture { _, store, issue ->
        val first = save(store, issue)
        assertThrows(HealthCareConflict::class.java) { save(store, issue, id = first.feedback.id, note = "Changed") }
        assertThrows(HealthCareConflict::class.java) { save(store, issue, HealthCareFeedbackKind.BARRIER, first.feedback.id) }
        assertThrows(HealthCareConflict::class.java) { save(store, issue, id = first.feedback.id, actionId = issue.actions.last().id) }
        assertThrows(HealthCareConflict::class.java) { save(store, issue.copy(id = UUID.randomUUID().toString()), id = first.feedback.id) }
        assertThrows(HealthCareConflict::class.java) { save(store, issue, id = UUID.randomUUID().toString()) }
        assertEquals(1, store.feedback(issue.id).items.size)
    }
    @Test fun historyPagesByRevisionDespiteClockSkewAndConcurrentNewFeedback(): Unit = fixture { _, store, issue ->
        val expected = mutableListOf<HealthCareFeedbackReceipt>()
        repeat(105) { index -> expected += save(store, store.concern(issue.id)!!, note = "Synthetic page $index",
            at = issue.updatedAt + 1000 - index, actionId = issue.actions[index % 2].id) }
        val first = store.feedback(issue.id)
        assertEquals(30, first.items.size)
        val later = save(store, store.concern(issue.id)!!)
        val actual = first.items.toMutableList(); var cursor = first.next
        while (cursor != null) {
            val page = store.feedback(issue.id, beforeRevision = cursor)
            assertTrue(page.items.size <= 30); actual += page.items; cursor = page.next
        }
        assertEquals(expected.reversed(), actual); assertEquals(105, actual.map { it.feedback.id }.toSet().size)
        assertEquals(later, store.feedback(issue.id).items.first())
        assertTrue(store.feedback(issue.id, issue.actions.last().id).items.all { it.actionId == issue.actions.last().id })
    }
    @Test fun payloadsAreEncryptedAndMetadataTamperingFailsClosed(): Unit = fixture { names, store, issue ->
        val receipt = save(store, issue, note = "private-fixture-barrier-unique")
        context.openOrCreateDatabase(names.care, 0, null).use { db ->
            db.rawQuery("SELECT payload FROM action_feedback", null).use {
                assertTrue(it.moveToFirst()); val encoded = it.getBlob(0).toString(Charsets.ISO_8859_1)
                assertFalse(encoded.contains(receipt.feedback.note)); assertFalse(encoded.contains(receipt.actionTitle))
            }
            db.update("action_feedback", ContentValues().apply { put("action_id", issue.actions.last().id) }, null, null)
        }
        assertThrows(IllegalStateException::class.java) { store.feedback(issue.id) }
    }
    @Test fun failedReceiptInsertRollsBackConcernHistoryAndReminder(): Unit = fixture { names, store, issue ->
        val reminder = schedule(names, store, issue); val history = store.history(issue.id)
        context.openOrCreateDatabase(names.care, 0, null).use { it.execSQL(
            "CREATE TRIGGER fail_feedback BEFORE INSERT ON action_feedback BEGIN SELECT RAISE(ABORT, 'synthetic failure'); END") }
        try {
            assertThrows(android.database.sqlite.SQLiteException::class.java) { save(store, issue, HealthCareFeedbackKind.COMPLETED) }
            assertEquals(issue, store.concern(issue.id)); assertEquals(history, store.history(issue.id))
            assertEquals(reminder, store.reminder(reminder.actionId)); assertTrue(store.feedback(issue.id).items.isEmpty())
        } finally { context.openOrCreateDatabase(names.care, 0, null).use { it.execSQL("DROP TRIGGER fail_feedback") } }
    }
    @Test fun schemaTenMigrationKeepsLegacyNotesWithoutInventingHistory(): Unit = fixture { names, store, issue ->
        val legacy = store.update(issue.id, issue.revision, "synthetic_legacy") { it.copy(actions = it.actions.map { action ->
            if (action.id == issue.actions.first().id) action.copy(state = HealthCareActionState.DONE, outcome = "Old completion note") else action }) }
        store.close()
        context.openOrCreateDatabase(names.care, 0, null).use { removeHealthEncounterTestTables(it); it.execSQL("DROP TABLE action_feedback"); it.version = 10 }
        HealthCareStore(context, names.care).use {
            assertEquals(legacy, it.concern(issue.id)); assertTrue(it.feedback(issue.id).items.isEmpty())
            save(it, legacy, actionId = legacy.actions.last().id)
            assertEquals(1, it.feedback(issue.id).items.size)
        }
        context.openOrCreateDatabase(names.care, 0, null).use { assertEquals(12, it.version) }
    }
    @Test fun deletionRemovesFeedbackAndOldOperationCannotReviveConcern(): Unit = fixture { _, store, issue ->
        val receipt = save(store, issue); store.delete(issue.id, receipt.revision)
        assertTrue(store.feedback(issue.id).items.isEmpty()); assertNull(store.concern(issue.id))
        assertThrows(HealthCareConflict::class.java) { save(store, issue, id = receipt.feedback.id) }
    }
    @Test fun pagingIsBoundedAndUsesActionIndex(): Unit = fixture { names, store, issue ->
        save(store, issue)
        listOf(0, 31, 1000).forEach { limit -> assertThrows(IllegalArgumentException::class.java) { store.feedback(issue.id, limit = limit) } }
        context.openOrCreateDatabase(names.care, 0, null).use { db ->
            db.rawQuery("EXPLAIN QUERY PLAN SELECT id FROM action_feedback WHERE concern_id=? AND action_id=? AND revision<? ORDER BY revision DESC LIMIT 31",
                arrayOf(issue.id, issue.actions.first().id, Int.MAX_VALUE.toString())).use { row ->
                assertTrue(row.moveToFirst()); assertTrue(row.getString(3).contains("care_feedback_action"))
            }
        }
    }
}

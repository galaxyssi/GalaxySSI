package com.galaxyssi.chat

import android.content.ContentValues
import android.os.SystemClock
import androidx.test.platform.app.InstrumentationRegistry
import java.time.ZoneId
import java.util.UUID
import org.junit.Assert.*
import org.junit.Test

class HealthCareAgendaDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val now get() = System.currentTimeMillis() - 60_000
    private val end get() = HealthCareAgenda.dayEnd(System.currentTimeMillis(), ZoneId.systemDefault())
    private fun fixture(test: (HealthOverviewDatabases, HealthCareStore) -> Unit) {
        val names = HealthOverviewDatabases(UUID.randomUUID().toString())
        try { HealthCareStore(context, names.care).use { it.configure(true, ""); test(names, it) } }
        finally { listOf(names.care, names.records, names.privacy, names.reminders, names.profile).forEach(context::deleteDatabase) }
    }
    private fun add(store: HealthCareStore, metric: HealthMetric = HealthMetric.GLUCOSE, count: Int = 1): HealthCareConcern {
        val at = now
        val assessment = HealthCareAssessment(HealthCareRecordRef(UUID.randomUUID().toString(), 1), at, "6.3", metric.units.first(), "4-6",
            setOf(HealthCareSignal.REPORT_HIGH))
        val issue = store.applyEvaluation(metric, UUID.randomUUID().toString(), store.settings().version, null, assessment, at)!!
        return store.update(issue.id, issue.revision, "fixture_actions") { it.copy(actions = (1..count).map { n ->
            HealthCareAction(UUID.randomUUID().toString(), HealthCareActionKind.CONTEXT, "合成行动 $n", "隔离测试", "合成资料",
                HealthCareActionState.CONFIRMED, at, at + 86400000, at, basis = HealthCareFollowUpPolicy.basis(issue))
        }) }
    }
    private fun prepare(store: HealthCareStore) { while (!store.prepareAgendaBatch()) { } }

    @Test fun globalKeysetPagesKeepAllActionsAndUseIndex(): Unit = fixture { names, store ->
        val ids = HealthMetric.entries.take(7).flatMap { add(store, it, 30).actions }.map { it.id }.toSet()
        prepare(store)
        var cursor: HealthCareAgendaCursor? = null; val seen = mutableListOf<String>(); val elapsed = mutableListOf<Long>()
        val dayEnd = end
        do {
            val start = SystemClock.elapsedRealtimeNanos()
            val page = store.agenda(HealthCareAgendaFilter.TODAY, dayEnd, cursor)
            elapsed += (SystemClock.elapsedRealtimeNanos() - start) / 1_000_000
            assertTrue(page.items.size <= 30); seen += page.items.map { it.action.id }; cursor = page.next
        } while (cursor != null)
        assertEquals(210, seen.size); assertEquals(ids, seen.toSet())
        android.util.Log.i("HealthAgendaFixture", "page_ms=" + elapsed.joinToString(","))
        context.openOrCreateDatabase(names.care, 0, null).use { db ->
            db.rawQuery("EXPLAIN QUERY PLAN SELECT concern_id,action_id FROM action_agenda WHERE bucket=0 AND due<? ORDER BY due,concern_id,action_id LIMIT 31", arrayOf(dayEnd.toString())).use {
                assertTrue(it.moveToFirst()); assertTrue(it.getString(3).contains("care_action_pages"))
            }
            db.rawQuery("PRAGMA table_info(action_agenda)", null).use { rows ->
                val columns = buildList { while (rows.moveToNext()) add(rows.getString(1)) }
                assertEquals(listOf("concern_id", "action_id", "revision", "bucket", "due"), columns)
            }
        }
    }
    @Test fun changedDataAndNewDayRejectOldCursor(): Unit = fixture { _, store ->
        val issue = add(store, count = 2); prepare(store)
        val cursor = store.agenda(HealthCareAgendaFilter.TODAY, end, limit = 1).next!!
        assertThrows(HealthCareConflict::class.java) { store.agenda(HealthCareAgendaFilter.TODAY, end + 86400000, cursor) }
        assertThrows(HealthCareConflict::class.java) { store.agenda(HealthCareAgendaFilter.REVIEW, end, cursor) }
        store.update(issue.id, issue.revision, "fixture_pause") { it.copy(stage = HealthCareStage.PAUSED) }
        assertThrows(HealthCareConflict::class.java) { store.agenda(HealthCareAgendaFilter.TODAY, end, cursor) }
        assertEquals(2, store.agenda(HealthCareAgendaFilter.REVIEW, end).items.size)
        assertTrue(store.agenda(HealthCareAgendaFilter.TODAY, end).items.isEmpty())
    }
    @Test fun outcomeAndDeletionUpdateProjectionAtomically(): Unit = fixture { _, store ->
        val issue = add(store); prepare(store)
        val done = store.finishAction(issue.id, issue.revision, issue.actions.single().id, "合成执行记录", System.currentTimeMillis())
        assertEquals("合成执行记录", store.agenda(HealthCareAgendaFilter.RECORDED, end).items.single().action.outcome)
        assertTrue(store.agenda(HealthCareAgendaFilter.TODAY, end).items.isEmpty())
        store.delete(done.id, done.revision)
        assertTrue(store.agenda(HealthCareAgendaFilter.RECORDED, end).items.isEmpty())
    }
    @Test fun rescheduleDeliveryAndCancellationDoNotCompleteAction(): Unit = fixture { names, store ->
        val issue = add(store); prepare(store); val action = issue.actions.single()
        val privacy = HealthPrivacyStore(context, names.privacy).use { it.policy() }
        val scheduled = store.scheduleReminder(issue.id, action.id, issue.revision, null, privacy, issue.inputVersion, end + 1000, now)
        assertTrue(store.agenda(HealthCareAgendaFilter.TODAY, end).items.isEmpty())
        assertEquals(scheduled.dueAt, store.agenda(HealthCareAgendaFilter.LATER, end).items.single().due)
        store.markReminderDelivered(action.id, scheduled.token, end + 2000)
        assertEquals(HealthCareActionState.CONFIRMED, store.agenda(HealthCareAgendaFilter.LATER, end).items.single().action.state)
        store.cancelReminder(action.id, scheduled.token, end + 3000)
        assertEquals(action.id, store.agenda(HealthCareAgendaFilter.TODAY, end).items.single().action.id)
        assertNull(store.agenda(HealthCareAgendaFilter.TODAY, end).items.single().reminder)
    }
    @Test fun unscheduledAndChangedBasisAreNotPresentedAsReadyToday(): Unit = fixture { _, store ->
        val issue = add(store, count = 3)
        store.update(issue.id, issue.revision, "fixture_states") { it.copy(actions = listOf(
            it.actions[0].copy(dueFrom = null, dueUntil = null), it.actions[1].copy(basis = ""),
            it.actions[2].copy(state = HealthCareActionState.PROPOSED))) }
        prepare(store)
        assertTrue(store.agenda(HealthCareAgendaFilter.TODAY, end).items.isEmpty())
        assertEquals(1, store.agenda(HealthCareAgendaFilter.LATER, end).items.size)
        assertEquals(2, store.agenda(HealthCareAgendaFilter.REVIEW, end).items.size)
    }
    @Test fun legacyBackfillResumesAndKeepsConcurrentUpdates(): Unit = fixture { names, store ->
        val first = add(store, HealthMetric.GLUCOSE, 2); val second = add(store, HealthMetric.HBA1C, 2)
        store.close()
        context.openOrCreateDatabase(names.care, 0, null).use {
            removeHealthEncounterTestTables(it)
            it.execSQL("DROP TABLE action_feedback"); it.execSQL("DROP TABLE action_agenda"); it.execSQL("DROP TABLE action_agenda_state"); it.version = 9
        }
        HealthCareStore(context, names.care).use {
            assertFalse(it.prepareAgendaBatch(1))
            assertThrows(IllegalStateException::class.java) { it.agenda(HealthCareAgendaFilter.TODAY, end) }
            it.update(first.id, first.revision, "fixture_pause") { old -> old.copy(stage = HealthCareStage.PAUSED) }
        }
        HealthCareStore(context, names.care).use {
            prepare(it)
            assertEquals(second.actions.map { a -> a.id }.toSet(), it.agenda(HealthCareAgendaFilter.TODAY, end).items.map { a -> a.action.id }.toSet())
            assertEquals(2, it.agenda(HealthCareAgendaFilter.REVIEW, end).items.size)
        }
        context.openOrCreateDatabase(names.care, 0, null).use { assertEquals(18, it.version) }
    }
    @Test fun indexTamperingIsRejectedAndTransactionRollsBack(): Unit = fixture { names, store ->
        val issue = add(store); prepare(store)
        context.openOrCreateDatabase(names.care, 0, null).use {
            it.update("action_agenda", ContentValues().apply { put("due", 1L) }, null, null)
        }
        assertThrows(IllegalStateException::class.java) { store.agenda(HealthCareAgendaFilter.TODAY, end) }
        assertEquals(issue, store.concern(issue.id))
    }
    @Test fun invalidPageSizesAndBatchSizesAreRejected(): Unit = fixture { _, store ->
        prepare(store)
        listOf(0, 31, Int.MAX_VALUE).forEach { size ->
            assertThrows(IllegalArgumentException::class.java) { store.agenda(HealthCareAgendaFilter.TODAY, end, limit = size) }
            assertThrows(IllegalArgumentException::class.java) { store.prepareAgendaBatch(size) }
        }
    }
}

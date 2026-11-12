package com.galaxyssi.chat

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Test

internal fun removeHealthVisitFollowUpTestTables(db: SQLiteDatabase) {
    db.execSQL("DROP TABLE visit_followups"); db.execSQL("DROP TABLE visit_followup_events")
}
internal class HealthCareVisitFollowUpFixture(private val context: Context) : AutoCloseable {
    val names = HealthOverviewDatabases(UUID.randomUUID().toString())
    val repository = HealthCareVisitFollowUpRepository(context, names)
    val issue = HealthCareFollowUpTestFixture.confirmed(context, names)
    val visit = HealthCareStore(context, names.care).use { store ->
        val now = System.currentTimeMillis()
        store.saveEncounter(issue.id, issue.revision, UUID.randomUUID().toString(), null,
            HealthCareEncounterDraft("合成随访就诊", state = HealthCareEncounterState.ATTENDED, attendedAt = now), UUID.randomUUID().toString(), now).encounter
    }
    fun snapshot(before: Int = Int.MAX_VALUE) = repository.load(issue.id, visit.id, before)
    fun record(input: HealthCareVisitFollowUpInput, operation: String = UUID.randomUUID().toString()) = repository.record(snapshot(), input, operation)
    fun start() = record(HealthCareVisitFollowUpInput(HealthCareVisitFollowUpKind.START, goal = "合成测试：记录功能与睡眠"))
    override fun close() { listOf(names.care, names.records, names.privacy, names.profile, names.reminders).forEach(context::deleteDatabase) }
}

class HealthCareVisitFollowUpDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private fun fixture(test: (HealthCareVisitFollowUpFixture) -> Unit) = HealthCareVisitFollowUpFixture(context).use(test)
    private fun id() = UUID.randomUUID().toString()
    private fun note(text: String) = HealthCareVisitFollowUpInput(HealthCareVisitFollowUpKind.CHECK_IN, note = text)

    @Test fun encryptedJournalReopensWithoutChangingCarePlanOrAssessment(): Unit = fixture { f ->
        val original = f.snapshot().visit.issue
        val first = f.start(); val next = f.record(note("private-followup-note"))
        HealthCareStore(context, f.names.care).use { store ->
            assertEquals(next.value, store.visitFollowUp(f.visit.id)); assertEquals(original.actions, store.concern(f.issue.id)!!.actions)
            assertEquals(original.assessment, store.concern(f.issue.id)!!.assessment); assertEquals(original.stage, store.concern(f.issue.id)!!.stage)
            assertEquals(original.target, store.concern(f.issue.id)!!.target); assertTrue(store.reminders(f.issue.id).isEmpty())
            assertEquals(listOf(next, first), store.visitFollowUpHistory(f.issue.id, f.visit.id).items)
        }
        context.openOrCreateDatabase(f.names.care, 0, null).use { db ->
            listOf("visit_followups", "visit_followup_events").forEach { table -> db.rawQuery("SELECT payload FROM $table", null).use { rows ->
                while(rows.moveToNext()) assertFalse(rows.getBlob(0).toString(Charsets.UTF_8).contains("private-followup-note"))
            } }
        }
    }
    @Test fun changedReplayAndStaleWritersCannotOverwriteHistory(): Unit = fixture { f ->
        f.start(); val snapshot = f.snapshot(); val operation = id(); val input = note("原始记录")
        val saved = f.repository.record(snapshot, input, operation)
        HealthCareStore(context, f.names.care).use { store ->
            assertEquals(saved, store.recordVisitFollowUp(f.issue.id, snapshot.visit.issue.revision, f.visit.id, f.visit.revision,
                snapshot.followUp!!.revision, input, operation, System.currentTimeMillis()))
            assertThrows(HealthCareConflict::class.java) { store.recordVisitFollowUp(f.issue.id, snapshot.visit.issue.revision, f.visit.id, f.visit.revision,
                snapshot.followUp.revision, note("篡改重放"), operation, System.currentTimeMillis()) }
        }
        assertThrows(HealthCareConflict::class.java) { f.repository.record(snapshot, note("过期写入"), id()) }
        assertEquals(2, f.snapshot().history.items.size)
    }
    @Test fun historyUsesBoundedStablePagesAcrossNewWrites(): Unit = fixture { f ->
        val expected = mutableListOf(f.start())
        repeat(64) { expected += f.record(note("合成分页记录 $it")) }
        val first = f.snapshot().history
        assertEquals(30, first.items.size)
        f.record(note("读取第一页后新增"))
        val second = f.snapshot(first.next!!).history
        val third = f.snapshot(second.next!!).history
        assertEquals(expected.reversed(), first.items + second.items + third.items); assertNull(third.next)
        HealthCareStore(context, f.names.care).use { store ->
            listOf(0, 31, 1000).forEach { assertThrows(IllegalArgumentException::class.java) { store.visitFollowUpHistory(f.issue.id, f.visit.id, limit = it) } }
            assertTrue(store.visitFollowUpHistory(id(), f.visit.id).items.isEmpty())
        }
    }
    @Test fun deletionPreservesVisitPlanAndPreventsStaleResurrection(): Unit = fixture { f ->
        f.start(); val old = f.snapshot(); f.repository.delete(old)
        assertNull(f.snapshot().followUp); assertTrue(f.snapshot().history.items.isEmpty())
        assertThrows(HealthCareConflict::class.java) { f.repository.record(old, note("迟到的结果"), id()) }
        HealthCareStore(context, f.names.care).use { store ->
            assertEquals(f.visit, store.encounter(f.visit.id)); assertEquals(f.issue.actions, store.concern(f.issue.id)!!.actions)
        }
    }
    @Test fun deletingParentPurgesAllFollowUpRows(): Unit = fixture { f ->
        f.start()
        HealthCareStore(context, f.names.care).use { store ->
            store.deleteEncounter(f.issue.id, store.concern(f.issue.id)!!.revision, f.visit.id, f.visit.revision, System.currentTimeMillis())
            assertNull(store.visitFollowUp(f.visit.id)); assertTrue(store.visitFollowUpHistory(f.issue.id, f.visit.id).items.isEmpty())
        }
    }
    @Test fun sourceChangesRequireReviewButNeverEraseSelfReports(): Unit = fixture { f ->
        val first = f.start()
        HealthCareStore(context, f.names.care).use { store -> store.saveEncounter(f.issue.id, store.concern(f.issue.id)!!.revision,
            f.visit.id, f.visit.revision, f.visit.details.copy(note = "修订就诊内容"), id(), System.currentTimeMillis()) }
        val added = f.record(note("新的感受"))
        assertEquals(first.value.encounterRevision, added.value.encounterRevision)
        val reviewed = f.record(HealthCareVisitFollowUpInput(HealthCareVisitFollowUpKind.REVIEW, note = "核对后继续", decision = HealthCareVisitReviewDecision.CONTINUE))
        assertEquals(f.snapshot().visit.selected!!.revision, reviewed.value.encounterRevision)
        assertEquals(3, f.snapshot().history.items.size)
    }
    @Test fun privacyRevocationRejectsPreviouslyOpenedEditor(): Unit = fixture { f ->
        f.start(); val old = f.snapshot()
        HealthPrivacyStore(context, f.names.privacy).use { it.change(HealthPrivacyOption.PROFILE_CONTEXT, false, it.policy().version) }
        assertThrows(HealthPrivacyConflict::class.java) { f.repository.record(old, note("不能写入"), id()) }
        assertThrows(HealthAccessBlocked::class.java) { f.snapshot() }
        HealthCareStore(context, f.names.care).use { assertEquals(1, it.visitFollowUpHistory(f.issue.id, f.visit.id).items.size) }
    }
    @Test fun indexTamperingCannotMoveJournalToAnotherVisit(): Unit = fixture { f ->
        f.start(); val wrong = id()
        context.openOrCreateDatabase(f.names.care, 0, null).use { it.update("visit_followups", ContentValues().apply { put("encounter_id", wrong) },
            "encounter_id=?", arrayOf(f.visit.id)) }
        HealthCareStore(context, f.names.care).use { assertThrows(IllegalStateException::class.java) { it.visitFollowUp(wrong) } }
    }
    @Test fun failedWriteRollsBackParentRevisionAndReceipt(): Unit = fixture { f ->
        val before = f.snapshot()
        context.openOrCreateDatabase(f.names.care, 0, null).use { it.execSQL("CREATE TRIGGER ignore_followup BEFORE INSERT ON visit_followups BEGIN SELECT RAISE(IGNORE); END") }
        assertThrows(IllegalStateException::class.java) { f.start() }
        assertEquals(before, f.snapshot())
    }
    @Test fun schemaSixteenUpgradePreservesExistingCareAndVisits(): Unit = fixture { f ->
        val before = f.snapshot()
        context.openOrCreateDatabase(f.names.care, 0, null).use { removeHealthVisitFollowUpTestTables(it); it.version = 16 }
        assertEquals(before, f.snapshot()); f.start()
        context.openOrCreateDatabase(f.names.care, 0, null).use { assertEquals(17, it.version) }
    }
    @Test fun concurrentCheckinsNeverReturnMixedSnapshotRevisions(): Unit = fixture { f ->
        f.start()
        val writer = Executors.newSingleThreadExecutor()
        try {
            val writes = writer.submit { repeat(24) { f.record(note("Concurrent synthetic check-in $it")) } }
            var reads = 0
            repeat(60) {
                val result = runCatching { f.snapshot() }
                result.fold({ snapshot ->
                    reads++
                    assertEquals(snapshot.followUp!!.revision, snapshot.history.items.first().value.revision)
                    assertTrue(snapshot.followUp.revision <= snapshot.visit.issue.revision)
                    assertTrue(snapshot.history.items.all { it.value.revision <= snapshot.visit.issue.revision })
                }, { assertTrue("Unexpected read failure: ${it.javaClass.simpleName}", it is HealthCareConflict) })
            }
            writes.get(90, TimeUnit.SECONDS)
            assertTrue(reads > 0)
            assertEquals(25, f.snapshot().history.items.size)
        } finally { writer.shutdown(); assertTrue(writer.awaitTermination(90, TimeUnit.SECONDS)) }
    }
}

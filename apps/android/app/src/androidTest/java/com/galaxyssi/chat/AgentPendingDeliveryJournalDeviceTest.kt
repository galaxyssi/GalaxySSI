package com.galaxyssi.chat

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.os.SystemClock
import android.util.Log
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import org.junit.After
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AgentPendingDeliveryJournalDeviceTest {
    private val context = InstrumentationRegistry.getInstrumentation().targetContext
    private val token = UUID.randomUUID().toString()
    private val database = "pending-test-$token.db"
    private val preferences = "pending-test-$token"
    private var journal = AgentPendingDeliveryJournal(context, database, preferences)

    @After fun cleanup() {
        journal.close()
        context.deleteDatabase(database)
        context.deleteSharedPreferences(preferences)
        AgentEncryptedPreferenceCache.clearNamespace(preferences)
    }

    @Test fun directChatBodyAndTurnHeadSurviveReopen() {
        journal.put(value(1)); journal.put(value(2).copy(turnId = "turn-1"))
        reopen()
        assertEquals(value(1), journal.find(1))
        assertTrue(journal.isSuperseded(1, "conversation", "turn-1"))
        assertFalse(journal.isSuperseded(2, "conversation", "turn-1"))
    }

    @Test fun contactMismatchAndSourceTamperingAreRejected() {
        journal.put(value(1))
        assertNull(journal.find(1, "another-contact"))
        sql("UPDATE pending_deliveries SET source_id=9 WHERE source_id=1")
        assertNull(journal.find(9))
        val page = journal.page()
        assertEquals(1, page.unreadableCount)
        assertEquals(9L, page.nextBeforeSource)
    }

    @Test fun failedHeadWriteRollsBackBodyInSameTransaction() {
        journal.page()
        sql("CREATE TRIGGER fail_head BEFORE INSERT ON pending_turn_heads BEGIN SELECT RAISE(ABORT,'injected'); END")
        assertThrows(Exception::class.java) { journal.put(value(1)) }
        sql("DROP TRIGGER fail_head")
        reopen()
        assertNull(journal.find(1))
        assertTrue(journal.page().deliveries.isEmpty())
    }

    @Test fun failedCompletionRollsBackAllRetirements() {
        journal.put(value(1)); journal.put(value(2).copy(turnId = "turn-1"))
        journal.markRecoveryPredecessor(1, 2)
        val predecessor = journal.find(1)!!
        sql("CREATE TRIGGER fail_completion BEFORE INSERT ON pending_turn_heads WHEN NEW.encrypted_value IS NULL BEGIN SELECT RAISE(ABORT,'injected'); END")
        assertThrows(Exception::class.java) { journal.completeResponse(predecessor) }
        sql("DROP TRIGGER fail_completion")
        reopen()
        assertNotNull(journal.find(1)); assertNotNull(journal.find(2))
        assertFalse(journal.isSuperseded(1, "conversation", "turn-1"))
    }

    @Test fun linkedPredecessorCompletionRetiresOnlyItsOwnTurn() {
        journal.put(value(1)); journal.put(value(2).copy(turnId = "turn-1")); journal.put(value(3))
        val predecessor = journal.markRecoveryPredecessor(1, 2)!!
        assertFalse(journal.isSuperseded(1, "conversation", "turn-1"))
        journal.completeResponse(predecessor)
        reopen()
        assertNull(journal.find(1)); assertNull(journal.find(2)); assertEquals(value(3), journal.find(3))
    }

    @Test fun wrongConversationSuccessorCannotBeDeletedByCompletion() {
        journal.put(value(1)); journal.put(value(2).copy(conversationId = "other"))
        journal.completeResponse(value(1).copy(recoverySuccessorSourceMessageId = 2))
        assertNotNull(journal.find(2)); assertNull(journal.find(1))
    }

    @Test fun removePredecessorKeepsCurrentTurnHead() {
        journal.put(value(1)); journal.put(value(2).copy(turnId = "turn-1"))
        journal.remove(1)
        reopen()
        assertTrue(journal.isSuperseded(1, "conversation", "turn-1"))
        assertNotNull(journal.find(2))
    }

    @Test fun inlineLegacyLookupDoesNotTriggerFullMigration() {
        legacy(value(1))
        context.getSharedPreferences(preferences, Context.MODE_PRIVATE).edit().putInt("source:999", 12).commit()
        assertEquals(value(1), journal.find(1))
        journal.put(value(2))
        assertNotNull(journal.find(2))
        assertThrows(Exception::class.java) { journal.page() }
        assertTrue(context.getSharedPreferences(preferences, Context.MODE_PRIVATE).contains("source:999"))
    }

    @Test fun legacyCiphertextMigratesAndReopensWithSupersession() {
        legacy(value(1)); legacy(value(2).copy(turnId = "turn-1"))
        assertEquals(listOf(2L, 1L), journal.page().deliveries.map { it.sourceMessageId })
        assertTrue(context.getSharedPreferences(preferences, Context.MODE_PRIVATE).all.isEmpty())
        reopen()
        assertTrue(journal.isSuperseded(1, "conversation", "turn-1"))
        assertNotNull(journal.find(2))
    }

    @Test fun removalBeforeMigrationSurvivesStaleLegacyFileAndReopen() {
        legacy(value(1)); legacy(value(2))
        journal.remove(1)
        reopen()
        assertEquals(listOf(2L), journal.page().deliveries.map { it.sourceMessageId })
        // Simulate old preferences remaining after the database commit and process death.
        legacy(value(1))
        reopen()
        assertNull(journal.find(1))
        assertEquals(listOf(2L), journal.page().deliveries.map { it.sourceMessageId })
    }

    @Test fun newWriteWinsOverLegacySnapshotForSameSource() {
        legacy(value(1))
        journal.put(value(1).copy(contactId = "new-contact"))
        reopen()
        assertEquals("new-contact", journal.page().deliveries.single().contactId)
    }

    @Test fun completionBeforeMigrationCannotBeResurrected() {
        legacy(value(1)); legacy(value(2).copy(turnId = "turn-1"))
        journal.completeResponse(value(1))
        reopen()
        assertTrue(journal.page().deliveries.isEmpty())
        assertNull(journal.find(1)); assertNull(journal.find(2))
    }

    @Test fun partialMigrationAndMarkerFailureCanResumeWithoutResurrection() {
        legacy(value(1)); legacy(value(2))
        journal.find(1)
        sql("CREATE TRIGGER fail_marker BEFORE INSERT ON pending_metadata BEGIN SELECT RAISE(ABORT,'injected'); END")
        assertThrows(Exception::class.java) { journal.page() }
        journal.remove(1)
        sql("DROP TRIGGER fail_marker")
        reopen()
        assertEquals(listOf(2L), journal.page().deliveries.map { it.sourceMessageId })
    }

    @Test fun legacyDelimiterCollisionDoesNotBindAnotherConversation() {
        legacy(value(1).copy(conversationId = "a:b", turnId = "c"))
        legacy(value(2).copy(conversationId = "a", turnId = "b:c"))
        journal.page()
        journal.completeResponse(value(1).copy(conversationId = "a:b", turnId = "c"))
        assertNotNull(journal.find(2))
        assertFalse(journal.isSuperseded(2, "a", "b:c"))
    }

    @Test fun malformedEncryptedRecordIsRetainedAndDoesNotHideLaterRows() {
        legacy(value(1))
        context.getSharedPreferences(preferences, Context.MODE_PRIVATE).edit().putString("source:2", "enc:v1:invalid:invalid").commit()
        val page = journal.page(limit = 1)
        assertEquals(1, page.unreadableCount); assertEquals(2L, page.nextBeforeSource)
        assertEquals(value(1), journal.page(page.nextBeforeSource).deliveries.single())
        assertEquals(2L, scalar("SELECT count(*) FROM pending_deliveries WHERE encrypted_value IS NOT NULL"))
    }

    @Test fun keysetPagingHandlesDeletesAndConcurrentNewerInsertions() {
        for (id in 1L..83L) journal.put(value(id))
        val first = journal.page()
        assertEquals(32, first.deliveries.size)
        journal.remove(50); journal.put(value(90))
        val second = journal.page(first.nextBeforeSource)
        assertFalse(second.deliveries.any { it.sourceMessageId in listOf(50L, 90L) })
        assertEquals(90L, journal.page().deliveries.first().sourceMessageId)
        assertEquals(64, journal.page(limit = 10000).deliveries.size)
    }

    @Test fun concurrentWritersAndRetirementsKeepExactPendingSet() {
        val executor = Executors.newFixedThreadPool(4)
        try {
            val futures = (0..3).map { worker -> executor.submit {
                for (offset in 1L..25L) {
                    val id = worker * 100L + offset
                    journal.put(value(id))
                    if (offset % 2L == 0L) journal.remove(id)
                }
            } }
            futures.forEach { it.get(30, TimeUnit.SECONDS) }
            val records = all()
            assertEquals(52, records.size)
            assertEquals(52, records.map { it.sourceMessageId }.toSet().size)
        } finally { executor.shutdownNow() }
    }

    @Test fun tenThousandPendingRecordsUseIndexedBoundedPagesAndSurviveReopen() {
        val start = SystemClock.elapsedRealtime()
        for (id in 1L..10000L) journal.put(value(id))
        val writeMs = SystemClock.elapsedRealtime() - start
        reopen()
        val firstStart = SystemClock.elapsedRealtime()
        val first = journal.page()
        val firstMs = SystemClock.elapsedRealtime() - firstStart
        assertEquals(32, first.deliveries.size)
        val records = all()
        assertEquals((10000L downTo 1L).toList(), records.map { it.sourceMessageId })
        val samples = (1..30).map {
            val time = SystemClock.elapsedRealtimeNanos()
            assertEquals(32, journal.page().deliveries.size)
            (SystemClock.elapsedRealtimeNanos() - time) / 1_000_000.0
        }.sorted()
        val queryPlan = raw { db -> db.rawQuery("EXPLAIN QUERY PLAN SELECT source_id,encoding,encrypted_value FROM pending_deliveries WHERE encrypted_value IS NOT NULL AND source_id<5000 ORDER BY source_id DESC LIMIT 32", null)
            .use { cursor -> buildList { while (cursor.moveToNext()) add(cursor.getString(3)) }.joinToString(" ") } }
        assertTrue(queryPlan, queryPlan.contains("pending_active"))
        val cipher = raw { db -> db.rawQuery("SELECT encrypted_value FROM pending_deliveries LIMIT 1", null).use { it.moveToFirst(); it.getString(0) } }
        assertTrue(AgentStorageCipher.isEncrypted(cipher)); assertFalse(cipher.contains("conversation"))
        Log.i("GalaxySSIRecoveryTest", "pending_10000_write_ms=$writeMs first_page_ms=$firstMs warm_page_p50_ms=${samples[14]} p95_ms=${samples[28]} rows=${records.size} plan=$queryPlan")
    }

    private fun value(id: Long) = AgentPendingDelivery(id, "conversation", "turn-$id", "task-$id", "contact")
    private fun legacy(value: AgentPendingDelivery) {
        AgentEncryptedPreferences(context, preferences).apply {
            writeString("source:${value.sourceMessageId}", AgentPendingDeliveryCodec.encode(value))
            writeString(AgentPendingDeliveryCodec.legacyTurnKey(value.conversationId, value.turnId), value.sourceMessageId.toString())
        }
    }
    private fun reopen() { journal.close(); journal = AgentPendingDeliveryJournal(context, database, preferences) }
    private fun all(): List<AgentPendingDelivery> = buildList {
        var before: Long? = null
        while (true) { val page = journal.page(before); before = page.nextBeforeSource ?: break; addAll(page.deliveries) }
    }
    private fun sql(statement: String) = raw { it.execSQL(statement) }
    private fun scalar(query: String): Long = raw { db -> db.rawQuery(query, null).use { it.moveToFirst(); it.getLong(0) } }
    private fun <T> raw(block: (SQLiteDatabase) -> T): T =
        SQLiteDatabase.openDatabase(context.getDatabasePath(database).absolutePath, null, SQLiteDatabase.OPEN_READWRITE).use(block)
}

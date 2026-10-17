package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AgentResumeLedgerDeviceTest {
    private val context = InstrumentationRegistry.getInstrumentation().targetContext

    @Test fun ledgerReadersDoNotWaitForTheWriterMonitor() {
        val name = "resume-ledger-${UUID.randomUUID()}.db"
        val store = AgentRunEventStore(context, name)
        val pool = Executors.newFixedThreadPool(2)
        val held = CountDownLatch(1); val release = CountDownLatch(1)
        try {
            store.appendNext(event("fixture-run", 1))
            val ledger = store.javaClass.getDeclaredField("ledger").apply { isAccessible = true }.get(store)
            val lock = requireNotNull(ledger.javaClass.getDeclaredField("writeLock").apply { isAccessible = true }.get(ledger))
            val writer = pool.submit { synchronized(lock) { held.countDown(); release.await(10, TimeUnit.SECONDS) } }
            assertTrue(held.await(2, TimeUnit.SECONDS))
            val read = pool.submit<Boolean> {
                store.latestEvent("fixture-run")?.sequence == 1L &&
                    store.snapshot("fixture-run")?.lastSequence == 1L &&
                    store.eventsPage("fixture-run", limit = 1).size == 1 &&
                    store.containsLoopRevision("fixture-run", "turn", 1, 1)
            }
            assertTrue("Ledger readers waited for a long writer", read.get(2, TimeUnit.SECONDS))
            release.countDown(); writer.get(2, TimeUnit.SECONDS)
        } finally {
            release.countDown(); pool.shutdownNow(); pool.awaitTermination(5, TimeUnit.SECONDS)
            store.close(); context.deleteDatabase(name)
        }
    }

    @Test fun indexedDedupeSupportsOldIdsAndNewAtomicReplays() {
        val name = "resume-dedupe-${UUID.randomUUID()}.db"
        val store = AgentRunEventStore(context, name)
        try {
            store.appendNextAll((1..300).map { event("fixture-run", it.toLong()) })
            assertTrue(store.containsLoopRevision("fixture-run", "turn", 250, 250))
            assertFalse(store.containsLoopRevision("fixture-run", "other-turn", 250, 250))
            assertFalse(store.containsLoopRevision("other-run", "turn", 250, 250))
            val nextKey = AgentExecutionLoopTimelinePolicy.eventKey("fixture-run", "turn", 301)
            val next = event("fixture-run", 301).copy(eventId = nextKey, idempotencyKey = nextKey, actionId = nextKey)
            assertNotNull(store.appendNext(next))
            assertNull(store.appendNext(next))
            assertTrue(store.containsLoopRevision("fixture-run", "turn", 301, 301))
            val otherKey = AgentExecutionLoopTimelinePolicy.eventKey("other-run", "turn", 301)
            assertNotNull(store.appendNext(event("other-run", 301).copy(
                eventId = otherKey, idempotencyKey = otherKey, actionId = otherKey)))
            assertEquals(301L, store.latestEvent("fixture-run")!!.sequence)
            val reopened = AgentRunEventStore(context, name)
            try { assertTrue(reopened.containsLoopRevision("fixture-run", "turn", 301, 301)) }
            finally { reopened.close() }
            val db = android.database.sqlite.SQLiteDatabase.openDatabase(context.getDatabasePath(name).path, null,
                android.database.sqlite.SQLiteDatabase.OPEN_READONLY)
            db.use { database ->
                database.rawQuery("EXPLAIN QUERY PLAN SELECT sequence,encrypted_event FROM run_events WHERE run_key=? AND timestamp_millis=?",
                    arrayOf("test", "250")).use { cursor ->
                    assertTrue(cursor.moveToFirst())
                    assertTrue(cursor.getString(3).contains("run_events_run_time"))
                }
            }
        } finally { store.close(); context.deleteDatabase(name) }
    }

    @Test fun versionTwoMigrationKeepsEventsAndCreatesTheLookupIndex() {
        val name = "resume-migrate-${UUID.randomUUID()}.db"
        var store = AgentRunEventStore(context, name)
        try {
            store.appendNext(event("migration-run", 1))
            store.close()
            android.database.sqlite.SQLiteDatabase.openDatabase(context.getDatabasePath(name).path, null, 0).use {
                it.execSQL("DROP INDEX run_events_run_time")
                it.version = 2
            }
            store = AgentRunEventStore(context, name)
            assertTrue(store.containsLoopRevision("migration-run", "turn", 1, 1))
            assertEquals(1L, store.snapshot("migration-run")!!.lastSequence)
            android.database.sqlite.SQLiteDatabase.openDatabase(context.getDatabasePath(name).path, null,
                android.database.sqlite.SQLiteDatabase.OPEN_READONLY).use {
                assertEquals(3, it.version)
                it.rawQuery("SELECT name FROM sqlite_master WHERE type='index' AND name='run_events_run_time'", null).use { cursor ->
                    assertTrue(cursor.moveToFirst())
                }
            }
        } finally { store.close(); context.deleteDatabase(name) }
    }

    private fun event(run: String, revision: Long) = AgentRunControlEvent(
        runId = run, taskId = "task", conversationId = "conversation", messageId = "turn", turnId = "turn",
        agentId = "fixture", deviceId = "fixture", type = AgentRunControlEventType.TOOL_PROGRESS,
        sequence = 0, timestampMillis = revision, payload = mapOf("loop_revision" to revision))
}

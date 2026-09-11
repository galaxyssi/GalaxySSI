package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import java.util.concurrent.Callable
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class KnowledgeVectorEnrollmentDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val spec = KnowledgeVectorSpec("a".repeat(64), 4, 32)
    private val encoder get() = object : KnowledgeVectorEncoder {
        override val spec = this@KnowledgeVectorEnrollmentDeviceTest.spec
        override fun tokenCount(text: String) = text.length + 2
        override fun embed(text: String) = floatArrayOf(1f, 0f, 0f, 0f)
        override fun close() = Unit
    }
    private fun item(id: String, body: String = "\u5206\u9875\u767b\u8bb0\u6d4b\u8bd5") =
        AgentKnowledgeItem(id, AgentKnowledgeKind.NOTE, id, body, source = "enrollment")
    private inner class Fixture {
        val name = "test-enrollment-${UUID.randomUUID()}.db"
        val legacy = "legacy-$name"
        var db = AgentKnowledgeDatabase.shared(context, name, legacy)
        var store = SQLiteAgentKnowledgeStore(context, name, legacy) { _, _ -> }
        val ledger get() = db.vectors(spec)
        fun seed(count: Int) = store.replaceSource("enrollment", (1..count).map { item("entry-$it") })
        fun queued() = db.access { sql -> sql.rawQuery("SELECT count(*) FROM knowledge_vector_queue WHERE model_key=?",
            arrayOf(ledger.modelKey)).use { check(it.moveToFirst()); it.getLong(0) } }
        fun state() = db.access { KnowledgeVectorEnrollment.state(it, ledger.modelKey) }
        fun page(limit: Int = 64) = db.transaction { KnowledgeVectorEnrollment.refill(it, ledger.modelKey, limit) }
        fun complete() {
            val indexer = KnowledgeVectorIndexer(ledger, encoder)
            repeat(1000) { if (!indexer.runBatch(16).pending) return }
            fail("Isolated vector enrollment did not settle")
        }
        fun reopen() {
            store.close()
            db = AgentKnowledgeDatabase.shared(context, name, legacy)
            store = SQLiteAgentKnowledgeStore(context, name, legacy) { _, _ -> }
        }
        fun cleanup() {
            store.close(); AgentKnowledgeDatabase.release(context, name)
            context.deleteDatabase(name); AgentEncryptedPreferences(context, legacy).clear()
        }
    }
    private fun isolated(block: (Fixture) -> Unit) {
        val fixture = Fixture()
        try { block(fixture) } finally { fixture.cleanup() }
    }

    @Test fun registrationIsConstantWorkAndDiscoveryUsesOneBoundedIndexedPage() = isolated { f ->
        f.seed(131)
        val reads = f.db.decryptedItemReads
        f.ledger.ensureRegistered()
        assertEquals(0L, f.queued())
        assertEquals(KnowledgeVectorEnrollment.State("", false), f.state())
        f.page()
        assertEquals(64L, f.queued())
        assertFalse(f.state().complete)
        assertEquals(reads, f.db.decryptedItemReads)
        f.db.access { sql -> sql.rawQuery("EXPLAIN QUERY PLAN " + KnowledgeVectorEnrollment.KEY_PAGE_SQL,
            arrayOf(f.state().after, "65")).use {
            assertTrue(it.moveToFirst()); assertTrue(it.getString(3).contains("SEARCH knowledge_items"))
        } }
        f.complete()
        assertEquals(0L, f.queued()); assertTrue(f.state().complete)
        (1..131).forEach { requireNotNull(f.ledger.page("entry-$it")).use { page -> assertEquals(1, page.total) } }
    }

    @Test fun emptySourcesCompleteWithoutOpeningAnEncoderAndFutureInsertsStillQueue() = isolated { f ->
        f.ledger.ensureRegistered()
        assertNull(f.ledger.nextJob()); assertFalse(f.ledger.enrollmentPending())
        f.store.upsert(item("later"))
        assertEquals(1L, f.queued())
        assertEquals("later", requireNotNull(f.ledger.nextJob()).item.id)
        f.complete(); requireNotNull(f.ledger.page("later")).close()
    }

    @Test fun editsAndDeletesOnBothSidesOfTheCursorDoNotLoseOrDuplicateWork() = isolated { f ->
        f.seed(131); f.ledger.ensureRegistered(); f.page(8)
        val ordered = (1..131).map { "entry-$it" }.sortedBy { f.db.key("id", it) }
        val first = ordered.first(); val last = ordered.last(); val deleted = ordered[100]
        f.store.upsert(item(first, "\u5df2\u66f4\u65b0\u524d\u534a\u9875"))
        f.store.upsert(item(last, "\u5df2\u66f4\u65b0\u540e\u534a\u9875"))
        f.db.transaction { it.delete("knowledge_items", "item_key=?", arrayOf(f.db.key("id", deleted))) }
        f.store.upsert(item("new-during-enrollment"))
        f.complete()
        assertNull(f.ledger.page(deleted))
        for (id in (ordered - deleted) + "new-during-enrollment") requireNotNull(f.ledger.page(id)).use {
            assertEquals(1, it.total)
        }
        assertEquals(131, f.store.stats().itemCount); assertEquals(0L, f.queued())
    }

    @Test fun completedLiveSourcesAheadOfDiscoveryAreNotReencoded() = isolated { f ->
        f.seed(131); f.ledger.ensureRegistered()
        val last = (1..131).map { "entry-$it" }.maxBy { f.db.key("id", it) }
        f.store.upsert(item(last))
        assertEquals(1, KnowledgeVectorIndexer(f.ledger, encoder).runBatch(1).committedChunks)
        val checkpoint = requireNotNull(f.ledger.changes().state()).head
        f.complete()
        val final = requireNotNull(f.ledger.changes().state())
        assertEquals(checkpoint + 130, final.head)
        assertEquals(131L, final.completedChunks)
        requireNotNull(f.ledger.page(last)).use { assertEquals(1, it.total) }
    }

    @Test fun cursorFailureRollsBackAllQueueRowsAndCanBeRetried() = isolated { f ->
        f.seed(131); f.ledger.ensureRegistered()
        f.db.access { it.execSQL("CREATE TRIGGER reject_enrollment BEFORE UPDATE ON knowledge_vector_enrollment " +
            "BEGIN SELECT RAISE(ABORT,'fixture checkpoint failure'); END") }
        assertThrows(Exception::class.java) { f.page() }
        assertEquals(0L, f.queued()); assertEquals("", f.state().after)
        f.db.access { it.execSQL("DROP TRIGGER reject_enrollment") }
        f.page(); assertEquals(64L, f.queued())
    }

    @Test fun silentlyIgnoredCheckpointAlsoRollsBackTheQueue() = isolated { f ->
        f.seed(65); f.ledger.ensureRegistered()
        f.db.access { it.execSQL("CREATE TRIGGER ignore_enrollment BEFORE UPDATE ON knowledge_vector_enrollment " +
            "BEGIN SELECT RAISE(IGNORE); END") }
        assertThrows(IllegalStateException::class.java) { f.page() }
        assertEquals(0L, f.queued()); assertEquals("", f.state().after)
    }

    @Test fun reopenContinuesTheSameCursorAndConcurrentRefillsNeverOverlap() = isolated { f ->
        f.seed(131); f.ledger.ensureRegistered(); f.page()
        val checkpoint = f.state()
        f.reopen(); assertEquals(checkpoint, f.state()); assertEquals(64L, f.queued())
        val threads = Executors.newFixedThreadPool(2)
        try {
            val jobs = (1..2).map { threads.submit(Callable { f.page() }) }
            jobs.forEach { it.get(30, TimeUnit.SECONDS) }
        } finally { threads.shutdownNow() }
        assertEquals(131L, f.queued()); assertTrue(f.state().complete)
        f.complete(); assertEquals(0L, f.queued())
    }

    @Test fun fullyCompletedPagesYieldPendingUntilDiscoveryActuallyFinishes() = isolated { f ->
        f.seed(131); f.complete()
        // Revisit a completed prefix to reproduce sources indexed by live writes before discovery.
        f.db.access { it.execSQL("UPDATE knowledge_vector_enrollment SET after_key='',complete=0") }
        val indexer = KnowledgeVectorIndexer(f.ledger, encoder)
        val first = indexer.runBatch(8)
        assertTrue(first.pending); assertEquals(0, first.committedChunks)
        assertTrue(indexer.runBatch(8).pending)
        assertFalse(indexer.runBatch(8).pending)
        assertEquals(0L, f.queued())
    }

    @Test fun versionFiveUpgradePreservesExistingQueueAndCompletedVectors() = isolated { f ->
        f.seed(2); f.complete(); f.store.upsert(item("pending"))
        f.db.access {
            it.execSQL("DROP TRIGGER knowledge_vector_enrollment_model")
            it.execSQL("DROP TABLE knowledge_vector_enrollment")
            it.execSQL("PRAGMA user_version=5")
        }
        f.reopen()
        assertTrue(f.state().complete); assertEquals(1L, f.queued())
        requireNotNull(f.ledger.page("entry-1")).close()
        f.complete(); requireNotNull(f.ledger.page("pending")).close()
        val other = f.db.vectors(spec.copy(modelSha256 = "b".repeat(64)))
        other.ensureRegistered(); assertTrue(other.enrollmentPending())
        f.ledger.unregister()
        assertTrue(other.enrollmentPending())
        f.db.access { sql -> sql.rawQuery("SELECT count(*) FROM knowledge_vector_enrollment", null).use {
            assertTrue(it.moveToFirst()); assertEquals(1L, it.getLong(0))
        } }
    }

    @Test fun invalidOrMissingCursorFailsExplicitlyWithoutResettingSources() = isolated { f ->
        f.seed(65); f.ledger.ensureRegistered()
        for (value in listOf("invalid", "a".repeat(65))) {
            f.db.access { sql -> sql.rawQuery("UPDATE knowledge_vector_enrollment SET after_key=?", arrayOf(value)).use { it.moveToNext() } }
            assertThrows(IllegalStateException::class.java) { f.page() }
            assertEquals(0L, f.queued())
        }
        f.db.access { it.execSQL("DELETE FROM knowledge_vector_enrollment") }
        assertThrows(IllegalStateException::class.java) { f.ledger.nextJob() }
        assertEquals(65, f.store.stats().itemCount)
    }
}

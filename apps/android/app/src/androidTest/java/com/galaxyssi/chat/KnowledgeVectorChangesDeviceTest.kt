package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class KnowledgeVectorChangesDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val spec = KnowledgeVectorSpec("a".repeat(64), 4, 32)
    private class Encoder(override val spec: KnowledgeVectorSpec) : KnowledgeVectorEncoder {
        override fun tokenCount(text: String) = text.length + 2
        override fun embed(text: String) = FloatArray(spec.dimensions) { if (it == 0) 1f else 0f }
        override fun close() = Unit
    }
    private inner class Fixture {
        val name = "test-vector-feed-${UUID.randomUUID()}.db"
        val legacy = "legacy-$name"
        var db = AgentKnowledgeDatabase.shared(context, name, legacy)
        var store = SQLiteAgentKnowledgeStore(context, name, legacy) { _, _ -> }
        fun ledger(model: KnowledgeVectorSpec = spec) = db.vectors(model)
        fun reopen() {
            AgentKnowledgeDatabase.release(context, name)
            db = AgentKnowledgeDatabase.shared(context, name, legacy)
            store = SQLiteAgentKnowledgeStore(context, name, legacy) { _, _ -> }
        }
        fun put(id: String, text: String = "\u8bb0\u5fc6-$id") = store.upsert(
            AgentKnowledgeItem(id, AgentKnowledgeKind.NOTE, id, text))
        fun finish(model: KnowledgeVectorSpec = spec) {
            val indexer = KnowledgeVectorIndexer(ledger(model), Encoder(model))
            repeat(2000) { if (!indexer.runBatch(64).pending) return }
            fail("Synthetic vector fixture did not finish")
        }
        fun close() {
            AgentKnowledgeDatabase.release(context, name)
            check(name.startsWith("test-vector-feed-"))
            context.deleteDatabase(name)
            AgentEncryptedPreferences(context, legacy).clear()
        }
        fun asVersionFour() {
            AgentKnowledgeDatabase.release(context, name)
            KnowledgeSqlite(context.getDatabasePath(name).absolutePath).use { sql ->
                sql.beginTransaction()
                try {
                    KnowledgeVectorChangeFixtureSchema.remove(sql)
                    sql.execSQL("PRAGMA user_version=4")
                    sql.setTransactionSuccessful()
                } finally { sql.endTransaction() }
            }
            reopen()
        }
    }
    private fun isolated(block: (Fixture) -> Unit) {
        val fixture = Fixture()
        try { block(fixture) } finally { fixture.close() }
    }
    private fun state(ledger: KnowledgeVectorLedger) = requireNotNull(ledger.changes().state())
    private fun rows(ledger: KnowledgeVectorLedger, limit: Int = 17): List<KnowledgeVectorChange> {
        val epoch = state(ledger).epoch
        val result = mutableListOf<KnowledgeVectorChange>()
        var after = 0L
        do {
            val page = ledger.changes().page(epoch, after, limit)
            assertTrue(page.rows.size <= limit)
            result.addAll(page.rows)
            after = page.nextSequence
        } while (page.hasMore)
        return result
    }
    @Test fun registrationHasStableEpochAndNoCompletedEventForPartialVectors() = isolated { f ->
        f.put("one", "\u6d4b\u8bd5\u8bb0\u5fc6".repeat(40))
        val ledger = f.ledger()
        assertNull(ledger.changes().state())
        val first = KnowledgeVectorIndexer(ledger, Encoder(spec)).runBatch(1)
        assertEquals(1, first.committedChunks)
        val before = state(ledger)
        assertEquals(0L, before.head); assertEquals(0L, before.completedChunks)
        assertTrue(before.bootstrapComplete); assertTrue(rows(ledger).isEmpty())
        f.reopen()
        assertEquals(before, state(f.ledger()))
        f.finish()
        val event = rows(f.ledger()).single()
        assertFalse(event.removed)
        requireNotNull(f.ledger().page("one")).use {
            assertEquals(it.total, event.chunkCount)
            assertEquals(it.total.toLong(), state(f.ledger()).completedChunks)
            assertEquals(it.revision, event.revision)
        }
    }
    @Test fun sourceReplacementAndDeletionAreInTheSameDurableChangeHistory() = isolated { f ->
        f.put("one"); f.finish()
        val before = rows(f.ledger()).single()
        f.put("one", "\u65b0\u7684\u5185\u5bb9")
        val removed = rows(f.ledger()).last()
        assertTrue(removed.removed); assertEquals(before.revision, removed.revision)
        assertEquals(0L, state(f.ledger()).completedChunks)
        f.finish()
        val replacement = rows(f.ledger()).last()
        assertFalse(replacement.removed); assertNotEquals(before.revision, replacement.revision)
        assertEquals(before.key, replacement.key)
        f.db.transaction { it.delete("knowledge_items", "item_key=?", arrayOf(replacement.key)) }
        assertTrue(rows(f.ledger()).last().removed)
        assertEquals(0L, state(f.ledger()).completedChunks)
        assertNull(f.ledger().page("one"))
        f.reopen()
        assertEquals(listOf(false, true, false, true), rows(f.ledger()).map { it.removed })
    }
    @Test fun outerTransactionRollbackRestoresSourceCounterAndChangeCursor() = isolated { f ->
        f.put("one"); f.finish()
        val before = state(f.ledger())
        val events = rows(f.ledger())
        assertThrows(IllegalStateException::class.java) {
            f.db.transaction {
                f.put("one", "uncommitted source")
                assertTrue(state(f.ledger()).head > before.head)
                error("Synthetic rollback after the deletion event")
            }
        }
        assertEquals(before, state(f.ledger()))
        assertEquals(events, rows(f.ledger()))
        assertNotNull(f.ledger().page("one")?.also { it.close() })
    }
    @Test fun rejectedPublicationRollsBackVectorDocumentAndFeedTogether() = isolated { f ->
        f.put("one")
        val ledger = f.ledger()
        val job = requireNotNull(ledger.nextJob())
        val chunk = requireNotNull(KnowledgeEmbeddingChunks.next(job.item.content, 0, 32, Encoder(spec)::tokenCount))
        f.db.access { it.execSQL("CREATE TRIGGER reject_feed BEFORE INSERT ON knowledge_vector_changes " +
            "BEGIN SELECT RAISE(ABORT,'synthetic feed failure'); END") }
        assertThrows(Exception::class.java) { ledger.append(job, chunk, floatArrayOf(1f, 0f, 0f, 0f)) }
        assertEquals(0, requireNotNull(ledger.nextJob()).count)
        assertEquals(0L, state(ledger).head)
        assertEquals(0L, state(ledger).completedChunks)
        assertNull(ledger.page("one"))
        f.db.access { it.execSQL("DROP TRIGGER reject_feed") }
        f.finish(); assertEquals(1, rows(ledger).size)
    }
    @Test fun modelRemovalAndReregistrationRejectAnOlderConsumerEpoch() = isolated { f ->
        f.put("one"); f.finish()
        val before = state(f.ledger())
        f.ledger().unregister()
        assertNull(f.ledger().changes().state())
        f.finish()
        val after = state(f.ledger())
        assertNotEquals(before.epoch, after.epoch)
        assertEquals(1, rows(f.ledger()).size)
        assertThrows(IllegalStateException::class.java) { f.ledger().changes().page(before.epoch, before.head) }
        assertEquals(1L, f.store.stats().itemCount)
    }
    @Test fun interleavedModelsAndSmallKeysetPagesHaveNoDuplicatesOrMissingEvents() = isolated { f ->
        for (id in 1..137) f.put("item-$id")
        val other = spec.copy(modelSha256 = "b".repeat(64))
        val firstIndexer = KnowledgeVectorIndexer(f.ledger(), Encoder(spec))
        val secondIndexer = KnowledgeVectorIndexer(f.ledger(other), Encoder(other))
        repeat(137) { firstIndexer.runBatch(1); secondIndexer.runBatch(1) }
        f.finish(); f.finish(other)
        for (ledger in listOf(f.ledger(), f.ledger(other))) {
            val events = rows(ledger, 7)
            assertEquals(137, events.size)
            assertEquals(137, events.map { it.key }.distinct().size)
            assertEquals(events.sortedBy { it.sequence }, events)
            assertTrue(events.all { !it.removed && it.key.length == 64 && it.revision.length == 64 })
            assertEquals(137L, state(ledger).completedChunks)
            val repeated = ledger.changes().page(state(ledger).epoch, limit = 7)
            assertEquals(events.take(7), repeated.rows)
        }
    }
    @Test fun missingMiddleEventCannotBeAcknowledgedAsACompletePage() = isolated { f ->
        repeat(3) { f.put("item-$it") }; f.finish()
        val events = rows(f.ledger())
        f.db.transaction { it.delete("knowledge_vector_changes", "sequence=?", arrayOf(events[1].sequence.toString())) }
        assertThrows(IllegalStateException::class.java) { rows(f.ledger()) }
    }
    @Test fun invalidPageArgumentsAndFutureCheckpointsAreRejected() = isolated { f ->
        f.put("one"); f.finish()
        val feed = f.ledger().changes(); val current = state(f.ledger())
        for (limit in listOf(0, 513)) assertThrows(IllegalArgumentException::class.java) { feed.page(current.epoch, limit = limit) }
        assertThrows(IllegalArgumentException::class.java) { feed.page(current.epoch, -1) }
        assertThrows(IllegalArgumentException::class.java) { feed.page(current.epoch, current.head + 1) }
        assertFalse(feed.page(current.epoch, current.head).hasMore)
    }
    @Test fun trackingValidationDoesNotNeedATableWideAddColumnConstraint() = isolated { f ->
        f.put("one"); f.finish()
        val before = state(f.ledger())
        assertThrows(Exception::class.java) { f.db.transaction { it.execSQL("UPDATE knowledge_vector_docs SET feed_tracked=2") } }
        assertEquals(before, state(f.ledger()))
        f.db.access { sql -> sql.rawQuery("SELECT sql FROM sqlite_schema WHERE name='knowledge_vector_docs'", null).use {
            assertTrue(it.moveToFirst())
            assertFalse(it.getString(0).contains("CHECK(feed_tracked"))
        } }
    }
    @Test fun versionFourMigrationIsLazyAndBackfillResumesAfterReopen() = isolated { f ->
        repeat(11) { f.put("item-$it") }; f.finish()
        f.asVersionFour()
        val catalog = KnowledgeVectorCatalog(f.db, f.ledger())
        val before = state(f.ledger())
        assertFalse(before.bootstrapComplete); assertEquals(0L, before.head)
        assertEquals(0L, before.completedChunks); assertEquals(11, catalog.count())
        assertFalse(f.ledger().changes().bootstrap(3))
        val checkpoint = state(f.ledger())
        assertEquals(3L, checkpoint.completedChunks)
        assertEquals(3, rows(f.ledger()).size)
        f.reopen(); assertEquals(checkpoint, state(f.ledger()))
        while (!f.ledger().changes().bootstrap(3)) Unit
        assertEquals(11L, state(f.ledger()).completedChunks)
        assertEquals(11, rows(f.ledger()).size)
        val stable = state(f.ledger()); assertTrue(f.ledger().changes().bootstrap(3))
        assertEquals(stable, state(f.ledger()))
        repeat(11) { assertNotNull(f.ledger().page("item-$it")?.also { it.close() }) }
    }
    @Test fun replacementAndDeletionDuringLegacyBackfillDoNotDoubleCount() = isolated { f ->
        val ids = (1..12).map { "item-$it" }
        ids.forEach { f.put(it) }; f.finish()
        f.asVersionFour()
        assertFalse(f.ledger().changes().bootstrap(3))
        val ordered = ids.sortedBy { f.db.key("id", it) }
        f.put(ordered.first(), "replacement during backfill")
        f.db.transaction { it.delete("knowledge_items", "item_key=?", arrayOf(f.db.key("id", ordered.last()))) }
        f.finish()
        assertTrue(state(f.ledger()).bootstrapComplete)
        assertEquals(11L, state(f.ledger()).completedChunks)
        assertEquals(11L, f.store.stats().itemCount)
        assertNull(f.ledger().page(ordered.last()))
        assertNotNull(f.ledger().page(ordered.first())?.also { it.close() })
    }
    @Test fun unrelatedDatabaseWritesDoNotInvalidateTheVectorCorpusStamp() = isolated { f ->
        f.put("one"); f.finish()
        val catalog = KnowledgeVectorCatalog(f.db, f.ledger())
        val before = catalog.stamp()
        f.db.transaction { it.execSQL("CREATE TABLE isolated_fixture(value INTEGER)"); it.execSQL("INSERT INTO isolated_fixture VALUES(1)") }
        assertEquals(before, catalog.stamp())
        assertEquals(1, catalog.count())
        f.reopen()
        assertEquals(before, KnowledgeVectorCatalog(f.db, f.ledger()).stamp())
        f.put("one", "changed source")
        assertNotEquals(before, KnowledgeVectorCatalog(f.db, f.ledger()).stamp())
    }
    @Test fun backfillRefusesTheUiThreadBeforeOpeningTheDatabase() = isolated { f ->
        f.ledger().ensureRegistered()
        InstrumentationRegistry.getInstrumentation().runOnMainSync {
            assertThrows(IllegalStateException::class.java) { f.ledger().changes().bootstrap() }
        }
    }
}

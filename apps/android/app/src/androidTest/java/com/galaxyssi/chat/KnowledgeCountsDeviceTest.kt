package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import java.util.concurrent.Callable
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class KnowledgeCountsDeviceTest {
    private val vectors = KnowledgeCountSchema.Kind.VECTOR
    private val queue = KnowledgeCountSchema.Kind.QUEUE

    @Test fun emptyAndUnregisteredModelsNeedOnlyPointReads() = KnowledgeCountTestFixture().use { f ->
        assertEquals(KnowledgeCountSnapshot(0, 0, true), f.counts())
        f.ledger.ensureRegistered(); f.verify()
        for (kind in KnowledgeCountSchema.Kind.entries) f.db.access { sql ->
            val args = if (kind == vectors) arrayOf("", "", "-1", "65") else arrayOf("", "", "65")
            sql.rawQuery("EXPLAIN QUERY PLAN " + KnowledgeCounts.pageSql(kind), args).use {
                assertTrue(it.moveToFirst())
                val plan = it.getString(3)
                assertTrue(plan, plan.contains("SEARCH ${kind.table}"))
                val seek = "(${kind.keys.joinToString(",")})>(${kind.keys.joinToString(",") { "?" }})"
                assertTrue("Every cursor key must participate in the seek: $plan", plan.contains(seek))
            }
        }
    }

    @Test fun manyChunksInOneDocumentSeekByNumericOrdinalAcrossRestart() = KnowledgeCountTestFixture().use { f ->
        f.store.upsert(f.item("many-chunks", "\u7edf\u8ba1\u5206\u7247\u6062\u590d".repeat(600)))
        f.indexLegacy()
        val count = f.counts().chunks
        assertTrue(count > 130)
        f.downgrade()
        assertFalse(f.page(vectors))
        assertEquals(63L, f.db.access { KnowledgeCounts.position(it, vectors).ordinal })
        assertFalse(f.page(vectors))
        assertEquals(127L, f.db.access { KnowledgeCounts.position(it, vectors).ordinal })
        f.reopen(); f.finishCounts(); f.verify()
        assertEquals(count, f.counts().chunks)
        requireNotNull(f.ledger.page("many-chunks", fromOrdinal = 100, limit = 20)).close()
    }

    @Test fun partiallyEncodedDocumentsCountCommittedVectorsBeforeDocumentCompletion() = KnowledgeCountTestFixture().use { f ->
        f.store.upsert(f.item("partial", "\u672a\u5b8c\u6210\u7684\u6587\u6863".repeat(40)))
        assertEquals(1, KnowledgeVectorIndexer(f.ledger, f.encoder).runBatch(1).committedChunks)
        assertEquals(KnowledgeCountSnapshot(1, 1, true), f.counts())
        assertEquals(0L, requireNotNull(f.ledger.changes().state()).completedChunks)
        f.index(); f.verify(); assertTrue(f.counts().chunks > 1)
        assertEquals(0L, f.counts().pending)
    }

    @Test fun sourceReplacementDeletionAndUnregisterMaintainBothCounters() = KnowledgeCountTestFixture().use { f ->
        f.seed(4); f.index(); f.verify()
        f.store.upsert(f.item("source-1", "\u66f4\u65b0"))
        assertEquals(KnowledgeCountSnapshot(3, 1, true), f.counts())
        f.db.transaction { it.delete("knowledge_items", "item_key=?", arrayOf(f.db.key("id", "source-2"))) }
        assertEquals(KnowledgeCountSnapshot(2, 1, true), f.counts())
        f.index(); f.verify()
        val other = f.db.vectors(f.spec.copy(modelSha256 = "b".repeat(64)))
        other.ensureRegistered(); other.nextJob()
        val before = f.db.access { KnowledgeCounts.snapshot(it, other.modelKey) }
        f.ledger.unregister()
        assertEquals(KnowledgeCountSnapshot(0, 0, true), f.counts())
        assertEquals(before, f.db.access { KnowledgeCounts.snapshot(it, other.modelKey) })
        assertEquals(3L, f.store.stats().itemCount)
    }

    @Test fun queueConflictAndVectorReplaceDoNotDoubleCount() = KnowledgeCountTestFixture().use { f ->
        f.seed(1); f.ledger.nextJob(); f.verify()
        repeat(3) { f.db.transaction { it.execSQL("INSERT INTO knowledge_vector_queue(model_key,item_key) " +
            "SELECT model_key,item_key FROM knowledge_vector_queue WHERE 1 ON CONFLICT(model_key,item_key) DO NOTHING") } }
        assertEquals(1L, f.counts().pending)
        f.index()
        repeat(3) { f.db.transaction { it.execSQL("INSERT OR REPLACE INTO knowledge_vectors(item_key,model_key,ordinal,ciphertext) " +
            "SELECT item_key,model_key,ordinal,ciphertext FROM knowledge_vectors") } }
        assertEquals(1L, f.counts().chunks); f.verify()
        requireNotNull(f.ledger.page("source-1")).close()
    }

    @Test fun legacyUpgradeIsBoundedAndDoesNotDecryptSourcesOrVectors() = KnowledgeCountTestFixture().use { f ->
        f.seed(131); f.indexLegacy(); f.store.upsert(f.item("pending")); f.downgrade()
        val reads = f.db.decryptedItemReads
        assertEquals(KnowledgeCountSnapshot(0, 0, false), f.counts())
        assertFalse(f.page(vectors)); assertEquals(64L, f.counts().chunks)
        assertTrue(f.page(queue)); assertEquals(1L, f.counts().pending)
        val cursor = f.db.access { KnowledgeCounts.position(it, vectors) }
        f.reopen(); assertEquals(cursor, f.db.access { KnowledgeCounts.position(it, vectors) })
        f.finishCounts(); f.verify()
        assertEquals(131L, f.counts().chunks)
        assertEquals(reads, f.db.decryptedItemReads)
        requireNotNull(f.ledger.page("source-100")).close()
    }

    @Test fun liveMutationsOnBothSidesOfLegacyCursorAreCountedExactlyOnce() = KnowledgeCountTestFixture().use { f ->
        f.seed(131); f.indexLegacy(); f.downgrade(); f.page(vectors, 8)
        val ordered = (1..131).map { "source-$it" }.sortedBy { f.db.key("id", it) }
        for (id in listOf(ordered.first(), ordered.last())) f.store.upsert(f.item(id, "\u4fee\u6539\u540e"))
        for (id in listOf(ordered[1], ordered[120])) f.db.transaction {
            it.delete("knowledge_items", "item_key=?", arrayOf(f.db.key("id", id)))
        }
        f.store.upsert(f.item("new-behind-or-ahead"))
        f.index(); f.finishCounts(); f.verify()
        assertEquals(130L, f.counts().chunks)
    }

    @Test fun alreadyTrackedPrefixConsumesBoundedPagesWithoutDuplicateCounts() = KnowledgeCountTestFixture().use { f ->
        f.seed(131); f.index()
        f.db.transaction { it.execSQL("UPDATE knowledge_count_scan SET complete=0 WHERE kind='VECTOR'") }
        val before = f.counts()
        assertFalse(f.page(vectors)); assertEquals(before, f.counts())
        assertFalse(f.page(vectors)); assertTrue(f.page(vectors)); f.verify()
    }

    @Test fun failedOrIgnoredCheckpointRollsBackAllTrackedRows() = KnowledgeCountTestFixture().use { f ->
        f.seed(65); f.indexLegacy(); f.downgrade()
        for (operation in listOf("ABORT,'fixture checkpoint'", "IGNORE")) {
            f.db.access { it.execSQL("CREATE TRIGGER reject_count_cursor BEFORE UPDATE ON knowledge_count_scan " +
                "BEGIN SELECT RAISE($operation); END") }
            assertThrows(Exception::class.java) { f.page(vectors) }
            assertEquals(0L, f.counts().chunks)
            assertEquals("", f.db.access { KnowledgeCounts.position(it, vectors).item })
            f.db.access { it.execSQL("DROP TRIGGER reject_count_cursor") }
        }
        f.finishCounts(); f.verify()
    }

    @Test fun ignoredTrackingOrCounterUpdatesCannotAdvanceTheCursor() = KnowledgeCountTestFixture().use { f ->
        f.seed(65); f.indexLegacy(); f.downgrade()
        for (table in listOf("knowledge_vectors", "knowledge_vector_counts")) {
            f.db.access { it.execSQL("CREATE TRIGGER ignore_count_write BEFORE UPDATE ON $table BEGIN SELECT RAISE(IGNORE); END") }
            assertThrows(Exception::class.java) { f.page(vectors) }
            assertEquals(0L, f.counts().chunks)
            assertEquals("", f.db.access { KnowledgeCounts.position(it, vectors).item })
            f.db.access { it.execSQL("DROP TRIGGER ignore_count_write") }
        }
        f.finishCounts(); f.verify()
    }

    @Test fun missingCountsFailWithoutSilentlyResettingOrAcceptingSourceWrites() = KnowledgeCountTestFixture().use { f ->
        f.seed(1); f.ledger.ensureRegistered()
        f.db.access { it.delete("knowledge_vector_counts", "model_key=?", arrayOf(f.ledger.modelKey)) }
        assertThrows(IllegalStateException::class.java) { f.counts() }
        assertThrows(Exception::class.java) { f.store.upsert(f.item("rejected")) }
        assertEquals(1L, f.store.stats().itemCount)
    }

    @Test fun signed64BitOverflowAbortsWithoutCommittingTheNewVector() = KnowledgeCountTestFixture().use { f ->
        f.seed(1); f.ledger.nextJob()
        f.db.access { it.execSQL("UPDATE knowledge_vector_counts SET chunks=9223372036854775807") }
        assertThrows(Exception::class.java) { KnowledgeVectorIndexer(f.ledger, f.encoder).runBatch(1) }
        assertEquals(0L, f.actual("knowledge_vectors"))
        assertEquals(0, requireNotNull(f.ledger.nextJob()).count)
        assertEquals(Long.MAX_VALUE, f.counts().chunks)
        f.db.access { it.execSQL("UPDATE knowledge_vector_counts SET chunks=0") }
        f.index(); f.verify()
    }

    @Test fun malformedAndMissingCursorFailWithoutRestartingOrDiscardingCounts() = KnowledgeCountTestFixture().use { f ->
        f.seed(2); f.indexLegacy(); f.downgrade()
        f.db.access { it.execSQL("UPDATE knowledge_count_scan SET after_item='bad' WHERE kind='VECTOR'") }
        assertThrows(IllegalStateException::class.java) { f.page(vectors) }
        f.db.access { it.execSQL("DELETE FROM knowledge_count_scan WHERE kind='VECTOR'") }
        assertThrows(IllegalStateException::class.java) { f.page(vectors) }
        assertEquals(2L, f.actual("knowledge_vectors"))
    }

    @Test fun underflowCannotDeleteAnAcknowledgedSourceAndTrackingCannotBeReset() = KnowledgeCountTestFixture().use { f ->
        f.seed(1); f.ledger.nextJob()
        assertThrows(Exception::class.java) { f.db.transaction { it.execSQL("UPDATE knowledge_vector_queue SET count_tracked=0") } }
        assertThrows(Exception::class.java) { f.db.transaction { it.execSQL("UPDATE knowledge_vector_queue SET item_key='changed'") } }
        f.db.access { it.execSQL("UPDATE knowledge_vector_counts SET pending=0") }
        assertThrows(Exception::class.java) { f.db.transaction { it.execSQL("DELETE FROM knowledge_items") } }
        assertEquals(1L, f.store.stats().itemCount); assertEquals(1L, f.actual("knowledge_vector_queue"))
        f.db.access { it.execSQL("UPDATE knowledge_vector_counts SET pending=1") }
        f.index(); f.verify()
    }

    @Test fun simultaneousMaintenancePagesSerializeAndReopenWithExactCounts() = KnowledgeCountTestFixture().use { f ->
        f.seed(131); f.indexLegacy(); f.downgrade()
        val executor = Executors.newFixedThreadPool(3)
        try { executor.invokeAll((1..3).map { Callable { f.page(vectors) } }).forEach { it.get(30, TimeUnit.SECONDS) } }
        finally { executor.shutdownNow() }
        f.finishCounts(); f.reopen(); f.verify(); assertEquals(131L, f.counts().chunks)
    }
}

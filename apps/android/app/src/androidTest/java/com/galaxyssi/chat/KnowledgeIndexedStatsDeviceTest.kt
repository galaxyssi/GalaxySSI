package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class KnowledgeIndexedStatsDeviceTest {
    private fun fixture(block: (KnowledgeSourceDirectoryTestFixture) -> Unit) = KnowledgeSourceDirectoryTestFixture().use { f ->
        f.db.execSQL("CREATE INDEX knowledge_updated ON knowledge_items(updated DESC,item_key)")
        block(f)
    }
    private fun reference(f: KnowledgeSourceDirectoryTestFixture): AgentKnowledgeStats = f.db.rawQuery(
        "SELECT count(*),count(DISTINCT NULLIF(source_key,'')),COALESCE(max(updated),0) FROM knowledge_items", null).use {
        check(it.moveToFirst()); AgentKnowledgeStats(it.getLong(0), it.getLong(1), it.getLong(2))
    }
    @Test fun emptyStoreAndLiveMutationsMatchExactSqlCounts() = fixture { f ->
        f.create()
        assertEquals(AgentKnowledgeStats(), KnowledgeIndexedStats.read(f.db))
        f.put(1, "", -20); f.put(2, f.key(7), 300); f.put(3, f.key(7), 700); f.put(4, f.key(9), 100)
        assertEquals(reference(f), KnowledgeIndexedStats.read(f.db))
        f.put(3, "", 50)
        assertEquals(reference(f), KnowledgeIndexedStats.read(f.db))
        f.transaction { f.db.delete("knowledge_items", "item_key=?", arrayOf(f.key(2))) }
        assertEquals(reference(f), KnowledgeIndexedStats.read(f.db))
        f.reopen(); assertEquals(reference(f), KnowledgeIndexedStats.read(f.db))
        f.transaction { f.db.delete("knowledge_items", null, null) }
        assertEquals(AgentKnowledgeStats(), KnowledgeIndexedStats.read(f.db))
    }
    @Test fun partialBackfillIsExplicitAndReadsDoNotAdvanceIt() = fixture { f ->
        repeat(10) { f.put(it, if (it % 2 == 0) "" else f.key(1), it.toLong()) }
        f.create()
        val before = f.state()
        val partial = KnowledgeIndexedStats.read(f.db)
        assertFalse(partial.countsComplete); assertEquals(0L, partial.itemCount)
        assertEquals(9L, partial.lastUpdatedAtMillis)
        assertTrue(partial.countSummary().contains("at least"))
        repeat(16) { assertEquals(partial, KnowledgeIndexedStats.read(f.db)) }
        assertEquals(before, f.state())
        assertFalse(f.page(4)); assertEquals(4L, KnowledgeIndexedStats.read(f.db).itemCount)
        f.put(20, f.key(20), 20)
        assertEquals(5L, KnowledgeIndexedStats.read(f.db).itemCount)
        f.reopen(); assertFalse(KnowledgeIndexedStats.read(f.db).countsComplete)
        f.finish(); assertEquals(reference(f), KnowledgeIndexedStats.read(f.db))
    }
    @Test fun rollbackCannotPublishCounterOrLatestTimeChanges() = fixture { f ->
        f.create(); f.put(1, f.key(1), 5)
        val before = KnowledgeIndexedStats.read(f.db)
        f.db.beginTransaction()
        try {
            f.put(2, f.key(2), 100)
            assertEquals(2L, KnowledgeIndexedStats.read(f.db).itemCount)
        } finally { f.db.endTransaction() }
        assertEquals(before, KnowledgeIndexedStats.read(f.db))
    }
    @Test fun countersRemain64BitAndMissingStateFailsExplicitly() = fixture { f ->
        f.create()
        // Arithmetic contract only; this does not pretend to create billions of rows.
        f.db.execSQL("UPDATE knowledge_source_state SET items=3000000001,groups=3000000000,named_groups=2999999999")
        val stats = KnowledgeIndexedStats.read(f.db)
        assertEquals(3_000_000_001L, stats.itemCount); assertEquals(2_999_999_999L, stats.sourceCount)
        assertTrue(stats.countSummary().contains("3000000001"))
        f.db.execSQL("DELETE FROM knowledge_source_state")
        assertTrue(runCatching { KnowledgeIndexedStats.read(f.db) }.isFailure)
    }
    @Test fun latestUsesCoveringIndexWithoutTemporarySort() = fixture { f ->
        f.create(); f.put(1)
        f.db.rawQuery("EXPLAIN QUERY PLAN ${KnowledgeIndexedStats.LATEST_SQL}", null).use { cursor ->
            val plan = buildList { while (cursor.moveToNext()) add(cursor.getString(3)) }.joinToString(" ")
            assertTrue(plan.contains("COVERING INDEX knowledge_updated")); assertFalse(plan.contains("TEMP B-TREE"))
        }
    }
    @Test fun realEncryptedStoreStatsDoNotDecryptBodiesOrStartAnEmbeddingModel() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val name = "test-indexed-stats-${UUID.randomUUID()}.db"
        val store = SQLiteAgentKnowledgeStore(context, name, "legacy-$name") { _, _ -> }
        val db = AgentKnowledgeDatabase.shared(context, name, "legacy-$name")
        try {
            repeat(8) { store.upsert(AgentKnowledgeItem(id="stats-$it", kind=AgentKnowledgeKind.NOTE,
                title="\u7edf\u8ba1-$it", content="\u4e2d\u6587\u8bb0\u5fc6-$it", source=if (it < 4) "" else "\u6765\u6e90", updatedAtMillis=it.toLong())) }
            val reads = db.decryptedItemReads
            val summaryReads = db.decryptedSourceSummaryReads
            repeat(32) { assertEquals(AgentKnowledgeStats(8, 1, 7), store.stats()) }
            assertEquals(reads, db.decryptedItemReads); assertEquals(summaryReads, db.decryptedSourceSummaryReads)
            assertEquals("not_configured", store.semanticSearchStatus)
        } finally { store.close(); context.deleteDatabase(name); AgentEncryptedPreferences(context, "legacy-$name").clear() }
    }
}

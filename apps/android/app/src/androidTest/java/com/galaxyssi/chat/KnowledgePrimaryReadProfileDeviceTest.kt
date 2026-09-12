package com.galaxyssi.chat

import android.os.Build
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class KnowledgePrimaryReadProfileDeviceTest {
    @Test fun retainedCandidateReadsAndFullTextRanking() {
        val args = InstrumentationRegistry.getArguments()
        val name = args.getString("retainedKnowledgeFixture")
        assumeTrue("Explicit retained fixture required", name != null)
        require(name == "test-knowledge-source-replace-621d79d8-9ce1-4d12-95b8-ebde10511a3f.db")
        val phase = requireNotNull(args.getString("readProfilePhase"))
        require(phase in setOf("before", "after"))
        assertEquals("SM-T575", Build.MODEL)
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        check(context.getDatabasePath(name).isFile)
        val store = SQLiteAgentKnowledgeStore(context, name, "legacy-$name") { _, _ -> }
        try {
            val owner = AgentKnowledgeDatabase.shared(context, name, "legacy-$name")
            assertEquals(10001L, store.stats().itemCount)
            fun measure(label: String, action: () -> Unit) {
                val cacheBefore = KnowledgePrimaryReadConnections.stats()
                val bodiesBefore = owner.decryptedItemReads
                val times = mutableListOf<Long>()
                repeat(6) {
                    val start = System.nanoTime()
                    action()
                    times += System.nanoTime() - start
                }
                val sorted = times.drop(1).sorted()
                val cacheAfter = KnowledgePrimaryReadConnections.stats()
                println("KNOWLEDGE_PRIMARY_READ_PROFILE phase=$phase operation=$label warmup=1 samples=${sorted.size} " +
                    "p50_ns=${sorted[sorted.size / 2]} p95_ns=${sorted.last()} max_ns=${sorted.last()} first_ns=${times.first()} " +
                    "opened=${cacheAfter.opened - cacheBefore.opened} reused=${cacheAfter.reused - cacheBefore.reused} " +
                    "peak=${cacheAfter.peak} decrypted=${owner.decryptedItemReads - bodiesBefore}")
                assertTrue(cacheAfter.peak <= 8)
            }
            measure("fts_256") {
                owner.searchSnapshot().use { read -> read.access { db ->
                    val term = db.rawQuery("SELECT title FROM knowledge_fts ORDER BY rowid LIMIT 1", null).use {
                        assertTrue(it.moveToFirst()); it.getString(0).substringBefore(' ')
                    }
                    assertTrue(term.matches(Regex("[a-f0-9]{64}")))
                    val match = "\"$term\""
                    db.rawQuery("SELECT r.item_key FROM knowledge_fts JOIN knowledge_fts_rows r ON r.rowid=knowledge_fts.rowid " +
                        "WHERE knowledge_fts MATCH ? ORDER BY bm25(knowledge_fts,5.0,2.0,1.0),knowledge_fts.rowid LIMIT 256",
                        arrayOf(match)).use { cursor ->
                        var count = 0
                        while (cursor.moveToNext()) count++
                        assertEquals(256, count)
                    }
                } }
            }
            measure("read_256") {
                owner.searchSnapshot().use { read ->
                    val records = read.recent(256).toList()
                    assertEquals(256, records.size)
                    assertEquals(256, records.map { it.id }.toSet().size)
                    assertTrue(records.all { it.content.contains("[statement-reuse-v1]") })
                }
            }
            measure("lexical_search") {
                val hits = store.search("\u77e5\u8bc6\u6b63\u6587", 8)
                assertEquals(8, hits.size)
                assertEquals(8, hits.map { it.id }.toSet().size)
            }
            assertEquals(10001L, store.stats().itemCount)
        } finally { store.close() }
    }
}

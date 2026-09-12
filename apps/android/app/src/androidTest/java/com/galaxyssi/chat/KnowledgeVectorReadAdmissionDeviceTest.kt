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
class KnowledgeVectorReadAdmissionDeviceTest {
    private val spec = KnowledgeVectorSpec("e".repeat(64), 2, 64)
    private class Encoder(override val spec: KnowledgeVectorSpec) : KnowledgeVectorEncoder {
        override fun tokenCount(text: String) = text.length + 2
        override fun embed(text: String) = floatArrayOf(1f, 0f)
        override fun close() = Unit
    }
    private data class Fixture(val db: AgentKnowledgeDatabase, val store: SQLiteAgentKnowledgeStore,
        val encoder: Encoder, val item: AgentKnowledgeItem)

    private fun isolated(block: (Fixture) -> Unit) {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val name = "test-vector-read-admission-${UUID.randomUUID()}.db"
        val store = SQLiteAgentKnowledgeStore(context, name, "legacy-$name") { _, _ -> }
        val db = AgentKnowledgeDatabase.shared(context, name, "legacy-$name")
        val encoder = Encoder(spec)
        KnowledgeSemanticSearch.resumeRuntime()
        try {
            val item = AgentKnowledgeItem("fruit", AgentKnowledgeKind.NOTE, "F", "orchard")
            store.upsert(item)
            assertFalse(store.indexVectorChunks(encoder, 8).pending)
            KnowledgeNativeIndex(db, spec, 1_000_000).use { assertTrue(it.synchronize {}) }
            block(Fixture(db, store, encoder, item))
        } finally {
            store.close()
            println("KNOWLEDGE_VECTOR_READ retained_fixture=$name")
            KnowledgeSemanticSearch.resumeRuntime()
        }
    }

    @Test fun feedCatalogAndVectorPagesReadCommittedStateDuringReplacement() = isolated { f ->
        val ledger = f.db.vectors(spec)
        val feed = ledger.changes()
        val catalog = KnowledgeVectorCatalog(f.db, ledger)
        val before = requireNotNull(feed.state())
        val stamp = catalog.stamp()
        heldReplacement(f) {
            assertEquals(before, feed.state())
            val page = feed.page(before.epoch, 0, 32)
            assertEquals(before, page.state)
            assertEquals(before.head, page.nextSequence)
            assertFalse(page.hasMore)
            assertEquals(stamp, catalog.stamp())
            assertEquals(1, catalog.count())
            assertEquals(listOf(f.db.key("id", f.item.id)), catalog.keys(""))
            requireNotNull(ledger.page(f.item.id)).use { vectors ->
                assertEquals(1, vectors.total)
                assertArrayEquals(floatArrayOf(1f, 0f), vectors.rows.single().values, 0f)
            }
        }
        assertNotEquals(before, feed.state())
        assertNotEquals(stamp, catalog.stamp())
        assertEquals(0, catalog.count())
        assertNull(ledger.page(f.item.id))
    }

    @Test fun reopenedNativeGraphDoesNotWaitForSourceWriter() = isolated { f ->
        KnowledgeNativeIndex(f.db, spec, 1_000_000).use { index ->
            heldReplacement(f) {
                val start = System.nanoTime()
                assertTrue(index.tryReady {})
                assertEquals(1, index.search(floatArrayOf(1f, 0f)).size)
                assertTrue(index.tryReady {})
                println("KNOWLEDGE_VECTOR_READ phase=reopen elapsed_ns=${System.nanoTime() - start}")
            }
            assertFalse(index.tryReady {})
            assertNull(index.readyStamp)
        }
    }

    @Test fun rankedSemanticQueriesCompleteBeforeSourceWriterCommits() = isolated { f ->
        val session = f.store.attachSemanticEncoder(spec, { f.encoder })
        // No lexical overlap: success must use the actual native graph and source validation.
        heldReplacement(f) {
            val samples = LongArray(100) {
                val start = System.nanoTime()
                assertEquals("orchard", f.store.searchRanked("apple", 8).single().excerpt)
                assertTrue(session.status, session.status.startsWith("ready:"))
                System.nanoTime() - start
            }.sorted()
            println("KNOWLEDGE_VECTOR_READ phase=ranked n=100 p50_ns=${samples[49]} " +
                "p95_ns=${samples[94]} p99_ns=${samples[98]} over_200ms=${samples.count { it > 200_000_000 }}")
        }
        assertTrue(f.store.searchRanked("apple", 8).isEmpty())
    }

    private fun heldReplacement(f: Fixture, read: () -> Unit) {
        val entered = CountDownLatch(1)
        val release = CountDownLatch(1)
        val pool = Executors.newFixedThreadPool(2)
        val writer = pool.submit {
            f.db.transaction { sql ->
                f.db.write(sql, f.item.copy(content = "harbor"))
                entered.countDown()
                check(release.await(30, TimeUnit.SECONDS))
            }
        }
        val reader = pool.submit { check(entered.await(10, TimeUnit.SECONDS)); read() }
        try { reader.get(10, TimeUnit.SECONDS) } finally {
            release.countDown()
            try { writer.get(10, TimeUnit.SECONDS); runCatching { reader.get(10, TimeUnit.SECONDS) } }
            finally { pool.shutdownNow(); assertTrue(pool.awaitTermination(10, TimeUnit.SECONDS)) }
        }
    }
}

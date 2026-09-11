package com.galaxyssi.chat

import android.os.SystemClock
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class KnowledgeRetrievalAdmissionDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val spec = KnowledgeVectorSpec("d".repeat(64), 2, 64)
    private class Encoder(override val spec: KnowledgeVectorSpec) : KnowledgeVectorEncoder {
        val calls = AtomicInteger()
        var before: () -> Unit = {}
        override fun tokenCount(text: String) = text.length + 2
        override fun embed(text: String): FloatArray {
            calls.incrementAndGet(); before()
            if (spec.dimensions != 2) {
                val seed = if (text == "apple") "orchard" else text
                val random = java.util.Random(seed.hashCode().toLong())
                val values = FloatArray(spec.dimensions) { random.nextFloat() - 0.5f }
                val norm = kotlin.math.sqrt(values.sumOf { (it * it).toDouble() }).toFloat()
                return values.apply { indices.forEach { this[it] /= norm } }
            }
            return if (text == "apple" || text == "orchard") floatArrayOf(1f, 0f) else floatArrayOf(0f, 1f)
        }
        override fun close() = Unit
    }
    private fun isolated(vectorSpec: KnowledgeVectorSpec = spec,
        block: (SQLiteAgentKnowledgeStore, AgentKnowledgeDatabase, Encoder) -> Unit) {
        val name = "test-admission-${UUID.randomUUID()}.db"
        val store = SQLiteAgentKnowledgeStore(context, name, "legacy-$name") { _, _ -> }
        val db = AgentKnowledgeDatabase.shared(context, name, "legacy-$name")
        val encoder = Encoder(vectorSpec)
        KnowledgeSemanticSearch.resumeRuntime()
        try {
            store.upsert(AgentKnowledgeItem("fruit", AgentKnowledgeKind.NOTE, "F", "orchard"))
            assertFalse(store.indexVectorChunks(encoder, 8).pending)
            block(store, db, encoder)
        } finally {
            store.close(); context.deleteDatabase(name)
            AgentEncryptedPreferences(context, "legacy-$name").clear()
        }
    }
    private fun timedLexicalQueries(store: SQLiteAgentKnowledgeStore, phase: String) {
        val samples = LongArray(32) {
            val start = SystemClock.elapsedRealtimeNanos()
            assertEquals("fruit", store.search("orchard", 8).single().id)
            (SystemClock.elapsedRealtimeNanos() - start) / 1_000_000
        }.sorted()
        println("KNOWLEDGE_ADMISSION phase=$phase n=32 p50_ms=${samples[15]} p95_ms=${samples[30]} max_ms=${samples.last()} raw_ms=$samples")
        assertTrue("Foreground waited for $phase: $samples", samples.last() < 200)
    }

    @Test fun nativeReadinessNeverRegistersBootstrapsOrReplaysAndReopensReadyGraphs() = isolated { store, db, encoder ->
        var index = KnowledgeNativeIndex(db, spec, 1_000_000)
        val feed = db.vectors(spec).changes()
        val before = feed.state()
        try {
            assertFalse(index.tryReady {})
            assertEquals(before, feed.state())
            assertEquals(0L, index.physicalNodeCount())
            assertTrue(index.synchronize {})
            assertTrue(index.tryReady {})
            val ready = feed.state()
            index.close()
            index = KnowledgeNativeIndex(db, spec, 1_000_000)
            assertTrue(index.tryReady {})
            assertEquals(2L, index.physicalNodeCount())
            assertEquals(ready, feed.state())
            assertEquals(1, index.search(floatArrayOf(1f, 0f)).size)
            store.upsert(AgentKnowledgeItem("fruit", AgentKnowledgeKind.NOTE, "F", "harbor"))
            assertFalse(store.indexVectorChunks(encoder, 8).pending)
            val changed = feed.state()
            assertFalse(index.tryReady {})
            assertNull(index.readyStamp)
            assertEquals(changed, feed.state())
            assertEquals(2L, index.physicalNodeCount())
            assertTrue(index.synchronize {})
            assertTrue(index.tryReady {})
            assertTrue(index.search(floatArrayOf(1f, 0f)).all { it.similarity < 0.35 })
            assertEquals(1, store.delete("harbor"))
            assertFalse(index.tryReady {})
            assertTrue(index.synchronize {})
            assertTrue(index.tryReady {})
            assertTrue(index.search(floatArrayOf(1f, 0f)).isEmpty())
            db.vectors(spec).unregister()
            assertFalse(index.tryReady {})
            assertNull(feed.state())
        } finally { index.close() }
    }

    @Test fun decryptingVectorPagesReleasesTheDatabaseAndRejectsConcurrentSourceChanges() {
        for (mutation in listOf("replace", "delete", "unregister")) isolated { store, db, _ ->
            val ledger = db.vectors(spec)
            val entered = CountDownLatch(1)
            val release = CountDownLatch(1)
            val checks = AtomicInteger()
            val executor = Executors.newSingleThreadExecutor()
            try {
                val work = executor.submit<KnowledgeVectorPage?> {
                    ledger.pageByKey(db.key("id", "fruit"), active = {
                        if (checks.incrementAndGet() == 1) {
                            entered.countDown(); check(release.await(15, TimeUnit.SECONDS))
                        }
                    })
                }
                assertTrue(entered.await(10, TimeUnit.SECONDS))
                timedLexicalQueries(store, "decrypt_$mutation")
                when (mutation) {
                    "replace" -> store.upsert(AgentKnowledgeItem("fruit", AgentKnowledgeKind.NOTE, "F", "harbor"))
                    "delete" -> assertEquals(1, store.delete("orchard"))
                    else -> ledger.unregister()
                }
                assertFalse(work.isDone)
                release.countDown()
                val page = work.get(15, TimeUnit.SECONDS)
                try { assertNull("Obsolete vectors survived $mutation", page) } finally { page?.close() }
            } finally { release.countDown(); executor.shutdownNow(); assertTrue(executor.awaitTermination(15, TimeUnit.SECONDS)) }
        }
    }

    @Test fun cancellationDuringPageDecryptionDoesNotPublishOrDamageTheSource() = isolated { _, db, _ ->
        val ledger = db.vectors(spec)
        val checks = AtomicInteger()
        assertThrows(IllegalStateException::class.java) {
            ledger.pageByKey(db.key("id", "fruit"), active = { check(checks.incrementAndGet() < 2) })
        }
        assertEquals(2, checks.get())
        requireNotNull(ledger.page("fruit")).use { assertEquals(1, it.total) }
    }

    @Test fun sourceBackfillIsScheduledWithoutRunningItInsideTheQuery() = isolated { store, db, encoder ->
        val session = store.attachSemanticEncoder(spec, { encoder })
        val before = encoder.calls.get()
        assertTrue(store.search("apple", 8).isEmpty())
        assertEquals(before, encoder.calls.get())
        val deadline = SystemClock.elapsedRealtime() + 10_000
        while (!session.status.startsWith("ready:") && SystemClock.elapsedRealtime() < deadline) Thread.sleep(10)
        assertTrue(session.status, session.status.startsWith("ready:"))
        assertTrue(db.vectors(spec).changes().state()!!.bootstrapComplete)
        assertEquals("fruit", store.search("apple", 8).single().id)
    }

    @Test fun queriesDoNotQueueBehindTheRealBackgroundReplayOwner() = isolated { store, _, encoder ->
        val session = store.attachSemanticEncoder(spec, { encoder })
        val entered = CountDownLatch(1)
        val release = CountDownLatch(1)
        val checks = AtomicInteger()
        val executor = Executors.newSingleThreadExecutor()
        try {
            val write = executor.submit<Boolean> { session.advanceIndex {
                if (checks.incrementAndGet() == 2) { entered.countDown(); check(release.await(15, TimeUnit.SECONDS)) }
                false
            } }
            assertTrue(entered.await(10, TimeUnit.SECONDS))
            val calls = encoder.calls.get()
            timedLexicalQueries(store, "replay_owner")
            assertEquals(calls, encoder.calls.get())
            assertFalse(write.isDone)
            release.countDown()
            assertTrue(write.get(15, TimeUnit.SECONDS))
            assertEquals("fruit", store.search("apple", 8).single().id)
        } finally { release.countDown(); executor.shutdownNow(); assertTrue(executor.awaitTermination(15, TimeUnit.SECONDS)) }
    }

    @Test fun aConcurrentSlowEncoderDoesNotBlockOtherQueriesOrPublishDeletedSources() = isolated { store, _, encoder ->
        val session = store.attachSemanticEncoder(spec, { encoder })
        assertTrue(session.advanceIndex())
        val entered = CountDownLatch(1)
        val release = CountDownLatch(1)
        val executor = Executors.newSingleThreadExecutor()
        encoder.before = { entered.countDown(); check(release.await(15, TimeUnit.SECONDS)) }
        try {
            val first = executor.submit<List<AgentKnowledgeItem>> { store.search("apple", 8) }
            assertTrue(entered.await(10, TimeUnit.SECONDS))
            val calls = encoder.calls.get()
            timedLexicalQueries(store, "slow_encoder")
            assertEquals(calls, encoder.calls.get())
            assertEquals(1, store.delete("orchard"))
            assertTrue(store.search("orchard", 8).isEmpty())
            assertFalse(first.isDone)
            release.countDown()
            assertTrue(first.get(15, TimeUnit.SECONDS).isEmpty())
            encoder.before = {}
            assertTrue(session.advanceIndex())
            assertTrue(store.search("apple", 8).isEmpty())
        } finally { release.countDown(); executor.shutdownNow(); assertTrue(executor.awaitTermination(15, TimeUnit.SECONDS)) }
    }

    @Test fun fullWidthMultiPageReplayKeepsForegroundQueriesResponsive() =
        isolated(KnowledgeVectorSpec("e".repeat(64), 512, 64)) { store, db, encoder ->
            val body = (1..512).joinToString("\n") { "Backlog record $it" }
            store.upsert(AgentKnowledgeItem("backlog", AgentKnowledgeKind.NOTE, "Backlog", body))
            var batch = store.indexVectorChunks(encoder, 256)
            while (batch.pending) batch = store.indexVectorChunks(encoder, 256)
            val count = db.vectors(encoder.spec).changes().state()!!.completedChunks
            assertTrue("Expected multi-page full-width vectors, got $count", count >= 128)
            println("KNOWLEDGE_ADMISSION_CORPUS dimensions=512 chunks=$count backlog_records=512")
            val session = store.attachSemanticEncoder(encoder.spec, { encoder })
            val entered = CountDownLatch(1)
            val executor = Executors.newSingleThreadExecutor()
            try {
                val start = SystemClock.elapsedRealtime()
                val work = executor.submit<Boolean> { session.advanceIndex { entered.countDown(); false } }
                assertTrue(entered.await(10, TimeUnit.SECONDS))
                timedLexicalQueries(store, "actual_512d_replay")
                work.get(180, TimeUnit.SECONDS)
                val deadline = SystemClock.elapsedRealtime() + 180_000
                while (!session.advanceIndex()) {
                    check(SystemClock.elapsedRealtime() < deadline) { "Native backlog did not settle" }
                }
                assertTrue(session.status, session.status.startsWith("ready:"))
                println("KNOWLEDGE_ADMISSION_REPLAY dimensions=512 chunks=$count elapsed_ms=${SystemClock.elapsedRealtime() - start}")
                val result = store.search("apple", 1)
                assertEquals(session.status, listOf("fruit"), result.map { it.id })
                assertTrue(session.status, session.status.startsWith("ready:"))
            } finally { executor.shutdownNow(); assertTrue(executor.awaitTermination(180, TimeUnit.SECONDS)) }
        }
}

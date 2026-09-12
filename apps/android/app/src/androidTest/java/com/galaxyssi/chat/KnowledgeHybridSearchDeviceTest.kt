package com.galaxyssi.chat

import android.os.SystemClock
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
class KnowledgeHybridSearchDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val spec = KnowledgeVectorSpec("a".repeat(64), 2, 64)
    private class Encoder(override val spec: KnowledgeVectorSpec) : KnowledgeVectorEncoder {
        var before: () -> Unit = {}
        var last: FloatArray? = null
        val closed = CountDownLatch(1)
        override fun tokenCount(text: String) = text.length + 2
        override fun embed(text: String): FloatArray {
            before()
            return (if (text == "orchard" || text == "apple") floatArrayOf(1f, 0f) else floatArrayOf(0f, 1f)).also { last = it }
        }
        override fun close() { closed.countDown() }
    }
    private data class Fixture(val store: SQLiteAgentKnowledgeStore, val db: AgentKnowledgeDatabase, val encoder: Encoder)
    private fun prepare(f: Fixture): KnowledgeSemanticSearch =
        f.store.attachSemanticEncoder(spec, { f.encoder }).also { assertTrue(it.advanceIndex()) }
    private fun isolated(block: (Fixture) -> Unit) {
        val name = "test-hybrid-${UUID.randomUUID()}.db"
        val store = SQLiteAgentKnowledgeStore(context, name, "legacy-$name") { _, _ -> }
        val encoder = Encoder(spec)
        KnowledgeSemanticSearch.resumeRuntime()
        try {
            store.upsert(AgentKnowledgeItem("fruit", AgentKnowledgeKind.NOTE, "F", "orchard"))
            store.upsert(AgentKnowledgeItem("water", AgentKnowledgeKind.NOTE, "W", "harbor"))
            assertFalse(store.indexVectorChunks(encoder, 8).pending)
            block(Fixture(store, AgentKnowledgeDatabase.shared(context, name, "legacy-$name"), encoder))
        } finally {
            store.close()
            KnowledgeSemanticSearch.resumeRuntime()
            context.deleteDatabase(name)
            AgentEncryptedPreferences(context, "legacy-$name").clear()
        }
    }
    @Test fun normalStoreAndRagRetrieveWithoutAnyLexicalOverlapAndHonorCloudPolicy() = isolated { f ->
        assertTrue(f.store.search("apple", 8).isEmpty())
        prepare(f)
        assertEquals("fruit", f.store.search("apple", 8).single().id)
        assertTrue(f.store.semanticSearchStatus.startsWith("ready:"))
        assertTrue(requireNotNull(f.encoder.last).all { it == 0f })
        assertEquals("fruit", AgentKnowledgeRetriever.retrieve(f.store, "apple", "agent-knowledge-local").citations.single().itemId)
        val cloud = AgentKnowledgeRetriever.retrieve(f.store, "apple", "cloud-model:fixture")
        assertTrue(cloud.citations.isEmpty()); assertEquals(1, cloud.blockedMatchCount)
        val snapshot = f.store.querySnapshot("apple", 8)
        assertEquals("fruit", snapshot.items.single().id); assertEquals(2L, snapshot.stats.itemCount)
    }
    @Test fun sourceReplacementInvalidatesCachedVectorsAndDoesNotReturnOldExcerpt() = isolated { f ->
        prepare(f)
        assertEquals("orchard", f.store.searchRanked("apple", 8).single().excerpt)
        f.store.upsert(AgentKnowledgeItem("fruit", AgentKnowledgeKind.NOTE, "F", "harbor"))
        assertTrue(f.store.search("apple", 8).isEmpty())
        assertFalse(f.store.indexVectorChunks(f.encoder, 8).pending)
        assertTrue(f.store.search("apple", 8).isEmpty())
    }
    @Test fun permissionChangesCannotReuseAnOlderMorePermissiveSource() = isolated { f ->
        f.store.updateAccess(setOf("fruit"), AgentKnowledgeCloudAccess.FULL, AgentKnowledgeAgentAccess.LOCAL_ONLY, emptyList())
        assertFalse(f.store.indexVectorChunks(f.encoder, 8).pending)
        prepare(f)
        assertEquals(1, AgentKnowledgeRetriever.retrieve(f.store, "apple", "cloud-model:fixture").citations.size)
        f.store.updateAccess(setOf("fruit"), AgentKnowledgeCloudAccess.DENY, AgentKnowledgeAgentAccess.LOCAL_ONLY, emptyList())
        assertTrue(AgentKnowledgeRetriever.retrieve(f.store, "apple", "cloud-model:fixture").citations.isEmpty())
        assertFalse(f.store.indexVectorChunks(f.encoder, 8).pending)
        assertTrue(AgentKnowledgeRetriever.retrieve(f.store, "apple", "cloud-model:fixture").citations.isEmpty())
    }
    @Test fun uiThreadNeverOpensAnEmbeddingModel() = isolated { f ->
        var opened = false
        f.store.attachSemanticEncoder(spec, { opened = true; f.encoder })
        InstrumentationRegistry.getInstrumentation().runOnMainSync {
            assertEquals("fruit", f.store.search("orchard", 8).single().id)
        }
        assertFalse(opened)
        assertEquals("requires_worker_thread", f.store.semanticSearchStatus)
    }
    @Test fun mutationWhileQueryModelRunsCannotPublishAnOldVectorMatch() = isolated { f ->
        prepare(f)
        f.encoder.before = { f.store.upsert(AgentKnowledgeItem("fruit", AgentKnowledgeKind.NOTE, "F", "harbor")) }
        assertTrue(f.store.search("apple", 8).isEmpty())
        assertTrue(f.store.semanticSearchStatus.startsWith("unavailable:"))
    }
    @Test fun hybridRankingSharesAReadViewWithoutHoldingWriterAndRevalidatesEvidence() = isolated { f ->
        val session = prepare(f)
        val writer = Executors.newSingleThreadExecutor()
        try {
            val result = session.search("apple", 8) { read ->
                assertNotNull(read)
                assertEquals("fruit", KnowledgeLexicalSearch.search(requireNotNull(read), "orchard", 8).single().item.id)
                writer.submit { f.store.upsert(AgentKnowledgeItem("fruit", AgentKnowledgeKind.NOTE, "F", "harbor")) }
                    .get(10, TimeUnit.SECONDS)
                // The WAL view still contains the old item, but final publication must reject it.
                KnowledgeLexicalSearch.search(read, "orchard", 8)
            }
            assertTrue(result.isEmpty())
            assertTrue(f.store.search("orchard", 8).isEmpty())
        } finally { writer.shutdownNow(); assertTrue(writer.awaitTermination(10, TimeUnit.SECONDS)) }
    }
    @Test fun insufficientAnnMemoryIsExplicitAndKeepsLexicalResultsAndAllSources() = isolated { f ->
        f.store.attachSemanticEncoder(spec, { f.encoder }, budgetBytes = 1)
        assertEquals("fruit", f.store.search("orchard", 8).single().id)
        assertTrue(f.store.semanticSearchStatus.startsWith("unavailable:"))
        assertEquals(2L, f.store.stats().itemCount)
    }
    @Test fun lifecycleInvalidationDuringPublicationCannotReturnStaleEvidence() = isolated { f ->
        val session = prepare(f)
        val prepared = CountDownLatch(1)
        val release = CountDownLatch(1)
        val executor = Executors.newSingleThreadExecutor()
        try {
            val result = executor.submit<List<AgentKnowledgeHit>> {
                session.search("apple", 8) { read ->
                    if (read == null) emptyList() else {
                        val hits = KnowledgeLexicalSearch.search(read, "orchard", 8)
                        // Pause after candidate calculation, before validation and publication.
                        prepared.countDown()
                        check(release.await(10, TimeUnit.SECONDS))
                        hits
                    }
                }
            }
            assertTrue(prepared.await(10, TimeUnit.SECONDS))
            assertFalse(result.isDone)
            session.invalidate()
            release.countDown()
            assertTrue(result.get(10, TimeUnit.SECONDS).isEmpty())
        } finally { release.countDown(); executor.shutdownNow(); assertTrue(executor.awaitTermination(10, TimeUnit.SECONDS)) }
    }
    @Test fun corruptAuthenticatedVectorFallsBackWithoutPublishingDerivedEvidence() = isolated { f ->
        val session = f.store.attachSemanticEncoder(spec, { f.encoder })
        f.db.access { it.execSQL("UPDATE knowledge_vectors SET ciphertext=zeroblob(length(ciphertext))") }
        assertTrue(runCatching { session.advanceIndex() }.isFailure)
        assertTrue(f.store.semanticSearchStatus.startsWith("unavailable:"))
        assertTrue(f.store.search("apple", 8).isEmpty())
        assertEquals("fruit", f.store.search("orchard", 8).single().id)
    }
    @Test fun lifecycleInvalidationDoesNotBlockUiOrAllowLateResults() = isolated { f ->
        val entered = CountDownLatch(1)
        val release = CountDownLatch(1)
        val session = prepare(f)
        f.encoder.before = { entered.countDown(); check(release.await(10, TimeUnit.SECONDS)) }
        val executor = Executors.newSingleThreadExecutor()
        try {
            val future = executor.submit<List<AgentKnowledgeItem>> { f.store.search("apple", 8) }
            assertTrue(entered.await(10, TimeUnit.SECONDS))
            val start = SystemClock.elapsedRealtime()
            KnowledgeSemanticSearch.clearRuntime(suspend = true)
            assertTrue("Lifecycle callback blocked", SystemClock.elapsedRealtime() - start < 100)
            release.countDown()
            assertTrue(future.get(10, TimeUnit.SECONDS).isEmpty())
            assertTrue(requireNotNull(f.encoder.last).all { it == 0f })
            f.encoder.before = {}
            KnowledgeSemanticSearch.resumeRuntime()
            assertTrue(session.advanceIndex())
            val result = f.store.search("apple", 8)
            assertEquals(session.status, listOf("fruit"), result.map { it.id })
        } finally { release.countDown(); executor.shutdownNow() }
    }
    @Test fun shortTtlAndExplicitCloseInvalidateTheGraph() = isolated { f ->
        val session = KnowledgeSemanticSearch(f.db, spec, { f.encoder }, 1_000_000, ttlMillis = 100)
        try {
            assertTrue(session.advanceIndex())
            assertEquals("fruit", session.search("apple", 8) { emptyList() }.single().item.id)
            val until = SystemClock.elapsedRealtime() + 3000
            while (session.status != "invalidated" && SystemClock.elapsedRealtime() < until) Thread.sleep(10)
            assertEquals("invalidated", session.status)
            assertEquals("fruit", session.search("apple", 8) { emptyList() }.single().item.id)
        } finally { session.close() }
        assertTrue(f.encoder.closed.await(5, TimeUnit.SECONDS))
        assertTrue(session.search("apple", 8) { emptyList() }.isEmpty())
    }
    @Test fun ttlExpirationDoesNotCancelAQueryAlreadyUsingTheCache() = isolated { f ->
        val session = KnowledgeSemanticSearch(f.db, spec, { f.encoder }, 1_000_000, ttlMillis = 50)
        f.encoder.before = { Thread.sleep(150) }
        try {
            assertTrue(session.advanceIndex())
            val result = session.search("apple", 8) { emptyList() }
            assertEquals(session.status, listOf("fruit"), result.map { it.item.id })
            assertTrue(f.encoder.closed.await(5, TimeUnit.SECONDS))
        } finally { session.close() }
    }
}

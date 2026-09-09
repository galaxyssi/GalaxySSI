package com.galaxyssi.chat

import android.os.SystemClock
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.UUID
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class KnowledgeHybridNeuralDeviceTest {
    @Test fun actualChineseNeuralQueriesUseTheNormalStoreAndRagAfterReopen() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val model = File(context.getExternalFilesDir(null), "embedding-test/bge-small-zh-v1.5-q8_0.gguf")
        assumeTrue("Install the pinned real-model fixture", model.isFile)
        val spec = KnowledgeVectorSpec("5a88d266870fbd27c6f329df60de80e2d4cf3bbd5e6f080bd5c1b2e5abb12039", 512, 64)
        val name = "test-neural-hybrid-${UUID.randomUUID()}.db"
        var store = SQLiteAgentKnowledgeStore(context, name, "legacy-$name") { _, _ -> }
        KnowledgeSemanticSearch.resumeRuntime()
        try {
            val passages = listOf(
                "\u624b\u673a\u4e22\u5931\u540e\u53ef\u4ee5\u901a\u8fc7\u5b9a\u4f4d\u529f\u80fd\u67e5\u627e\u8bbe\u5907",
                "\u4fee\u6539\u767b\u5f55\u5bc6\u7801\u9700\u8981\u5728\u8d26\u53f7\u5b89\u5168\u9875\u9762\u8fdb\u884c",
                "\u6570\u636e\u5e93\u5efa\u7acb\u7d22\u5f15\u53ef\u4ee5\u52a0\u5feb\u67e5\u8be2\u901f\u5ea6"
            )
            passages.forEachIndexed { id, content -> store.upsert(AgentKnowledgeItem("doc-$id", AgentKnowledgeKind.NOTE, "Record $id", content)) }
            LlamaKnowledgeVectorEncoder.open(context, model, spec).use { encoder ->
                assertFalse(store.indexVectorChunks(encoder, 8).pending)
            }
            store.close()
            store = SQLiteAgentKnowledgeStore(context, name, "legacy-$name") { _, _ -> }
            store.attachSemanticEncoder(spec, { LlamaKnowledgeVectorEncoder.open(context, model, spec) })
            val queries = listOf("\u6211\u7684\u7535\u8bdd\u627e\u4e0d\u5230\u4e86\u600e\u4e48\u529e",
                "\u600e\u6837\u66f4\u6362\u8d26\u6237\u53e3\u4ee4", "\u600e\u6837\u8ba9SQL\u68c0\u7d22\u66f4\u5feb")
            queries.forEachIndexed { id, query ->
                val result = AgentKnowledgeRetriever.retrieve(store, query, "agent-knowledge-local", 1)
                assertEquals("doc-$id", result.citations.single().itemId)
                assertTrue(store.semanticSearchStatus, store.semanticSearchStatus.startsWith("ready:"))
            }
            val samples = LongArray(100) { sample ->
                val start = SystemClock.elapsedRealtimeNanos()
                val id = sample % queries.size
                assertEquals("doc-$id", store.search(queries[id], 1).single().id)
                (SystemClock.elapsedRealtimeNanos() - start) / 1_000_000
            }.sorted()
            println("KNOWLEDGE_HYBRID_REAL recall_at_1=3/3 samples=100 p50_ms=${samples[49]} p95_ms=${samples[94]} p99_ms=${samples[98]}")
            assertTrue("Hot hybrid retrieval P95 too slow: ${samples[94]}", samples[94] < 500)
        } finally {
            store.close()
            context.deleteDatabase(name)
            AgentEncryptedPreferences(context, "legacy-$name").clear()
        }
    }
}

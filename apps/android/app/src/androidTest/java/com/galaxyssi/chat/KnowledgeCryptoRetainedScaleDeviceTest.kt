package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import com.galaxyssi.chat.metrics.*

@RunWith(AndroidJUnit4::class)
class KnowledgeCryptoRetainedScaleDeviceTest {
    @Test fun rewriteAndVerifyTheSameTenThousandEncryptedBodies() {
        val name = InstrumentationRegistry.getArguments().getString("retainedKnowledgeFixture")
        assumeTrue("Explicit retained synthetic fixture required", name != null)
        requireNotNull(name)
        require(name.matches(Regex("test-knowledge-source-replace-[a-f0-9-]+\\.db")))
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        check(context.getDatabasePath(name).isFile)
        val source = "\u6765\u6e90"
        val variant = InstrumentationRegistry.getArguments().getString("retainedKnowledgeVariant").orEmpty()
        require(variant.isEmpty() || variant.matches(Regex("[a-z0-9-]{1,64}")))
        val content = "\u66f4\u65b0 " + "\u77e5\u8bc6\u6b63\u6587".repeat(80) +
            if (variant.isEmpty()) "" else " [$variant]"
        var observed = 0
        val points = mutableListOf<AgentTimingPoint>()
        val timing = KnowledgeSourceWriteTiming(AgentRuntimeTiming({ trace, stage, operation, outcome, at ->
            points += AgentTimingPoint(trace, "a".repeat(32), stage, at, 0, operation, outcome = outcome)
        }))
        val store = SQLiteAgentKnowledgeStore(context, name, "legacy-$name", publishSource = { mutation ->
            GlobalPersistentContextObservationExtractor.knowledgeSourceMutation(mutation, 1234)
            observed++
        }) { _, _ -> }
        try {
            assertEquals(10_001L, store.stats().itemCount)
            val started = System.nanoTime()
            store.replaceSource(source, (1_000..11_000).asSequence().map { i ->
                AgentKnowledgeItem(id = "replace-$i", kind = AgentKnowledgeKind.DOCUMENT,
                    title = "\u6d4b\u8bd5 $i", content = "$content $i", source = source,
                    chunkIndex = i, chunkCount = 10_001, updatedAtMillis = i.toLong())
            }, timing)
            println("KNOWLEDGE_CRYPTO_SCALE replace_ms=${(System.nanoTime() - started) / 1_000_000} rows=10001 fixture=$name variant=$variant")
            for (phase in listOf("total", "stage", "prepare", "commit", "ownership", "apply", "observe")) {
                val metric = AgentLatencyContract.summarize(points).getValue("phone_runtime_knowledge_source_${phase}_ms")
                assertEquals(phase, 1, metric.count)
                assertEquals(phase, 0, metric.unsuccessful)
                println("KNOWLEDGE_CRYPTO_SCALE phase=$phase elapsed_ms=${metric.p95Ms} rows=10001")
            }
            assertEquals(1, observed)
            val statements = AgentKnowledgeDatabase.shared(context, name, "legacy-$name").access { it.statementStats }
            println("KNOWLEDGE_CRYPTO_SCALE prepared=${statements.prepared} reused=${statements.reused} " +
                "idle_statements=${statements.idle} idle_sql_chars=${statements.sqlChars}")
        } finally { store.close() }
        AgentRowStorageCipher.clearCachedKeys()
        val reopened = SQLiteAgentKnowledgeStore(context, name, "legacy-$name") { _, _ -> }
        try {
            val started = System.nanoTime()
            val seen = java.util.BitSet(10_001)
            AgentKnowledgeDatabase.shared(context, name, "legacy-$name").backupSnapshot().use { snapshot ->
                snapshot.items().forEach { item ->
                    val index = item.id.removePrefix("replace-").toInt()
                    assertTrue(index in 1_000..11_000)
                    assertFalse(seen[index - 1_000]); seen.set(index - 1_000)
                    assertEquals("$content $index", item.content)
                }
            }
            assertEquals(10_001, seen.cardinality())
            assertEquals(10_001L, reopened.stats().itemCount)
            assertTrue(reopened.findByIds(setOf("replace-500", "replace-999")).isEmpty())
            println("KNOWLEDGE_CRYPTO_SCALE verify_ms=${(System.nanoTime() - started) / 1_000_000} verified=${seen.cardinality()}")
        } finally { reopened.close() }
    }
}

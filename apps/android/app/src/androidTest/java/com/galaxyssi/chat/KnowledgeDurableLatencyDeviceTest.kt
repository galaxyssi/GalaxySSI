package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class KnowledgeDurableLatencyDeviceTest {
    @Test fun retainedPublicReadsAndIndividualDurableWritesPreserveEveryProbedRecord() {
        val name = requireNotNull(InstrumentationRegistry.getArguments().getString("retainedKnowledgeFixture"))
        require(name == "test-knowledge-source-replace-621d79d8-9ce1-4d12-95b8-ebde10511a3f.db")
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        check(context.getDatabasePath(name).isFile) { "Retained real-body fixture is required" }
        val store = SQLiteAgentKnowledgeStore(context, name, "legacy-$name") { _, _ -> }
        val reads = LongArray(100)
        val writes = LongArray(100)
        val restores = LongArray(100)
        try {
            assertEquals(10_001L, store.stats().itemCount)
            repeat(100) { index ->
                val id = "replace-${1000 + index}"
                val started = System.nanoTime()
                val before = store.findByIds(setOf(id)).single()
                reads[index] = System.nanoTime() - started
                assertEquals(id, before.id)
                val changed = before.copy(content = before.content + " [\u6301\u4e45\u5316\u5199\u5165-$index]")
                try {
                    val writeStarted = System.nanoTime()
                    // No surrounding transaction: upsert includes partition and catalog commits.
                    store.upsert(changed)
                    writes[index] = System.nanoTime() - writeStarted
                    assertEquals(changed, store.findByIds(setOf(id)).single())
                } finally {
                    val restoreStarted = System.nanoTime()
                    store.upsert(before)
                    restores[index] = System.nanoTime() - restoreStarted
                    assertEquals(before, store.findByIds(setOf(id)).single())
                }
            }
            assertEquals(10_001L, store.stats().itemCount)
            report("public_read", reads)
            report("durable_upsert", writes)
            report("durable_restore", restores)
        } finally { store.close(); AgentKnowledgeDatabase.release(context, name) }
        val reopened = SQLiteAgentKnowledgeStore(context, name, "legacy-$name") { _, _ -> }
        try {
            assertEquals(10_001L, reopened.stats().itemCount)
            repeat(100) { index ->
                val item = reopened.findByIds(setOf("replace-${1000 + index}")).single()
                assertFalse(item.content.contains("[\u6301\u4e45\u5316\u5199\u5165-"))
            }
        } finally { reopened.close(); AgentKnowledgeDatabase.release(context, name) }
        println("KNOWLEDGE_DURABLE_PROFILE corpus=10001 restored=100 reopened=100 observers=disabled models=disabled")
    }

    private fun report(operation: String, samples: LongArray) {
        assertTrue(samples.all { it > 0 })
        samples.sort()
        println("KNOWLEDGE_DURABLE_PROFILE operation=$operation samples=${samples.size} " +
            "p50_ns=${samples[49]} p95_ns=${samples[94]} p99_ns=${samples[98]} max_ns=${samples.last()} " +
            "within_200ms=${samples.count { it <= 200_000_000 }}")
    }
}

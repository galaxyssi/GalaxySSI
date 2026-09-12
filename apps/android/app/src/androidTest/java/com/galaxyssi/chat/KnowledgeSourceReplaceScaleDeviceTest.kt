package com.galaxyssi.chat

import android.os.SystemClock
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class KnowledgeSourceReplaceScaleDeviceTest {
    @Test fun tenThousandEncryptedBodiesSurviveStreamingReplacementAndReopen() = KnowledgeSourceReplaceFixture().use { f ->
        fun item(i: Int) = f.item(i).copy(content = "\u77e5\u8bc6\u6b63\u6587".repeat(80) + " $i", chunkCount = 10_001)
        val start = SystemClock.elapsedRealtime()
        f.store.replaceSource("\u6765\u6e90", (0..10_000).asSequence().map(::item).constrainOnce())
        val seeded = SystemClock.elapsedRealtime()
        assertEquals(10_001L, f.store.stats().itemCount)
        var sampledPeak = 0L
        var produced = 0
        f.store.replaceSource("\u6765\u6e90", (500..10_500).asSequence().map {
            produced++
            sampledPeak = maxOf(sampledPeak, Runtime.getRuntime().totalMemory() - Runtime.getRuntime().freeMemory())
            item(it).copy(content = "\u66f4\u65b0 ${item(it).content}")
        }.constrainOnce())
        val replaced = SystemClock.elapsedRealtime()
        assertEquals(10_001, produced); assertEquals(10_001L, f.store.stats().itemCount)
        assertEquals("10001", f.events.single().metadata["item_count"])
        assertEquals(GlobalConversationEventType.KNOWLEDGE_UPDATED, f.events.single().type)
        f.reopen()
        assertEquals(10_001L, f.store.stats().itemCount)
        assertTrue(f.store.findByIds(setOf("replace-0", "replace-499")).isEmpty())
        val endpoints = f.store.findByIds(setOf("replace-500", "replace-10500"))
        assertEquals(2, endpoints.size); assertTrue(endpoints.all { it.content.startsWith("\u66f4\u65b0 ") })
        val seen = java.util.BitSet(10_001)
        f.db.backupSnapshot().use { view ->
            // Verify every body by stable ID without building a corpus-sized result list.
            for (actual in view.items()) {
                val id = actual.id.removePrefix("replace-").toInt()
                assertTrue(id in 500..10_500); assertFalse(seen[id - 500]); seen.set(id - 500)
                assertEquals("\u66f4\u65b0 ${item(id).content}", actual.content)
            }
        }
        assertEquals(10_001, seen.cardinality())
        println("KNOWLEDGE_SOURCE_REPLACE_SCALE rows=10001 seedMs=${seeded - start} replaceMs=${replaced - seeded} " +
            "verifyMs=${SystemClock.elapsedRealtime() - replaced} producerSampledJavaHeapBytes=$sampledPeak " +
            "databaseBytes=${f.context.getDatabasePath(f.name).length()}")
    }
}

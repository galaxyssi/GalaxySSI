package com.galaxyssi.chat

import android.os.Build
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.security.MessageDigest
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class KnowledgePrimaryCompactionRetainedDeviceTest {
    @Test fun compactRetainedRealBodiesAndVerifyAllRecordsAcrossReopening() {
        val name = InstrumentationRegistry.getArguments().getString("retainedKnowledgeFixture")
        assumeTrue("Explicit retained fixture required", name != null)
        require(name == "test-knowledge-source-replace-621d79d8-9ce1-4d12-95b8-ebde10511a3f.db")
        assertEquals("SM-T575", Build.MODEL)
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        check(context.getDatabasePath(name).isFile)
        var store = SQLiteAgentKnowledgeStore(context, name, "legacy-$name") { _, _ -> }
        fun owner() = AgentKnowledgeDatabase.shared(context, name, "legacy-$name")
        fun digest(): String {
            val sha = MessageDigest.getInstance("SHA-256")
            val seen = java.util.BitSet(10_001)
            owner().backupSnapshot().use { snapshot -> snapshot.items().forEach { item ->
                val index = item.id.removePrefix("replace-").toInt()
                assertTrue(index in 1000..11000); assertFalse(seen[index - 1000]); seen.set(index - 1000)
                val bytes = AgentKnowledgeCodec.encodeItem(item).toString().toByteArray()
                try { sha.update(java.nio.ByteBuffer.allocate(4).putInt(bytes.size).array()); sha.update(bytes) }
                finally { bytes.fill(0) }
            } }
            assertEquals(10_001, seen.cardinality())
            return sha.digest().joinToString("") { "%02x".format(it) }
        }
        fun revision() = owner().readCommitted { KnowledgeSourceSelection(owner(), AgentKnowledgeSourceReference("\u6765\u6e90")).revision(it) }
        fun bytes() = File(context.getDatabasePath(name).absolutePath + ".primary").listFiles()!!.sumOf { it.length() }
        try {
            assertEquals(10_001L, store.stats().itemCount)
            val before = digest(); val revision = revision(); val beforeBytes = bytes()
            val times = mutableListOf<Long>()
            var moved = 0; var reclaimed = 0L; var retired = 0
            val start = System.nanoTime()
            while (true) {
                val tick = System.nanoTime()
                val page = requireNotNull(owner().reclaimPrimary())
                times.add(System.nanoTime() - tick)
                assertTrue(page.movedRecords <= 8)
                moved += page.movedRecords; reclaimed += page.bytes; retired += page.partitions
                if (page.complete) break
                if (times.size % 100 == 0) println("KNOWLEDGE_COMPACTION_SCALE pages=${times.size} moved=$moved")
                if (times.size % 250 == 0) {
                    store.close(); store = SQLiteAgentKnowledgeStore(context, name, "legacy-$name") { _, _ -> }
                }
                assertTrue("Maintenance did not converge", times.size < 10_000)
            }
            val elapsed = (System.nanoTime() - start) / 1_000_000
            store.close(); AgentRowStorageCipher.clearCachedKeys()
            store = SQLiteAgentKnowledgeStore(context, name, "legacy-$name") { _, _ -> }
            assertEquals(before, digest()); assertEquals(revision, revision())
            assertEquals(10_001L, store.stats().itemCount)
            val sorted = times.sorted()
            println("KNOWLEDGE_COMPACTION_SCALE verified=10001 digest=$before pages=${times.size} moved=$moved retired=$retired " +
                "elapsed_ms=$elapsed page_p95_ms=${sorted[((sorted.size - 1) * .95).toInt()] / 1_000_000.0} " +
                "page_max_ms=${sorted.last() / 1_000_000.0} before_bytes=$beforeBytes after_bytes=${bytes()} reclaimed_bytes=$reclaimed")
        } finally { store.close() }
    }
}

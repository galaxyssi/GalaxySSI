package com.galaxyssi.chat

import android.os.Build
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.security.MessageDigest
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class KnowledgePrimaryRetainedDeviceTest {
    @Test fun migrateAndReopenAllRetainedRealBodiesWithoutRewritingLogicalRevisions() {
        val args = InstrumentationRegistry.getArguments()
        val name = args.getString("retainedKnowledgeFixture")
        assumeTrue("Explicit retained fixture required", name != null)
        requireNotNull(name)
        assertEquals("SM-T575", Build.MODEL)
        require(name == "test-knowledge-source-replace-621d79d8-9ce1-4d12-95b8-ebde10511a3f.db")
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        check(context.getDatabasePath(name).isFile)
        var store = SQLiteAgentKnowledgeStore(context, name, "legacy-$name") { _, _ -> }
        fun owner() = AgentKnowledgeDatabase.shared(context, name, "legacy-$name")
        fun digest(): String {
            val sha = MessageDigest.getInstance("SHA-256")
            val seen = java.util.BitSet(10_001)
            owner().backupSnapshot().use { snapshot -> snapshot.items().forEach { item ->
                val index = item.id.removePrefix("replace-").toInt()
                assertTrue(index in 1000..11000)
                assertFalse(seen[index - 1000]); seen.set(index - 1000)
                val bytes = AgentKnowledgeCodec.encodeItem(item).toString().toByteArray()
                try { sha.update(java.nio.ByteBuffer.allocate(4).putInt(bytes.size).array()); sha.update(bytes) }
                finally { bytes.fill(0) }
            } }
            assertEquals(10_001, seen.cardinality())
            return sha.digest().joinToString("") { "%02x".format(it) }
        }
        try {
            assertEquals(10_001L, store.stats().itemCount)
            val before = digest()
            val selection = KnowledgeSourceSelection(owner(), AgentKnowledgeSourceReference("\u6765\u6e90"))
            val revision = owner().readCommitted(selection::revision)
            var pages = 0; var moved = 0
            var longest = 0L
            val started = System.nanoTime()
            while (true) {
                val pageStarted = System.nanoTime()
                val page = owner().migratePrimaryPage()
                longest = maxOf(longest, System.nanoTime() - pageStarted)
                pages++; moved += page.moved
                assertTrue(page.visited <= 8)
                if (pages % 100 == 0) println("KNOWLEDGE_PRIMARY_SCALE pages=$pages moved=$moved")
                if (page.complete) break
                if (pages % 250 == 0) {
                    store.close(); store = SQLiteAgentKnowledgeStore(context, name, "legacy-$name") { _, _ -> }
                }
            }
            println("KNOWLEDGE_PRIMARY_SCALE migration_ms=${(System.nanoTime()-started)/1000000} pages=$pages moved=$moved max_page_ms=${longest/1000000}")
            store.close(); AgentRowStorageCipher.clearCachedKeys()
            store = SQLiteAgentKnowledgeStore(context, name, "legacy-$name") { _, _ -> }
            assertEquals(before, digest())
            assertEquals(revision, owner().readCommitted { KnowledgeSourceSelection(owner(), AgentKnowledgeSourceReference("\u6765\u6e90")).revision(it) })
            owner().readCommitted { db ->
                for ((table, count) in listOf("knowledge_primary_refs" to 10001L, "knowledge_chunks" to 0L, "knowledge_payloads" to 0L)) {
                    db.rawQuery("SELECT count(*) FROM $table", null).use { check(it.moveToFirst()); assertEquals(count, it.getLong(0)) }
                }
                db.rawQuery("SELECT sqlite_version()", null).use { check(it.moveToFirst()); println("KNOWLEDGE_PRIMARY_SCALE sqlite=${it.getString(0)}") }
                db.rawQuery("SELECT count(*) FROM knowledge_primary_partitions", null).use {
                    check(it.moveToFirst()); assertTrue(it.getLong(0) >= 4); println("KNOWLEDGE_PRIMARY_SCALE partitions=${it.getLong(0)} digest=$before verified=10001")
                }
            }
        } finally { store.close() }
    }
}

package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class KnowledgeNativeIndexDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val spec = KnowledgeVectorSpec("c".repeat(64), 2, 64)
    private val encoder = object : KnowledgeVectorEncoder {
        override val spec get() = this@KnowledgeNativeIndexDeviceTest.spec
        override fun tokenCount(text: String) = text.length + 2
        override fun embed(text: String) = if (text.startsWith("orchard")) floatArrayOf(1f, 0f) else floatArrayOf(0f, 1f)
        override fun close() = Unit
    }
    private fun isolated(block: (SQLiteAgentKnowledgeStore, AgentKnowledgeDatabase) -> Unit) {
        val name = "test-native-source-${UUID.randomUUID()}.db"
        val store = SQLiteAgentKnowledgeStore(context, name, "legacy-$name") { _, _ -> }
        val db = AgentKnowledgeDatabase.shared(context, name, "legacy-$name")
        val directory = db.nativeIndexDirectory(db.vectors(spec).modelKey)
        try { block(store, db) } finally {
            store.close(); context.deleteDatabase(name); directory.deleteRecursively()
            AgentEncryptedPreferences(context, "legacy-$name").clear()
        }
    }
    private fun item(id: String, content: String = "orchard") = AgentKnowledgeItem(id, AgentKnowledgeKind.NOTE, id, content)
    private fun finish(index: KnowledgeNativeIndex) { var slices = 0; while (!index.synchronize(1) {}) { check(++slices < 1000) } }

    @Test fun sourceFeedReplaysIncrementallyAndTtlStyleReopenDoesNotRebuildTheGraph() = isolated { store, db ->
        repeat(12) { store.upsert(item("source-$it")) }
        assertFalse(store.indexVectorChunks(encoder, 32).pending)
        var index = KnowledgeNativeIndex(db, spec, 1_000_000)
        try {
            assertFalse(index.synchronize(1) {})
            val checkpointNodes = index.physicalNodeCount()
            assertTrue(checkpointNodes in 2..3)
            index.close()
            index = KnowledgeNativeIndex(db, spec, 1_000_000)
            finish(index)
            assertEquals(13L, index.physicalNodeCount())
            assertEquals(12, index.search(floatArrayOf(1f, 0f)).size)
            repeat(3) {
                index.close(); index = KnowledgeNativeIndex(db, spec, 1_000_000)
                assertTrue(index.synchronize(1) {})
                assertEquals(13L, index.physicalNodeCount())
            }
        } finally { index.close() }
    }

    @Test fun obsoleteReadyEventsAndRemovalAreResolvedAgainstTheCurrentSource() = isolated { store, db ->
        store.upsert(item("fruit")); assertFalse(store.indexVectorChunks(encoder, 8).pending)
        store.upsert(item("fruit", "harbor")); assertFalse(store.indexVectorChunks(encoder, 8).pending)
        val index = KnowledgeNativeIndex(db, spec, 1_000_000)
        try {
            finish(index)
            assertEquals(2L, index.physicalNodeCount())
            assertTrue(index.search(floatArrayOf(1f, 0f)).all { it.similarity < 0.35 })
            assertEquals(1, store.delete("fruit"))
            finish(index)
            assertTrue(index.search(floatArrayOf(0f, 1f)).isEmpty())
        } finally { index.close() }
    }

    @Test fun realKeystoreWrappedIndexCanReopenWithoutPlaintextVectorOrKeyFiles() = isolated { store, db ->
        store.upsert(item("fruit")); assertFalse(store.indexVectorChunks(encoder, 8).pending)
        var index = KnowledgeNativeIndex(db, spec, 1_000_000)
        try {
            finish(index); assertEquals(1, index.search(floatArrayOf(1f, 0f)).size)
            val directory = db.nativeIndexDirectory(db.vectors(spec).modelKey)
            assertEquals(1, directory.listFiles().orEmpty().count { it.name.endsWith(".key") && it.length() == 61L })
            directory.walkTopDown().filter { it.isFile }.forEach { file ->
                assertFalse(file.readBytes().toString(Charsets.ISO_8859_1).contains("orchard"))
            }
            index.close(); index = KnowledgeNativeIndex(db, spec, 1_000_000)
            assertTrue(index.synchronize(1) {})
            assertEquals(1, index.search(floatArrayOf(1f, 0f)).size)
        } finally { index.close() }
    }
}

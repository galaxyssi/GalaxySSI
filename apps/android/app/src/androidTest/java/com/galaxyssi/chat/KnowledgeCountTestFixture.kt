package com.galaxyssi.chat

import androidx.test.platform.app.InstrumentationRegistry
import java.io.Closeable
import java.util.UUID
import org.junit.Assert.*

internal class KnowledgeCountTestFixture(
    val spec: KnowledgeVectorSpec = KnowledgeVectorSpec("a".repeat(64), 4, 32),
    val name: String = "test-counts-${UUID.randomUUID()}.db"
) : Closeable {
    val context = InstrumentationRegistry.getInstrumentation().targetContext
    val legacy = "legacy-$name"
    var db = AgentKnowledgeDatabase.shared(context, name, legacy)
    var store = SQLiteAgentKnowledgeStore(context, name, legacy) { _, _ -> }
    val ledger get() = db.vectors(spec)
    val encoder = object : KnowledgeVectorEncoder {
        override val spec = this@KnowledgeCountTestFixture.spec
        override fun tokenCount(text: String) = text.length + 2
        override fun embed(text: String) = FloatArray(spec.dimensions) { if (it == 0) 1f else 0f }
        override fun close() = Unit
    }
    fun item(id: String, text: String = "\u8bb0\u5fc6\u7edf\u8ba1\u6d4b\u8bd5") =
        AgentKnowledgeItem(id, AgentKnowledgeKind.NOTE, id, text, source = "counts")
    fun seed(count: Int) = store.replaceSource("counts", (1..count).map { item("source-$it") })
    fun index() {
        val indexer = KnowledgeVectorIndexer(ledger, encoder)
        repeat(2000) { if (!indexer.runBatch(32).pending) return }
        error("Isolated index did not settle")
    }
    fun counts() = db.access { KnowledgeCounts.snapshot(it, ledger.modelKey) }
    fun actual(table: String, model: String = ledger.modelKey): Long = db.access { sql ->
        sql.rawQuery("SELECT count(*) FROM $table WHERE model_key=?", arrayOf(model)).use { check(it.moveToFirst()); it.getLong(0) }
    }
    fun page(kind: KnowledgeCountSchema.Kind, limit: Int = 64) = db.transaction { KnowledgeCounts.advance(it, kind, limit) }
    fun finishCounts() {
        repeat(2000) {
            KnowledgeCountSchema.Kind.entries.forEach { kind -> page(kind) }
            if (!db.access(KnowledgeCounts::pending)) return
        }
        error("Isolated counts did not settle")
    }
    fun verify() {
        val measured = counts()
        assertTrue(measured.complete)
        assertEquals(actual("knowledge_vectors"), measured.chunks)
        assertEquals(actual("knowledge_vector_queue"), measured.pending)
    }
    fun downgrade() {
        db.transaction { KnowledgeCountFixtureSchema.remove(it); it.execSQL("PRAGMA user_version=6") }
        reopen()
    }
    fun reopen() {
        store.close(); AgentKnowledgeDatabase.release(context, name)
        db = AgentKnowledgeDatabase.shared(context, name, legacy)
        store = SQLiteAgentKnowledgeStore(context, name, legacy) { _, _ -> }
    }
    override fun close() {
        store.close(); AgentKnowledgeDatabase.release(context, name)
        context.deleteDatabase(name); AgentEncryptedPreferences(context, legacy).clear()
    }
}

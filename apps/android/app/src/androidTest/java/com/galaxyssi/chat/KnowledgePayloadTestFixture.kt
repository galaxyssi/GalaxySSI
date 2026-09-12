package com.galaxyssi.chat

import android.content.ContentValues
import androidx.test.platform.app.InstrumentationRegistry
import java.io.Closeable
import java.io.File
import java.util.UUID

internal class KnowledgePayloadTestFixture : Closeable {
    val context = InstrumentationRegistry.getInstrumentation().targetContext
    val name = "test-knowledge-payload-${UUID.randomUUID()}.db"
    private val legacy = "legacy-$name"
    var store = open(); private set
    val db get() = AgentKnowledgeDatabase.shared(context, name, legacy)
    val root get() = File(context.getDatabasePath(name).absolutePath + ".payloads")
    private fun open() = SQLiteAgentKnowledgeStore(context, name, legacy) { _, _ -> }
    fun reopen() { store.close(); store = open() }
    fun item(i: Int, content: String = "\u79c1\u5bc6\u77e5\u8bc6\ud83d\ude80".repeat(3000)) = AgentKnowledgeItem(
        id = "payload-$i", kind = AgentKnowledgeKind.NOTE, title = "\u77e5\u8bc6-$i", content = content,
        summary = "\u6458\u8981-$i", source = "\u5206\u6bb5\u6d4b\u8bd5", updatedAtMillis = i.toLong())
    fun count(table: String): Long {
        require(table in setOf("knowledge_payloads", "knowledge_chunks", "knowledge_items", "knowledge_fts"))
        return db.access { sql -> sql.rawQuery("SELECT count(*) FROM $table", null).use { check(it.moveToFirst()); it.getLong(0) } }
    }
    fun checkpoint(): String = db.access { sql -> sql.rawQuery("SELECT after_item,all_rows,complete FROM knowledge_payload_migration", null).use {
        check(it.moveToFirst()); "${it.getString(0)}:${it.getLong(1)}:${it.getLong(2)}"
    } }
    fun makeLegacy(item: AgentKnowledgeItem) {
        store.upsert(item)
        val key = db.key("id", item.id)
        db.transaction { sql ->
            val header = requireNotNull(db.readHeader(sql, key))
            val encoded = db.readEncoded(sql, key, header)
            sql.delete("knowledge_payloads", "item_key=?", arrayOf(key))
            sql.delete("knowledge_chunks", "item_key=?", arrayOf(key))
            sql.insertOrThrow("knowledge_chunks", null, ContentValues().apply {
                put("item_key", key); put("ordinal", 0)
                put("ciphertext", AgentStorageCipher.encrypt(encoded, "$name:$key:0".toByteArray()))
            })
            sql.update("knowledge_items", ContentValues().apply {
                put("header", AgentStorageCipher.encrypt(header.put("chunks", 1).toString(), "$name:$key:header".toByteArray()))
            }, "item_key=?", arrayOf(key))
        }
    }
    override fun close() {
        store.close()
        // Keep this isolated fixture for recovery follow-ups; never touch production or prior scale data.
        println("KNOWLEDGE_PAYLOAD_FIXTURE $name")
    }
}

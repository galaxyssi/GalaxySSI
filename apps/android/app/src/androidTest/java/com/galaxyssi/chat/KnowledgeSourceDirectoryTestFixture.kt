package com.galaxyssi.chat

import android.content.ContentValues
import androidx.test.platform.app.InstrumentationRegistry
import java.io.Closeable
import java.util.UUID
import org.junit.Assert.*

/** Metadata-only fixture deliberately cannot decrypt bodies; separate integration cases use real sources. */
internal class KnowledgeSourceDirectoryTestFixture : Closeable {
    val context = InstrumentationRegistry.getInstrumentation().targetContext
    val name = "test-source-directory-${UUID.randomUUID()}.db"
    var db = open()
    init { db.execSQL("CREATE TABLE knowledge_items(item_key TEXT PRIMARY KEY,source_key TEXT NOT NULL,updated INTEGER NOT NULL)") }
    private fun open() = KnowledgeSqlite(context.getDatabasePath(name).absolutePath).also {
        it.execSQL("PRAGMA foreign_keys=ON"); it.execSQL("PRAGMA recursive_triggers=ON"); it.execSQL("PRAGMA journal_mode=WAL")
    }
    fun reopen() { db.close(); db = open() }
    fun key(id: Int) = id.toString(16).padStart(64, '0')
    fun put(id: Int, source: String = key(id), updated: Long = id.toLong()) = transaction {
        db.delete("knowledge_items", "item_key=?", arrayOf(key(id)))
        db.insertOrThrow("knowledge_items", null, ContentValues().apply {
            put("item_key", key(id)); put("source_key", source); put("updated", updated)
        })
    }
    fun create() = transaction { KnowledgeSourceDirectorySchema.create(db) }
    fun page(limit: Int = 64) = transaction { KnowledgeSourceDirectory.advance(db, limit) }
    fun finish() { while (!page()) Unit }
    fun state() = KnowledgeSourceDirectory.state(db)
    fun <T> transaction(block: () -> T): T {
        db.beginTransaction()
        try { return block().also { db.setTransactionSuccessful() } } finally { db.endTransaction() }
    }
    fun verify() {
        val state = state(); assertTrue(state.complete)
        val expected = db.rawQuery("SELECT CASE WHEN source_key='' THEN 'i:'||item_key ELSE 's:'||source_key END AS g," +
            "count(*),max(updated) FROM knowledge_items GROUP BY g ORDER BY g", null).use { c ->
            buildList { while(c.moveToNext()) add(Triple(c.getString(0),c.getLong(1),c.getLong(2))) }
        }
        val actual = db.rawQuery("SELECT group_key,members,~sort_updated FROM knowledge_source_directory ORDER BY group_key", null).use { c ->
            buildList { while(c.moveToNext()) add(Triple(c.getString(0),c.getLong(1),c.getLong(2))) }
        }
        assertEquals(expected, actual)
        assertEquals(expected.size.toLong(), state.groups)
        assertEquals(expected.sumOf { it.second }, state.items)
        assertEquals(expected.count { it.first.startsWith("s:") }.toLong(), state.namedGroups)
        db.rawQuery("PRAGMA foreign_key_check", null).use { assertFalse(it.moveToFirst()) }
    }
    override fun close() { db.close(); context.deleteDatabase(name) }
}

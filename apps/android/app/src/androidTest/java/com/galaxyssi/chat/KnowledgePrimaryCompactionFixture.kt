package com.galaxyssi.chat

import android.content.ContentValues
import androidx.test.platform.app.InstrumentationRegistry
import java.io.Closeable
import java.io.File
import java.util.UUID

internal class KnowledgePrimaryCompactionFixture(
    val name: String = "test-primary-compact-${UUID.randomUUID().toString().replace("-", "")}.db",
    records: Long = 64,
    schema: Boolean = true
) : Closeable {
    val context = InstrumentationRegistry.getInstrumentation().targetContext
    val file = context.getDatabasePath(name)
    val root = File(file.absolutePath + ".primary")
    val db = KnowledgeSqlite(file.absolutePath)
    val parts = KnowledgePrimaryPartitions(context, root, name, partitionRecords = records)
    init {
        db.execSQL("PRAGMA foreign_keys=ON"); db.execSQL("PRAGMA recursive_triggers=ON")
        db.execSQL("PRAGMA journal_mode=WAL"); db.execSQL("PRAGMA synchronous=FULL")
        val exists = db.rawQuery("SELECT 1 FROM sqlite_master WHERE name='knowledge_items'", null).use { it.moveToFirst() }
        if (!exists) {
            db.execSQL("CREATE TABLE knowledge_items(item_key TEXT PRIMARY KEY)")
            KnowledgePrimarySchema.create(db)
            if (schema) KnowledgePrimaryCompactionSchema.create(db)
        }
    }
    fun key(i: Int) = "00" + i.toString(16).padStart(62, '0')
    fun put(i: Int, value: String = "\u8bb0\u5fc6-$i") {
        db.delete("knowledge_items", "item_key=?", arrayOf(key(i)))
        db.insertOrThrow("knowledge_items", null, ContentValues().apply { put("item_key", key(i)) })
        parts.append(db, key(i), value)
    }
    fun transaction(commit: Boolean = true, block: () -> Unit) {
        db.beginTransaction(); parts.begin()
        try { block(); if (commit) { parts.prepareCommit(); db.setTransactionSuccessful() } }
        finally { try { db.endTransaction() } finally { parts.end() } }
    }
    fun seed() = transaction {
        repeat(64) { put(it) }
        repeat(48) { db.delete("knowledge_items", "item_key=?", arrayOf(key(it))) }
    }
    fun source(i: Int = 63) = db.rawQuery("SELECT partition_key FROM knowledge_primary_refs WHERE item_key=?", arrayOf(key(i))).use {
        check(it.moveToFirst()); it.getString(0)
    }
    fun number(sql: String) = db.rawQuery(sql, null).use { check(it.moveToFirst()); it.getLong(0) }
    fun drain(): Int {
        var moved = 0
        repeat(100) {
            val page = KnowledgePrimaryReclaim.advance(db, parts) { }
            check(page.movedRecords <= 8); moved += page.movedRecords
            if (page.complete) return moved
        }
        error("Fixture compaction did not converge")
    }
    fun verify() { for (i in 48..63) check(parts.read(db, key(i)) == "\u8bb0\u5fc6-$i") }
    override fun close() { parts.close(); db.close(); println("KNOWLEDGE_COMPACTION_FIXTURE $name") }
}

package com.galaxyssi.chat

import android.content.ContentValues
import android.os.Looper

class KnowledgeSourceDirectoryNotReady internal constructor(val processed: Long) :
    IllegalStateException("Knowledge source index is being prepared")

internal data class KnowledgeSourceDirectoryState(val after: String, val complete: Boolean,
    val items: Long, val groups: Long, val namedGroups: Long) {
    fun requireReady() { if (!complete) throw KnowledgeSourceDirectoryNotReady(items) }
}

/** Restartable keyset enrollment. Live mutations maintain the same directory in their transaction. */
internal object KnowledgeSourceDirectory {
    const val PAGE_SIZE = 64
    private val HASH = Regex("[a-f0-9]{64}")
    private data class Row(val key: String, val source: String, val updated: Long)
    fun state(db: KnowledgeSqlite): KnowledgeSourceDirectoryState = db.rawQuery(
        "SELECT CASE WHEN length(after_item)<=64 THEN after_item ELSE 'invalid' END,complete,items,groups,named_groups " +
            "FROM knowledge_source_state WHERE id=1", null).use {
        check(it.moveToFirst()) { "Source directory checkpoint is missing" }
        val result = KnowledgeSourceDirectoryState(it.getString(0), it.getLong(1) == 1L, it.getLong(2), it.getLong(3), it.getLong(4))
        check((result.after.isEmpty() || result.after.matches(HASH)) && it.getLong(1) in 0L..1L &&
            result.items >= result.groups && result.groups >= result.namedGroups && result.namedGroups >= 0) {
            "Invalid source directory checkpoint"
        }
        result
    }
    const val PAGE_SQL = "SELECT item_key,source_key,updated FROM knowledge_items WHERE item_key>? ORDER BY item_key LIMIT ?"
    const val BROWSE_SQL = "SELECT group_key,~sort_updated,members,head FROM knowledge_source_directory " +
        "WHERE (sort_updated,group_key)>(?,?) ORDER BY sort_updated,group_key LIMIT ?"
    fun advance(db: KnowledgeSqlite, limit: Int = PAGE_SIZE): Boolean {
        check(Looper.myLooper() != Looper.getMainLooper()) { "Source enrollment requires a worker thread" }
        require(limit in 1..256)
        val current = state(db)
        if (current.complete) return true
        val rows = db.rawQuery(PAGE_SQL, arrayOf(current.after, (limit + 1).toString())).use { c ->
            buildList { while (c.moveToNext()) {
                val row = Row(c.getString(0), c.getString(1), c.getLong(2))
                check(row.key.matches(HASH) && (row.source.isEmpty() || row.source.matches(HASH))) { "Invalid source directory identity" }
                add(row)
            } }
        }
        val page = rows.take(limit)
        for (row in page) {
            val group = if (row.source.isEmpty()) "i:${row.key}" else "s:${row.source}"
            db.rawQuery("INSERT INTO knowledge_source_members(item_key,group_key,sort_updated) VALUES(?,?,?) " +
                "ON CONFLICT(item_key) DO NOTHING", arrayOf(row.key, group, row.updated.inv().toString())).use { it.moveToNext() }
            db.rawQuery("SELECT group_key,sort_updated FROM knowledge_source_members WHERE item_key=?", arrayOf(row.key)).use {
                check(it.moveToFirst() && it.getString(0) == group && it.getLong(1) == row.updated.inv()) {
                    "Source directory membership mismatch"
                }
            }
        }
        val complete = rows.size <= limit
        db.update("knowledge_source_state", ContentValues().apply {
            put("after_item", page.lastOrNull()?.key ?: current.after); put("complete", if (complete) 1 else 0)
        }, "id=1", emptyArray())
        db.rawQuery("SELECT changes()", null).use { check(it.moveToFirst() && it.getLong(0) == 1L) { "Source directory checkpoint was lost" } }
        return complete
    }
}

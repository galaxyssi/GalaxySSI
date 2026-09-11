package com.galaxyssi.chat

import android.content.ContentValues
import android.os.Looper

internal data class KnowledgeCountSnapshot(val chunks: Long, val pending: Long, val complete: Boolean)

/** Point reads with a restartable, bounded legacy sweep over existing primary-key indexes. */
internal object KnowledgeCounts {
    const val PAGE_SIZE = 64
    private val HASH = Regex("[a-f0-9]{64}")
    internal data class Position(val item: String, val model: String, val ordinal: Long, val complete: Boolean)
    private data class Row(val position: Position, val tracked: Boolean)

    fun snapshot(db: KnowledgeSqlite, model: String): KnowledgeCountSnapshot {
        val result = db.rawQuery("SELECT chunks,pending,legacy FROM knowledge_vector_counts WHERE model_key=?",
            arrayOf(model)).use {
            if (!it.moveToFirst()) null else {
                check(it.getLong(0) >= 0 && it.getLong(1) >= 0 && it.getLong(2) in 0L..1L)
                KnowledgeCountSnapshot(it.getLong(0), it.getLong(1), it.getLong(2) == 0L)
            }
        }
        if (result == null) {
            check(!db.rawQuery("SELECT 1 FROM knowledge_vector_models WHERE model_key=?", arrayOf(model)).use { it.moveToFirst() }) {
                "Registered model has no memory counts"
            }
            return KnowledgeCountSnapshot(0, 0, true)
        }
        return if (result.complete) result else result.copy(complete = !pending(db))
    }

    fun pending(db: KnowledgeSqlite): Boolean = KnowledgeCountSchema.Kind.entries.map { position(db, it).complete }.any { !it }

    internal fun position(db: KnowledgeSqlite, kind: KnowledgeCountSchema.Kind): Position = db.rawQuery(
        "SELECT CASE WHEN length(after_item)<=64 THEN after_item ELSE 'invalid' END," +
            "CASE WHEN length(after_model)<=64 THEN after_model ELSE 'invalid' END,after_ordinal,complete " +
            "FROM knowledge_count_scan WHERE kind=?", arrayOf(kind.name)).use {
        check(it.moveToFirst()) { "Memory count checkpoint is missing" }
        val result = Position(it.getString(0), it.getString(1), it.getLong(2), it.getLong(3) == 1L)
        check((result.item.isEmpty() && result.model.isEmpty() && result.ordinal == -1L) ||
            (result.item.matches(HASH) && result.model.matches(HASH) && result.ordinal >= 0)) { "Invalid memory count cursor" }
        check(it.getLong(3) in 0L..1L)
        result
    }

    internal fun pageSql(kind: KnowledgeCountSchema.Kind): String {
        val keys = kind.keys.joinToString(",")
        // Column affinity coerces bound values; CAST here prevents a seek on the ordinal key.
        val parameters = kind.keys.joinToString(",") { "?" }
        return "SELECT CASE WHEN length(item_key)=64 THEN item_key ELSE '' END," +
            "CASE WHEN length(model_key)=64 THEN model_key ELSE '' END," +
            (if (kind == KnowledgeCountSchema.Kind.VECTOR) "ordinal" else "0") +
            ",CASE WHEN typeof(count_tracked)='integer' THEN count_tracked ELSE -1 END" +
            " FROM ${kind.table} WHERE ($keys)>($parameters) ORDER BY $keys LIMIT ?"
    }

    /** Caller owns the transaction. Already counted rows still consume the page budget. */
    fun advance(db: KnowledgeSqlite, kind: KnowledgeCountSchema.Kind, limit: Int = PAGE_SIZE): Boolean {
        check(Looper.myLooper() != Looper.getMainLooper()) { "Memory count backfill requires a worker thread" }
        require(limit in 1..256)
        val current = position(db, kind)
        if (current.complete) return true
        val keys = kind.keys.map { when (it) {
            "item_key" -> current.item
            "model_key" -> current.model
            else -> current.ordinal.toString()
        } }
        val rows = db.rawQuery(pageSql(kind), (keys + (limit + 1).toString()).toTypedArray()).use { cursor ->
            buildList { while (cursor.moveToNext()) {
                val row = Position(cursor.getString(0), cursor.getString(1), cursor.getLong(2), false)
                check(row.item.matches(HASH) && row.model.matches(HASH) && row.ordinal >= 0) { "Invalid memory count key" }
                check(cursor.getLong(3) in 0L..1L) { "Invalid memory count tracking state" }
                add(Row(row, cursor.getLong(3) == 1L))
            } }
        }
        val page = rows.take(limit)
        for (entry in page) {
            if (entry.tracked) continue
            val row = entry.position
            val args = kind.keys.map { when (it) { "item_key" -> row.item; "model_key" -> row.model; else -> row.ordinal.toString() } }
            db.update(kind.table, ContentValues().apply { put("count_tracked", 1) },
                kind.keys.joinToString(" AND ") { "$it=?" } + " AND count_tracked=0", args.toTypedArray())
            db.rawQuery("SELECT changes()", null).use {
                check(it.moveToFirst() && it.getLong(0) == 1L) { "Memory count tracking update was lost" }
            }
        }
        val last = page.lastOrNull()?.position ?: current
        val complete = rows.size <= limit
        db.update("knowledge_count_scan", ContentValues().apply {
            put("after_item", last.item); put("after_model", last.model); put("after_ordinal", last.ordinal)
            put("complete", if (complete) 1 else 0)
        }, "kind=?", arrayOf(kind.name))
        db.rawQuery("SELECT changes()", null).use { check(it.moveToFirst() && it.getLong(0) == 1L) { "Memory count checkpoint was lost" } }
        return complete
    }
}

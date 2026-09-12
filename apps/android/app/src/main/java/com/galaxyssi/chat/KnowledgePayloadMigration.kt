package com.galaxyssi.chat

import android.content.ContentValues

/** Physical-only migration: do not rewrite headers, source revisions, FTS or vector replay state. */
internal object KnowledgePayloadMigration {
    data class Page(val visited: Int, val moved: Int, val complete: Boolean)
    fun advance(owner: AgentKnowledgeDatabase, db: KnowledgeSqlite, limit: Int = 4,
        checkActive: () -> Unit = {}): Page {
        require(limit in 1..32)
        val state = db.rawQuery("SELECT after_item,all_rows,complete FROM knowledge_payload_migration WHERE id=1", null).use {
            check(it.moveToFirst()) { "Knowledge payload migration checkpoint missing" }
            Triple(it.getString(0), it.getLong(1), it.getLong(2))
        }
        check((state.first.isEmpty() || state.first.matches(Regex("[a-f0-9]{64}"))) && state.second in 0..1 && state.third in 0..1)
        val allRows = state.second == 1L || KnowledgeSourceDirectory.state(db).items >= KnowledgePayloadSegments.LARGE_STORE_ROWS
        val upgrade = allRows && state.second == 0L
        if (!upgrade && state.third == 1L) return Page(0, 0, true)
        val after = if (upgrade) "" else state.first
        val keys = db.rawQuery("SELECT item_key FROM knowledge_items WHERE item_key>? ORDER BY item_key LIMIT ?",
            arrayOf(after, (limit + 1).toString())).use { c -> buildList { while (c.moveToNext()) add(c.getString(0)) } }
        val page = keys.take(limit)
        var moved = 0
        var visited = 0
        for (key in page) {
            try { checkActive() } catch (yield: MemoryMaintenanceYield) {
                if (visited == 0) throw yield
                break
            }
            visited++
            val external = db.rawQuery("SELECT 1 FROM knowledge_payloads WHERE item_key=?", arrayOf(key)).use { it.moveToFirst() }
            if (external) continue
            val header = requireNotNull(owner.readHeader(db, key))
            val encoded = owner.readEncoded(db, key, header)
            if (!allRows && encoded.length < KnowledgePayloadSegments.INLINE_CHARS) continue
            owner.payloads.append(db, key, encoded)
            db.delete("knowledge_chunks", "item_key=?", arrayOf(key))
            moved++
        }
        // Commit completed records at a time-slice boundary, even if one record was slow.
        val complete = keys.size <= limit && visited == page.size
        db.update("knowledge_payload_migration", ContentValues().apply {
            put("after_item", if (visited > 0) page[visited - 1] else after); put("all_rows", if (allRows) 1 else 0)
            put("complete", if (complete) 1 else 0)
        }, "id=1", emptyArray())
        db.rawQuery("SELECT changes()", null).use { check(it.moveToFirst() && it.getLong(0) == 1L) }
        return Page(visited, moved, complete)
    }
}

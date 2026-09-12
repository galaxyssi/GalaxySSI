package com.galaxyssi.chat

import android.content.ContentValues

/** Only physical ownership changes: headers, revisions, policies and index watermarks remain intact. */
internal object KnowledgePrimaryMigration {
    data class Page(val visited: Int, val moved: Int, val complete: Boolean)

    fun advance(owner: AgentKnowledgeDatabase, db: KnowledgeSqlite, limit: Int = 8,
        checkActive: () -> Unit = {}): Page {
        require(limit in 1..32)
        val state = db.rawQuery("SELECT after_item,complete FROM knowledge_primary_migration WHERE id=1", null).use {
            check(it.moveToFirst()); it.getString(0) to it.getInt(1)
        }
        require((state.first.isEmpty() || state.first.matches(Regex("[a-f0-9]{64}"))) && state.second in 0..1)
        if (state.second == 1) return Page(0, 0, true)
        val keys = db.rawQuery("SELECT item_key FROM knowledge_items WHERE item_key>? ORDER BY item_key LIMIT ?",
            arrayOf(state.first, (limit + 1).toString())).use { cursor -> buildList {
                while (cursor.moveToNext()) add(cursor.getString(0))
            } }
        var visited = 0
        var moved = 0
        var after = state.first
        for (key in keys.take(limit)) {
            try { checkActive() } catch (yield: MemoryMaintenanceYield) { if (visited == 0) throw yield else break }
            val present = db.rawQuery("SELECT 1 FROM knowledge_primary_refs WHERE item_key=?", arrayOf(key)).use { it.moveToFirst() }
            if (!present) {
                val header = requireNotNull(owner.readHeader(db, key))
                val encoded = owner.readEncoded(db, key, header)
                owner.primary.append(db, key, encoded)
                // Verify staged frames before publishing the catalog and deleting legacy copies.
                check(owner.primary.read(db, key) == encoded) { "Primary migration verification failed" }
                db.delete("knowledge_chunks", "item_key=?", arrayOf(key))
                db.delete("knowledge_payloads", "item_key=?", arrayOf(key))
                moved++
            }
            visited++; after = key
        }
        val complete = keys.size <= limit && visited == keys.size
        db.update("knowledge_primary_migration", ContentValues().apply {
            put("after_item", after); put("complete", if (complete) 1 else 0)
        }, "id=1", emptyArray())
        return Page(visited, moved, complete)
    }
}

package com.galaxyssi.chat

import android.content.ContentValues

internal object AgentKnowledgeFtsIndex {
    fun create(db: KnowledgeSqlite) {
        db.execSQL("CREATE VIRTUAL TABLE knowledge_fts USING fts5(title,summary,body,tokenize='ascii')")
        db.execSQL("CREATE TABLE knowledge_fts_rows(rowid INTEGER PRIMARY KEY AUTOINCREMENT, " +
            "item_key TEXT UNIQUE NOT NULL REFERENCES knowledge_items(item_key) ON DELETE CASCADE)")
        db.execSQL("CREATE TABLE knowledge_fts_pending(item_key TEXT PRIMARY KEY REFERENCES knowledge_items(item_key) ON DELETE CASCADE)")
        db.execSQL("CREATE TRIGGER knowledge_fts_delete BEFORE DELETE ON knowledge_items BEGIN " +
            "DELETE FROM knowledge_fts WHERE rowid IN (SELECT rowid FROM knowledge_fts_rows WHERE item_key=old.item_key); END")
    }

    fun put(db: KnowledgeSqlite, id: String, item: AgentKnowledgeItem, tokens: AgentKnowledgeSearchTokens) {
        fun rowId(): Long? = db.rawQuery("SELECT rowid FROM knowledge_fts_rows WHERE item_key=?", arrayOf(id)).use {
            if (it.moveToFirst()) it.getLong(0) else null
        }
        val row = rowId() ?: run {
            db.insertOrThrow("knowledge_fts_rows", null, ContentValues().apply { put("item_key", id) })
            requireNotNull(rowId())
        }
        db.delete("knowledge_fts", "rowid=?", arrayOf(row.toString()))
        db.insertOrThrow("knowledge_fts", null, ContentValues().apply {
            put("rowid", row)
            put("title", tokens.encode(item.title + " " + item.tags.joinToString(" ")))
            put("summary", tokens.encode(item.summary))
            put("body", tokens.encode(item.content))
        })
        db.delete("knowledge_fts_pending", "item_key=?", arrayOf(id))
    }

    fun search(db: KnowledgeSqlite, query: String, limit: Int, tokens: AgentKnowledgeSearchTokens): Set<String> {
        val match = tokens.query(query)
        if (match.isEmpty() || limit <= 0) return emptySet()
        return db.rawQuery("SELECT r.item_key FROM knowledge_fts JOIN knowledge_fts_rows r ON r.rowid=knowledge_fts.rowid " +
            "WHERE knowledge_fts MATCH ? ORDER BY bm25(knowledge_fts,5.0,2.0,1.0),knowledge_fts.rowid LIMIT ?",
            arrayOf(match, limit.toString())).use {
            buildSet { while (it.moveToNext()) add(it.getString(0)) }
        }
    }

    fun pending(db: KnowledgeSqlite, limit: Int, after: String = ""): List<String> =
        db.rawQuery("SELECT item_key FROM knowledge_fts_pending WHERE item_key>? ORDER BY item_key LIMIT ?",
            arrayOf(after, limit.toString())).use { buildList { while (it.moveToNext()) add(it.getString(0)) } }
}

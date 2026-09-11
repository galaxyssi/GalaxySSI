package com.galaxyssi.chat

import android.content.ContentValues

/** Restartable discovery of pre-existing sources. Cursor and queue changes commit together. */
internal object KnowledgeVectorEnrollment {
    const val PAGE_SIZE = 64
    const val KEY_PAGE_SQL = "SELECT CASE WHEN length(item_key)=64 THEN item_key ELSE '' END FROM knowledge_items " +
        "WHERE item_key>? ORDER BY item_key LIMIT ?"
    private val HASH = Regex("[a-f0-9]{64}")
    data class State(val after: String, val complete: Boolean)

    fun create(db: KnowledgeSqlite) {
        db.execSQL("CREATE TABLE knowledge_vector_enrollment (model_key TEXT PRIMARY KEY " +
            "REFERENCES knowledge_vector_models(model_key) ON DELETE CASCADE," +
            "after_key TEXT NOT NULL DEFAULT '',complete INTEGER NOT NULL DEFAULT 0 CHECK(complete IN (0,1)))")
        // Older registrations filled the entire queue atomically. Do not scan their sources again.
        db.execSQL("INSERT INTO knowledge_vector_enrollment(model_key,complete) SELECT model_key,1 FROM knowledge_vector_models")
        db.execSQL("CREATE TRIGGER knowledge_vector_enrollment_model AFTER INSERT ON knowledge_vector_models BEGIN " +
            "INSERT INTO knowledge_vector_enrollment(model_key) VALUES(NEW.model_key); END")
    }

    fun state(db: KnowledgeSqlite, modelKey: String): State = db.rawQuery(
        "SELECT CASE WHEN length(after_key)<=64 THEN after_key ELSE 'invalid' END,complete " +
            "FROM knowledge_vector_enrollment WHERE model_key=?", arrayOf(modelKey)).use {
        check(it.moveToFirst()) { "Vector source enrollment state is missing" }
        val after = it.getString(0)
        check(after.isEmpty() || after.matches(HASH)) { "Invalid vector source enrollment cursor" }
        check(it.getLong(1) in 0L..1L) { "Invalid vector source enrollment completion" }
        State(after, it.getLong(1) == 1L)
    }

    /** Caller owns the source transaction. LIMIT precedes completed-document filtering. */
    fun refill(db: KnowledgeSqlite, modelKey: String, limit: Int = PAGE_SIZE): State {
        require(limit in 1..256)
        val current = state(db, modelKey)
        if (current.complete) return current
        val keys = db.rawQuery(KEY_PAGE_SQL,
            arrayOf(current.after, (limit + 1).toString())).use { cursor ->
            buildList { while (cursor.moveToNext()) add(cursor.getString(0).also {
                check(it.matches(HASH)) { "Invalid vector source key" }
            }) }
        }
        val page = keys.take(limit)
        page.forEach { key ->
            // Live mutations may already have queued or completed this key before discovery reaches it.
            db.rawQuery("INSERT INTO knowledge_vector_queue(model_key,item_key) SELECT ?,? WHERE NOT EXISTS(" +
                "SELECT 1 FROM knowledge_vector_docs WHERE model_key=? AND item_key=? AND complete=1) " +
                "ON CONFLICT(model_key,item_key) DO NOTHING", arrayOf(modelKey, key, modelKey, key)).use { it.moveToNext() }
        }
        val next = State(page.lastOrNull() ?: current.after, keys.size <= limit)
        db.update("knowledge_vector_enrollment", ContentValues().apply {
            put("after_key", next.after); put("complete", if (next.complete) 1 else 0)
        }, "model_key=?", arrayOf(modelKey))
        db.rawQuery("SELECT changes()", null).use {
            check(it.moveToFirst() && it.getLong(0) == 1L) { "Vector source enrollment checkpoint was lost" }
        }
        return next
    }
}

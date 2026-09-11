package com.galaxyssi.chat

import android.content.ContentValues
import android.database.sqlite.SQLiteDatabase
import org.json.JSONObject
import java.util.UUID

internal class AgentMemoryRecallIndex(internal val database: AgentEncryptedDatabase) {
    internal data class State(val json: JSONObject) {
        val generation: String get() = json.getString("generation")
        val ready: Boolean get() = json.getBoolean("ready")
        val cursor: String get() = json.getString("cursor")
    }

    fun observer(): (SQLiteDatabase, String, String?) -> Unit {
        val sourceRevision = sourceRevision()
        var current: State? = null
        return observer@{ sql, key, raw ->
            if (!key.startsWith(AgentPersonalMemoryRows.PREFIX) && key != AgentPersonalMemoryRows.META) return@observer
            val state = current ?: run {
                var initial = state(sql)
                if (initial.json.optString("source_revision") != sourceRevision) {
                    database.remove(MARKER)
                    initial = state(sql)
                }
                initial.also { current = it }
            }
            if (key == AgentPersonalMemoryRows.META) {
                // Bulk replacement removes obsolete rows after writing source metadata.
                // Validate counts only after the entire transaction has committed.
                if (raw != null) {
                    state.json.put("source_revision", AgentMemoryRecallRevision.content(JSONObject(raw)))
                    database.writeString(MARKER, state.json.toString())
                }
            } else if (raw == null) sql.delete(DOCS, "row_key=?", arrayOf(key))
            else hasher(state).use { put(sql, key, raw, it) }
        }
    }

    internal fun state(sql: SQLiteDatabase): State {
        if (!database.contains(MARKER)) {
            create(sql)
            val generation = UUID.randomUUID().toString()
            val stamp = AgentMemoryRecallHasher(generation).use { it.token("key-check") }
            database.writeString(MARKER, JSONObject().put("version", 1).put("generation", generation)
                .put("cursor", "").put("ready", database.countKeys(AgentPersonalMemoryRows.PREFIX) == 0)
                .put("source_revision", sourceRevision())
                .put("key_stamp", stamp).toString())
        }
        return State(JSONObject(database.readString(MARKER, ""))).also {
            check(it.json.getInt("version") == 1 && (it.cursor.isEmpty() || it.cursor.startsWith(AgentPersonalMemoryRows.PREFIX))) {
                "Invalid memory recall index metadata"
            }
        }
    }

    private fun sourceRevision(): String = if (database.contains(AgentPersonalMemoryRows.META)) {
        AgentMemoryRecallRevision.content(JSONObject(database.readString(AgentPersonalMemoryRows.META, "")))
    } else ""

    internal fun hasher(state: State): AgentMemoryRecallHasher = AgentMemoryRecallHasher(state.generation).also {
        if (it.token("key-check") != state.json.getString("key_stamp")) {
            it.close(); error("Memory recall index key mismatch")
        }
    }

    internal fun count(sql: SQLiteDatabase): Long = sql.rawQuery("SELECT n FROM $COUNTS WHERE id=1", null)
        .use { check(it.moveToFirst()); it.getLong(0) }

    /** Commit the cursor with its rows; restarting a wrapper/process resumes the next keyset page. */
    internal fun backfillPage(expectedGeneration: String, limit: Int = 16): Boolean = synchronized(AgentMemoryStorage.lock) {
        require(limit in 1..128)
        database.indexedTransaction { sql ->
            if (!database.contains(MARKER)) return@indexedTransaction true
            val state = state(sql)
            if (state.generation != expectedGeneration || state.ready) return@indexedTransaction true
            check(state.json.getString("source_revision") == sourceRevision()) {
                "Memory recall backfill source revision changed"
            }
            val keys = database.keysAfter(AgentPersonalMemoryRows.PREFIX, state.cursor, limit)
            hasher(state).use { hash -> keys.forEach { put(sql, it, database.readString(it, ""), hash) } }
            if (keys.isNotEmpty()) state.json.put("cursor", keys.last())
            if (keys.size < limit) {
                check(count(sql) == JSONObject(database.readString(AgentPersonalMemoryRows.META, "")).getLong("count")) {
                    "Memory recall backfill count mismatch"
                }
                state.json.put("ready", true)
            }
            database.writeString(MARKER, state.json.toString())
            state.ready
        }
    }

    internal fun put(sql: SQLiteDatabase, key: String, raw: String, hash: AgentMemoryRecallHasher) {
        val record = JSONObject(raw)
        val item = AgentMemoryItemCodec.decode(record.getJSONObject("item")) ?: error("Invalid memory recall source")
        val position = record.getLong("position")
        check(position >= 0 && AgentPersonalMemoryRows.key(item.id) == key && item.value.isNotBlank())
        val signature = signature(item, hash)
        val previous = sql.rawQuery("SELECT id,signature FROM $DOCS WHERE row_key=?", arrayOf(key))
            .use { if (it.moveToFirst()) it.getLong(0) to it.getString(1) else null }
        if (previous?.second == signature) return
        val id = previous?.first ?: sql.insertOrThrow(DOCS, null, ContentValues().apply {
            put("row_key", key); put("signature", signature)
        }).also { check(it > 0) }
        if (previous != null) {
            sql.delete(POSTINGS, "doc_id=?", arrayOf(id.toString()))
            sql.update(DOCS, ContentValues().apply { put("signature", signature) }, "id=?", arrayOf(id.toString()))
        }
        sql.compileStatement("INSERT OR IGNORE INTO $TERMS(token,n) VALUES(?,0)").use { insertTerm ->
            sql.compileStatement("SELECT id FROM $TERMS WHERE token=?").use { findTerm ->
                sql.compileStatement("INSERT OR IGNORE INTO $POSTINGS(term_id,doc_id) VALUES(?,?)").use { posting ->
                    AgentMemoryRecallTerms.document(item).forEach { term ->
                        val token = hash.token(term)
                        insertTerm.bindString(1, token); insertTerm.executeInsert()
                        findTerm.bindString(1, token)
                        posting.bindLong(1, findTerm.simpleQueryForLong()); posting.bindLong(2, id); posting.executeInsert()
                    }
                }
            }
        }
    }

    internal fun signature(item: AgentMemoryItem, hash: AgentMemoryRecallHasher): String = hash.token(
        "document:${item.key.length}:${item.key}:${item.value.length}:${item.value}:${item.status}:${item.privateMemory}")

    private fun create(sql: SQLiteDatabase) {
        sql.execSQL("CREATE TABLE IF NOT EXISTS $DOCS(id INTEGER PRIMARY KEY,row_key TEXT NOT NULL UNIQUE,signature TEXT NOT NULL)")
        sql.execSQL("CREATE TABLE IF NOT EXISTS $TERMS(id INTEGER PRIMARY KEY,token TEXT NOT NULL UNIQUE,n INTEGER NOT NULL CHECK(n>=0))")
        sql.execSQL("CREATE TABLE IF NOT EXISTS $POSTINGS(term_id INTEGER NOT NULL,doc_id INTEGER NOT NULL,PRIMARY KEY(term_id,doc_id)) WITHOUT ROWID")
        sql.execSQL("CREATE INDEX IF NOT EXISTS memory_recall_doc_terms ON $POSTINGS(doc_id,term_id)")
        sql.execSQL("CREATE TABLE IF NOT EXISTS $COUNTS(id INTEGER PRIMARY KEY CHECK(id=1),n INTEGER NOT NULL CHECK(n>=0))")
        sql.execSQL("INSERT OR IGNORE INTO $COUNTS VALUES(1,0)")
        sql.execSQL("CREATE TRIGGER IF NOT EXISTS memory_recall_doc_add AFTER INSERT ON $DOCS BEGIN UPDATE $COUNTS SET n=n+1 WHERE id=1; END")
        sql.execSQL("CREATE TRIGGER IF NOT EXISTS memory_recall_doc_remove AFTER DELETE ON $DOCS BEGIN " +
            "DELETE FROM $POSTINGS WHERE doc_id=OLD.id; UPDATE $COUNTS SET n=n-1 WHERE id=1; END")
        sql.execSQL("CREATE TRIGGER IF NOT EXISTS memory_recall_post_add AFTER INSERT ON $POSTINGS BEGIN UPDATE $TERMS SET n=n+1 WHERE id=NEW.term_id; END")
        sql.execSQL("CREATE TRIGGER IF NOT EXISTS memory_recall_post_remove AFTER DELETE ON $POSTINGS BEGIN " +
            "UPDATE $TERMS SET n=n-1 WHERE id=OLD.term_id; DELETE FROM $TERMS WHERE id=OLD.term_id AND n=0; END")
        sql.execSQL("CREATE TRIGGER IF NOT EXISTS memory_recall_clear AFTER DELETE ON encrypted_values WHEN OLD.storage_key='$MARKER' BEGIN " +
            "DELETE FROM $DOCS; DELETE FROM $POSTINGS; DELETE FROM $TERMS; UPDATE $COUNTS SET n=0 WHERE id=1; END")
        sql.delete(DOCS, null, null); sql.delete(POSTINGS, null, null); sql.delete(TERMS, null, null)
        sql.execSQL("UPDATE $COUNTS SET n=0 WHERE id=1")
    }

    companion object {
        const val MARKER = "personal-memory:recall:v1:metadata"
        const val DOCS = "personal_memory_recall_documents"
        const val TERMS = "personal_memory_recall_terms"
        const val POSTINGS = "personal_memory_recall_postings"
        const val COUNTS = "personal_memory_recall_count"
    }
}

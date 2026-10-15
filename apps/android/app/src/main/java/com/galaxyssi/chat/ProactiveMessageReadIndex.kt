package com.galaxyssi.chat

import android.database.sqlite.SQLiteDatabase
import org.json.JSONObject

/** Ordering metadata only; headlines and bodies remain in the encrypted message rows. */
internal class ProactiveMessageReadIndex(private val database: AgentEncryptedDatabase) {
    fun ready() = database.contains(READY)

    fun prepare(records: () -> Sequence<JSONObject>) {
        if (ready()) return
        database.indexedTransaction { db ->
            if (ready()) return@indexedTransaction
            db.execSQL("CREATE TABLE IF NOT EXISTS $TABLE (id TEXT PRIMARY KEY NOT NULL, " +
                "storage_key TEXT NOT NULL, delivered INTEGER NOT NULL, created INTEGER NOT NULL, " +
                "viewed INTEGER NOT NULL, digest TEXT NOT NULL)")
            db.execSQL("CREATE INDEX IF NOT EXISTS proactive_message_delivery ON $TABLE(delivered DESC,created DESC,id)")
            db.execSQL("CREATE INDEX IF NOT EXISTS proactive_message_digest ON $TABLE(digest)")
            db.execSQL("CREATE TRIGGER IF NOT EXISTS proactive_message_read_delete AFTER DELETE ON encrypted_values " +
                "BEGIN DELETE FROM $TABLE WHERE storage_key = OLD.storage_key; END")
            db.delete(TABLE, null, null)
            records().forEach { record -> update(db, ROW_PREFIX + record.getString("id"), record.toString()) }
            database.writeString(READY, "1")
        }
    }

    fun update(db: SQLiteDatabase, key: String, value: String?) {
        if (!key.startsWith(ROW_PREFIX)) return
        val id = key.removePrefix(ROW_PREFIX)
        if (value == null) { db.delete(TABLE, "id = ?", arrayOf(id)); return }
        val record = JSONObject(value)
        if (record.optString("status") != "DELIVERED") {
            db.delete(TABLE, "id = ?", arrayOf(id)); return
        }
        val digest = if (record.optString("target") == "GLOBAL_DIGEST") record.optString("delivery_group_id") else ""
        db.execSQL("INSERT OR REPLACE INTO $TABLE(id,storage_key,delivered,created,viewed,digest) VALUES(?,?,?,?,?,?)",
            arrayOf(id, key, record.optLong("delivered_at_millis"), record.optLong("created_at_millis"),
                record.optLong("viewed_at_millis"), digest))
    }

    fun firstKeys(state: AttentionReaderState, saved: Set<String>, pageSize: Int = 20): List<String> =
        database.indexedTransaction { db ->
            val restored = state.keys.takeIf { it.isNotEmpty() }?.let { keys ->
                val anchor = keys.indexOf(state.anchor).coerceAtLeast(0)
                keys.drop((anchor - 3).coerceAtLeast(0)).take(pageSize)
            }.orEmpty()
            val selected = when {
                restored.isNotEmpty() -> keysForItems(db, restored)
                state.filter == AttentionFeedFilter.SAVED -> keysForItems(db, saved.toList(), pageSize)
                else -> db.rawQuery("SELECT storage_key FROM $TABLE" +
                    (if (state.filter == AttentionFeedFilter.UNREAD) " WHERE viewed <= 0" else "") +
                    " ORDER BY delivered DESC,created DESC,id LIMIT ?", arrayOf(pageSize.toString())).use { cursor ->
                    buildList { while (cursor.moveToNext()) add(cursor.getString(0)) }
                }
            }
            // A digest must never be shown as a partial group.
            val keys = selected.toMutableSet()
            selected.forEach { key ->
                db.rawQuery("SELECT storage_key FROM $TABLE WHERE digest <> '' AND digest = " +
                    "(SELECT digest FROM $TABLE WHERE storage_key = ?)", arrayOf(key)).use { cursor ->
                    while (cursor.moveToNext()) keys += cursor.getString(0)
                }
            }
            keys.toList()
        }

    private fun keysForItems(db: SQLiteDatabase, items: List<String>, limit: Int = Int.MAX_VALUE): List<String> {
        val candidates = linkedMapOf<String, Pair<Long, Long>>()
        items.forEach { key ->
            val digest = key.startsWith("global-agent-digest:")
            val id = key.removePrefix(if (digest) "global-agent-digest:" else "global-agent:")
            db.rawQuery("SELECT storage_key,delivered,created FROM $TABLE WHERE ${if (digest) "digest" else "id"} = ?",
                arrayOf(id)).use { cursor ->
                while (cursor.moveToNext()) candidates[cursor.getString(0)] = cursor.getLong(1) to cursor.getLong(2)
            }
        }
        return candidates.entries.sortedWith(compareByDescending<Map.Entry<String, Pair<Long, Long>>> { it.value.first }
            .thenByDescending { it.value.second }.thenBy { it.key }).take(limit).map { it.key }
    }

    companion object {
        const val ROW_PREFIX = "proactive_message_row:"
        private const val TABLE = "proactive_message_read_index"
        private const val READY = "proactive_message_read_index_v1"
    }
}

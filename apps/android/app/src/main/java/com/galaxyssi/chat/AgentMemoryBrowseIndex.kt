package com.galaxyssi.chat

import android.content.ContentValues
import android.database.sqlite.SQLiteDatabase
import org.json.JSONObject
import java.util.UUID

/** Derived SQL metadata only. Bodies and raw identities remain in authenticated encrypted rows. */
internal class AgentMemoryBrowseIndex(private val database: AgentEncryptedDatabase) {
    fun observer(): (SQLiteDatabase, String, String?) -> Unit {
        var ready: Boolean? = null
        return { sql, key, raw ->
            if (key.startsWith(AgentPersonalMemoryRows.PREFIX)) {
                val enabled = ready ?: database.contains(MARKER).also { ready = it }
                if (enabled) put(sql, key, raw)
            }
        }
    }

    fun <T> read(block: (SQLiteDatabase, String, String) -> T): T = database.indexedTransaction { sql ->
        val metadata = JSONObject(database.readString(AgentPersonalMemoryRows.META, ""))
        if (!database.contains(MARKER)) {
            create(sql)
            var cursor = ""
            var count = 0L
            while (true) {
                val keys = database.keysAfter(AgentPersonalMemoryRows.PREFIX, cursor, 128)
                if (keys.isEmpty()) break
                val values = database.readStrings(keys)
                keys.forEach { key -> put(sql, key, values[key] ?: error("Cannot decrypt memory browse migration row")); count++ }
                cursor = keys.last()
            }
            check(count == metadata.getLong("count")) { "Memory browse migration count mismatch" }
            database.writeString(MARKER, JSONObject().put("version", 1).put("generation", UUID.randomUUID().toString())
                .put("key_stamp", AgentMemoryIndexKey.stamp()).toString())
        }
        val marker = JSONObject(database.readString(MARKER, ""))
        check(marker.getInt("version") == 1 && marker.getString("generation").isNotBlank() &&
            marker.getString("key_stamp") == AgentMemoryIndexKey.stamp()) { "Memory browse index or key is invalid" }
        sql.rawQuery("SELECT coalesce(sum(n),0),coalesce(sum(CASE WHEN state='ACTIVE' THEN n ELSE 0 END),0) FROM $COUNTS WHERE state!='GROUP'", null).use {
            check(it.moveToFirst() && it.getLong(0) == metadata.getLong("count") && it.getLong(1) == metadata.getLong("active_count")) {
                "Memory browse counts do not match source metadata"
            }
        }
        block(sql, marker.getString("generation"), metadata.getString("revision"))
    }

    private fun create(sql: SQLiteDatabase) {
        sql.execSQL("CREATE TABLE IF NOT EXISTS $ROWS (row_key TEXT PRIMARY KEY,state TEXT NOT NULL,kind TEXT NOT NULL," +
            "priority INTEGER NOT NULL,sort_time INTEGER NOT NULL,position INTEGER NOT NULL,private INTEGER NOT NULL," +
            "expiry INTEGER NOT NULL,group_key TEXT NOT NULL)")
        sql.execSQL("CREATE INDEX IF NOT EXISTS memory_browse_order ON $ROWS(state,priority,sort_time,position,row_key)")
        sql.execSQL("CREATE INDEX IF NOT EXISTS memory_browse_kind_order ON $ROWS(state,kind,priority,sort_time,position,row_key)")
        sql.execSQL("CREATE INDEX IF NOT EXISTS memory_browse_public_order ON $ROWS(state,private,priority,sort_time,position,row_key)")
        sql.execSQL("CREATE INDEX IF NOT EXISTS memory_browse_group ON $ROWS(group_key,sort_time,position,row_key)")
        sql.execSQL("CREATE TABLE IF NOT EXISTS $GROUPS (group_key TEXT PRIMARY KEY,kind TEXT NOT NULL,n INTEGER NOT NULL," +
            "priority INTEGER NOT NULL DEFAULT 0,sort_time INTEGER NOT NULL,position INTEGER NOT NULL,row_key TEXT NOT NULL)")
        sql.execSQL("CREATE INDEX IF NOT EXISTS memory_browse_group_order ON $GROUPS(priority,sort_time,position,row_key)")
        sql.execSQL("CREATE INDEX IF NOT EXISTS memory_browse_group_kind_order ON $GROUPS(kind,priority,sort_time,position,row_key)")
        sql.execSQL("CREATE TABLE IF NOT EXISTS $COUNTS (state TEXT NOT NULL,kind TEXT NOT NULL,n INTEGER NOT NULL CHECK(n>=0),PRIMARY KEY(state,kind))")
        sql.execSQL("CREATE TRIGGER IF NOT EXISTS memory_browse_clear AFTER DELETE ON encrypted_values " +
            "WHEN OLD.storage_key='$MARKER' BEGIN DELETE FROM $ROWS; DELETE FROM $GROUPS; DELETE FROM $COUNTS; END")
        // A missing marker permits reconstruction of derived indexes, never deletion of source rows.
        sql.delete(ROWS, null, null); sql.delete(GROUPS, null, null); sql.delete(COUNTS, null, null)
    }

    private fun put(sql: SQLiteDatabase, key: String, raw: String?) {
        val old = sql.rawQuery("SELECT state,kind,priority,sort_time,position,private,expiry,group_key FROM $ROWS WHERE row_key=?",
            arrayOf(key)).use { c -> if (!c.moveToFirst()) null else List(8) { c.getString(it) } }
        val next = raw?.let { value ->
            val row = JSONObject(value)
            val item = AgentMemoryItemCodec.decode(row.getJSONObject("item")) ?: error("Invalid memory browse payload")
            check(AgentPersonalMemoryRows.key(item.id) == key && row.getLong("position") >= 0)
            listOf(item.status.name, item.kind.name, AgentMemoryBrowseOrder.priority(item).toString(),
                AgentMemoryBrowseOrder.time(item.timestampMillis).toString(), row.getLong("position").toString(),
                (if (item.privateMemory) 1 else 0).toString(), item.expiresAtMillis.toString(), groupKey(item))
        }
        if (old == next) return
        if (old != null) adjust(sql, old[0], old[1], -1)
        sql.delete(ROWS, "row_key=?", arrayOf(key))
        if (next != null) {
            sql.insertOrThrow(ROWS, null, ContentValues().apply {
                put("row_key", key); put("state", next[0]); put("kind", next[1]); put("priority", next[2].toInt())
                put("sort_time", next[3].toLong()); put("position", next[4].toLong()); put("private", next[5].toInt())
                put("expiry", next[6].toLong()); put("group_key", next[7])
            })
            adjust(sql, next[0], next[1], 1)
        }
        listOfNotNull(old?.get(7), next?.get(7)).filter(String::isNotBlank).distinct().forEach { refreshGroup(sql, it) }
    }

    private fun adjust(sql: SQLiteDatabase, state: String, kind: String, delta: Long) {
        val previous = sql.rawQuery("SELECT n FROM $COUNTS WHERE state=? AND kind=?", arrayOf(state, kind))
            .use { if (it.moveToFirst()) it.getLong(0) else 0L }
        val next = Math.addExact(previous, delta)
        check(next >= 0) { "Memory browse count underflow" }
        sql.insertWithOnConflict(COUNTS, null, ContentValues().apply {
            put("state", state); put("kind", kind); put("n", next)
        }, SQLiteDatabase.CONFLICT_REPLACE).also { check(it != -1L) }
    }

    private fun refreshGroup(sql: SQLiteDatabase, key: String) {
        val previousKind = sql.rawQuery("SELECT kind FROM $GROUPS WHERE group_key=?", arrayOf(key))
            .use { if (it.moveToFirst()) it.getString(0) else null }
        val summary = sql.rawQuery("SELECT count(*),min(position) FROM $ROWS WHERE group_key=?", arrayOf(key))
            .use { check(it.moveToFirst()); it.getLong(0) to it.getLong(1) }
        val count = summary.first
        sql.delete(GROUPS, "group_key=?", arrayOf(key))
        if (previousKind != null) adjust(sql, "GROUP", previousKind, -1)
        if (count < 2) return
        sql.rawQuery("SELECT kind,sort_time,position,row_key FROM $ROWS WHERE group_key=? ORDER BY sort_time,position,row_key LIMIT 1",
            arrayOf(key)).use { row ->
            check(row.moveToFirst())
            sql.insertOrThrow(GROUPS, null, ContentValues().apply {
                put("group_key", key); put("kind", row.getString(0)); put("n", count); put("priority", 0)
                put("sort_time", row.getLong(1)); put("position", summary.second); put("row_key", row.getString(3))
            })
            adjust(sql, "GROUP", row.getString(0), 1)
        }
    }

    companion object {
        const val MARKER = "personal-memory:browse:v1:metadata"
        const val ROWS = "personal_memory_browse"
        const val GROUPS = "personal_memory_browse_groups"
        const val COUNTS = "personal_memory_browse_counts"
        fun groupKey(item: AgentMemoryItem): String = if (item.status != AgentMemoryStatus.CONFLICTED || item.conflictGroupId.isBlank()) ""
            else AgentMemoryIndexKey.token("memory-browse-group-v1:${AgentMemoryLookupIdentity.material(item.copy(value = ""))}:${item.conflictGroupId.length}:${item.conflictGroupId}")
    }
}

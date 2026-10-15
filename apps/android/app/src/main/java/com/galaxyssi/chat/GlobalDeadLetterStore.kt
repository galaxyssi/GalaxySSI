package com.galaxyssi.chat

import android.database.sqlite.SQLiteDatabase
import org.json.JSONArray
import org.json.JSONObject

/** Repository lock protects mutations. Only ordering/version metadata is indexed; payloads stay encrypted. */
internal class GlobalDeadLetterStore(private val database: AgentEncryptedDatabase) {
    private fun prepare() {
        if (database.contains(READY)) return
        database.indexedTransaction { db ->
            if (database.contains(READY)) return@indexedTransaction
            db.execSQL("CREATE TABLE IF NOT EXISTS $TABLE (id TEXT PRIMARY KEY NOT NULL, " +
                "quarantined INTEGER NOT NULL, version INTEGER NOT NULL, recovered INTEGER NOT NULL)")
            db.execSQL("CREATE TRIGGER IF NOT EXISTS global_dead_letter_delete AFTER DELETE ON encrypted_values " +
                "WHEN substr(OLD.storage_key,1,${PREFIX.length}) = '$PREFIX' " +
                "BEGIN DELETE FROM $TABLE WHERE id = substr(OLD.storage_key,${PREFIX.length + 1}); END")
            val raw = if (database.contains(LEGACY)) database.readString(LEGACY, "") else "[]"
            check(raw.isNotEmpty()) { "Unreadable legacy dead letters" }
            val legacy = JSONArray(raw)
            database.mutateStreaming(sequence {
                for (i in 0 until legacy.length()) {
                    val record = legacy.getJSONObject(i)
                    yield(PREFIX + identity(record) to record.toString())
                }
                yield(READY to "1")
            }, onMutation = ::index, removals = { sequenceOf(LEGACY) })
        }
    }

    fun ids(): Set<String> {
        prepare()
        return database.indexedTransaction { db ->
            db.rawQuery("SELECT id FROM $TABLE ORDER BY quarantined,id", null).use { cursor ->
                buildSet { while (cursor.moveToNext()) add(cursor.getString(0)) }
            }
        }
    }

    fun hasRecoveryCandidate(version: Int): Boolean {
        prepare()
        return database.indexedTransaction { db ->
            db.rawQuery("SELECT 1 FROM $TABLE WHERE version < ? AND recovered < ? LIMIT 1",
                arrayOf(version.toString(), version.toString())).use { it.moveToFirst() }
        }
    }

    fun all(): List<JSONObject> {
        prepare()
        return database.readStrings(ids().map { PREFIX + it }).values.map(::JSONObject)
    }

    fun upsert(records: List<JSONObject>) {
        if (records.isEmpty()) return
        prepare()
        database.indexedTransaction { db ->
            database.mutateStrings(records.associate { PREFIX + identity(it) to it.toString() }, onMutation = ::index)
            val expired = db.rawQuery("SELECT id FROM $TABLE ORDER BY quarantined DESC,id DESC LIMIT -1 OFFSET ?",
                arrayOf(MAX_RECORDS.toString())).use { cursor ->
                buildList { while (cursor.moveToNext()) add(PREFIX + cursor.getString(0)) }
            }
            database.mutateStrings(emptyMap(), expired, onMutation = ::index)
        }
    }

    fun replace(records: List<JSONObject>) {
        prepare()
        val retained = records.distinctBy(::identity).sortedBy { it.optLong("quarantined_at_millis") }
            .takeLast(MAX_RECORDS).associate { PREFIX + identity(it) to it.toString() }
        database.mutateStreaming(retained.asSequence().map { it.key to it.value }, onMutation = ::index,
            removals = { ids().asSequence().map { PREFIX + it }.filter { it !in retained } })
    }

    private fun index(db: SQLiteDatabase, key: String, value: String?) {
        if (!key.startsWith(PREFIX)) return
        val id = key.removePrefix(PREFIX)
        if (value == null) { db.delete(TABLE, "id = ?", arrayOf(id)); return }
        val record = JSONObject(value)
        db.execSQL("INSERT OR REPLACE INTO $TABLE(id,quarantined,version,recovered) VALUES(?,?,?,?)",
            arrayOf(id, record.optLong("quarantined_at_millis"), record.optInt("quarantined_version_code"),
                record.optInt("last_auto_recovery_version_code")))
    }

    private fun identity(record: JSONObject): String = record.getJSONObject("event").getString("id").also {
        require(it.isNotBlank()) { "Missing dead-letter event identity" }
    }

    companion object {
        internal const val LEGACY = "conversation_event_dead_letters"
        internal const val PREFIX = "conversation_event_dead_letter_row:"
        private const val TABLE = "global_dead_letter_index"
        private const val READY = "global_dead_letter_rows_v1"
        private const val MAX_RECORDS = 1_000
    }
}

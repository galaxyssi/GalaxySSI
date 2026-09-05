package com.galaxyssi.chat

import android.content.ContentValues
import android.database.sqlite.SQLiteDatabase

internal data class AgentRunSnapshotPointer(val runKey: String, val sequence: Long, val ordinal: Long)

/** All writes run inside the ledger's event transaction, including migration batches. */
internal object AgentRunSnapshotIndex {
    const val TABLE = "run_snapshot_index"
    const val MIGRATION_KEY = "snapshot_event_index_v1"

    fun create(db: SQLiteDatabase) {
        db.execSQL("CREATE TABLE IF NOT EXISTS $TABLE (" +
            "kind TEXT NOT NULL, run_key TEXT NOT NULL, sequence INTEGER NOT NULL," +
            "event_ordinal INTEGER NOT NULL, task_hash TEXT NOT NULL," +
            "message_hash TEXT NOT NULL, request_hash TEXT NOT NULL," +
            "PRIMARY KEY(kind,run_key)," +
            "FOREIGN KEY(run_key,sequence) REFERENCES run_events(run_key,sequence) ON DELETE CASCADE)")
        AgentRunSnapshotLookup.entries.forEach { lookup ->
            db.execSQL("CREATE INDEX IF NOT EXISTS snapshot_${lookup.column} ON $TABLE " +
                "(kind,${lookup.column},event_ordinal DESC)")
        }
        db.execSQL("CREATE INDEX IF NOT EXISTS snapshot_recent ON $TABLE (kind,event_ordinal DESC)")
    }

    fun update(db: SQLiteDatabase, event: AgentRunControlEvent, ordinal: Long) {
        val projection = AgentRunSnapshotContract.describe(event) ?: return
        val runKey = AgentRunSnapshotContract.digest(event.runId)
        val previous = db.rawQuery("SELECT sequence FROM $TABLE WHERE kind=? AND run_key=?",
            arrayOf(projection.kind, runKey)).use { if (it.moveToFirst()) it.getLong(0) else 0L }
        // A backfill that races a new event must never overwrite the newer projection.
        if (previous >= event.sequence) return
        val values = ContentValues().apply {
            put("kind", projection.kind)
            put("run_key", runKey)
            put("sequence", event.sequence)
            put("event_ordinal", ordinal)
            put("task_hash", hash(projection.kind, AgentRunSnapshotLookup.TASK, projection.taskId))
            put("message_hash", hash(projection.kind, AgentRunSnapshotLookup.MESSAGE, projection.messageId))
            put("request_hash", hash(projection.kind, AgentRunSnapshotLookup.REQUEST, projection.requestId))
        }
        db.insertWithOnConflict(TABLE, null, values, SQLiteDatabase.CONFLICT_REPLACE).also {
            check(it != -1L) { "Run snapshot index write failed" }
        }
    }

    fun find(db: SQLiteDatabase, kind: String, lookup: AgentRunSnapshotLookup?, value: String): AgentRunSnapshotPointer? {
        if (kind.isBlank() || value.isBlank()) return null
        val column = lookup?.column ?: "run_key"
        val key = if (lookup == null) AgentRunSnapshotContract.digest(value) else hash(kind, lookup, value)
        return db.query(TABLE, arrayOf("run_key", "sequence", "event_ordinal"),
            "kind=? AND $column=?", arrayOf(kind, key), null, null, "event_ordinal DESC", "1").use {
            if (!it.moveToFirst()) null else AgentRunSnapshotPointer(it.getString(0), it.getLong(1), it.getLong(2))
        }
    }

    fun page(db: SQLiteDatabase, kind: String, beforeOrdinal: Long?, limit: Int): List<AgentRunSnapshotPointer> =
        db.query(TABLE, arrayOf("run_key", "sequence", "event_ordinal"),
            if (beforeOrdinal == null) "kind=?" else "kind=? AND event_ordinal<?",
            if (beforeOrdinal == null) arrayOf(kind) else arrayOf(kind, beforeOrdinal.toString()),
            null, null, "event_ordinal DESC", limit.coerceIn(1, 256).toString()).use { cursor ->
            buildList {
                while (cursor.moveToNext()) add(AgentRunSnapshotPointer(cursor.getString(0), cursor.getLong(1), cursor.getLong(2)))
            }
        }

    fun removeRuns(db: SQLiteDatabase, kind: String) {
        db.execSQL("DELETE FROM run_roots WHERE run_key IN (SELECT run_key FROM $TABLE WHERE kind=?)", arrayOf(kind))
    }

    private fun hash(kind: String, lookup: AgentRunSnapshotLookup, value: String) =
        AgentRunSnapshotContract.lookupHash(kind, lookup, value)
}

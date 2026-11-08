package com.galaxyssi.chat

import android.content.ContentValues
import android.database.Cursor
import android.database.sqlite.SQLiteDatabase
import org.json.JSONObject

internal class HealthCareFeedbackRows(private val db: SQLiteDatabase,
    private val pack: (String, String, JSONObject) -> ByteArray, private val unpack: (String, String, ByteArray) -> JSONObject) {
    private fun decode(row: Cursor) = HealthCareFeedbackReceipt.from(unpack("action_feedback", row.getString(0), row.getBlob(4))).also {
        check(it.feedback.id == row.getString(0) && it.concernId == row.getString(1) && it.actionId == row.getString(2) && it.revision == row.getInt(3))
    }
    fun get(id: String): HealthCareFeedbackReceipt? = db.rawQuery("SELECT $COLUMNS FROM action_feedback WHERE id=?", arrayOf(id))
        .use { if (it.moveToFirst()) decode(it) else null }
    fun write(value: HealthCareFeedbackReceipt) {
        db.insertOrThrow("action_feedback", null, ContentValues().apply {
            put("id", value.feedback.id); put("concern_id", value.concernId); put("action_id", value.actionId); put("revision", value.revision)
            put("payload", pack("action_feedback", value.feedback.id, value.json()))
        })
    }
    fun page(id: String, actionId: String?, before: Int, limit: Int): HealthCareFeedbackPage {
        require(HealthProfilePolicy.uuid(id) && (actionId == null || HealthProfilePolicy.uuid(actionId)))
        require(before > 0 && limit in 1..30)
        val args = arrayListOf(id, before.toString()).apply { actionId?.let(::add) }
        val rows = db.rawQuery("SELECT $COLUMNS FROM action_feedback WHERE concern_id=? AND revision<?" +
            (if (actionId == null) "" else " AND action_id=?") + " ORDER BY revision DESC LIMIT ${limit + 1}", args.toTypedArray())
            .use { buildList { while (it.moveToNext()) add(decode(it)) } }
        val visible = rows.take(limit)
        return HealthCareFeedbackPage(visible, if (rows.size > limit) visible.last().revision else null)
    }
    fun delete(id: String) { db.delete("action_feedback", "concern_id=?", arrayOf(id)) }
    companion object {
        private const val COLUMNS = "id,concern_id,action_id,revision,payload"
        fun create(db: SQLiteDatabase) {
            db.execSQL("CREATE TABLE action_feedback(id TEXT PRIMARY KEY,concern_id TEXT NOT NULL,action_id TEXT NOT NULL," +
                "revision INTEGER NOT NULL,payload BLOB NOT NULL,UNIQUE(concern_id,revision))")
            db.execSQL("CREATE INDEX care_feedback_action ON action_feedback(concern_id,action_id,revision DESC)")
        }
    }
}

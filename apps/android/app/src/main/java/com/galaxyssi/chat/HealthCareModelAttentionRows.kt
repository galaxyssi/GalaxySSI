package com.galaxyssi.chat

import android.content.ContentValues
import android.database.Cursor
import android.database.sqlite.SQLiteDatabase
import org.json.JSONObject

internal class HealthCareModelAttentionRows(private val db: SQLiteDatabase,
    private val pack: (String, String, JSONObject) -> ByteArray,
    private val unpack: (String, String, ByteArray) -> JSONObject) {
    private fun decode(row: Cursor) = HealthCareModelAttention.from(unpack("model_attention", row.getString(0), row.getBlob(4))).also {
        check(it.concernId == row.getString(0) && it.turnId == row.getString(1) && it.createdAt == row.getLong(2) && it.state.name == row.getString(3))
    }
    fun get(id: String): HealthCareModelAttention? = db.rawQuery(
        "SELECT concern_id,turn_id,created_at,state,payload FROM model_attention WHERE concern_id=?", arrayOf(id)).use {
        if (it.moveToFirst()) decode(it) else null
    }
    fun waiting(limit: Int): List<HealthCareModelAttention> {
        require(limit in 1..30)
        return db.rawQuery("SELECT concern_id,turn_id,created_at,state,payload FROM model_attention WHERE state='WAITING' ORDER BY created_at,concern_id LIMIT ?",
            arrayOf(limit.toString())).use { rows -> buildList { while (rows.moveToNext()) add(decode(rows)) } }
    }
    fun write(value: HealthCareModelAttention) {
        db.insertWithOnConflict("model_attention", null, ContentValues().apply {
            put("concern_id", value.concernId); put("turn_id", value.turnId); put("created_at", value.createdAt)
            put("state", value.state.name); put("payload", pack("model_attention", value.concernId, value.json()))
        }, SQLiteDatabase.CONFLICT_REPLACE)
        check(get(value.concernId) == value) { "The health attention receipt was not retained" }
    }
    fun delete(id: String) { db.delete("model_attention", "concern_id=?", arrayOf(id)) }
    companion object {
        fun create(db: SQLiteDatabase) {
            db.execSQL("CREATE TABLE model_attention(concern_id TEXT PRIMARY KEY,turn_id TEXT NOT NULL,created_at INTEGER NOT NULL,state TEXT NOT NULL,payload BLOB NOT NULL)")
            db.execSQL("CREATE INDEX care_model_attention_pending ON model_attention(state,created_at,concern_id)")
        }
    }
}

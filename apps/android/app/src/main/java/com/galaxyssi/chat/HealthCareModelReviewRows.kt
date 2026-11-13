package com.galaxyssi.chat

import android.content.ContentValues
import android.database.sqlite.SQLiteDatabase
import org.json.JSONObject

internal class HealthCareModelReviewRows(private val db: SQLiteDatabase,
    private val pack: (String, String, JSONObject) -> ByteArray,
    private val unpack: (String, String, ByteArray) -> JSONObject) {
    fun get(turn: String): HealthCareModelReview? = db.rawQuery(
        "SELECT concern_id,created_at,payload FROM model_reviews WHERE turn_id=?", arrayOf(turn)).use {
        if (!it.moveToFirst()) null else HealthCareModelReview.from(unpack("model_review", turn, it.getBlob(2))).also { value ->
            check(value.grant.turnId == turn && value.grant.concernId == it.getString(0) && value.createdAt == it.getLong(1))
        }
    }
    fun insert(value: HealthCareModelReview) {
        db.insertOrThrow("model_reviews", null, ContentValues().apply {
            put("turn_id", value.grant.turnId); put("concern_id", value.grant.concernId); put("created_at", value.createdAt)
            put("payload", pack("model_review", value.grant.turnId, value.json()))
        })
    }
    fun delete(concern: String) { db.delete("model_reviews", "concern_id=?", arrayOf(concern)) }
    companion object {
        fun create(db: SQLiteDatabase) {
            db.execSQL("CREATE TABLE model_reviews(turn_id TEXT PRIMARY KEY,concern_id TEXT NOT NULL,created_at INTEGER NOT NULL,payload BLOB NOT NULL)")
            db.execSQL("CREATE INDEX care_model_review_concern ON model_reviews(concern_id,created_at DESC,turn_id DESC)")
        }
    }
}

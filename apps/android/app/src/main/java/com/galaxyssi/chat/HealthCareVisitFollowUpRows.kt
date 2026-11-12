package com.galaxyssi.chat

import android.content.ContentValues
import android.database.sqlite.SQLiteDatabase
import org.json.JSONObject

internal class HealthCareVisitFollowUpRows(private val db: SQLiteDatabase,
    private val pack: (String, String, JSONObject) -> ByteArray, private val unpack: (String, String, ByteArray) -> JSONObject) {
    fun get(encounter: String): HealthCareVisitFollowUp? = db.rawQuery(
        "SELECT id,concern_id,revision,payload FROM visit_followups WHERE encounter_id=?", arrayOf(encounter)).use { r ->
        if (!r.moveToFirst()) null else HealthCareVisitFollowUp.from(unpack("visit_followup", r.getString(0), r.getBlob(3))).also {
            check(it.id == r.getString(0) && it.concernId == r.getString(1) && it.encounterId == encounter && it.revision == r.getInt(2))
        }
    }
    fun receipt(id: String): HealthCareVisitFollowUpReceipt? = db.rawQuery(
        "SELECT concern_id,encounter_id,revision,payload FROM visit_followup_events WHERE operation_id=?", arrayOf(id)).use { r ->
        if (!r.moveToFirst()) null else decode(id, r.getString(0), r.getString(1), r.getInt(2), r.getBlob(3))
    }
    private fun decode(id: String, concern: String, encounter: String, revision: Int, bytes: ByteArray) =
        HealthCareVisitFollowUpReceipt.from(unpack("visit_followup_event", id, bytes)).also {
            check(it.operationId == id && it.value.concernId == concern && it.value.encounterId == encounter && it.value.revision == revision)
        }
    fun write(value: HealthCareVisitFollowUpReceipt) {
        db.insertOrThrow("visit_followup_events", null, ContentValues().apply {
            put("operation_id", value.operationId); put("concern_id", value.value.concernId); put("encounter_id", value.value.encounterId)
            put("revision", value.value.revision); put("payload", pack("visit_followup_event", value.operationId, value.json()))
        })
        db.insertWithOnConflict("visit_followups", null, ContentValues().apply {
            put("id", value.value.id); put("concern_id", value.value.concernId); put("encounter_id", value.value.encounterId)
            put("revision", value.value.revision); put("payload", pack("visit_followup", value.value.id, value.value.json()))
        }, SQLiteDatabase.CONFLICT_REPLACE)
        check(get(value.value.encounterId) == value.value && receipt(value.operationId) == value) { "Follow-up write failed" }
    }
    fun page(concern: String, encounter: String, before: Int, limit: Int): HealthCareVisitFollowUpPage {
        require(listOf(concern, encounter).all(HealthProfilePolicy::uuid) && before > 0 && limit in 1..30)
        val values = db.rawQuery("SELECT operation_id,revision,payload FROM visit_followup_events WHERE concern_id=? AND encounter_id=? " +
            "AND revision<? ORDER BY revision DESC LIMIT ${limit + 1}", arrayOf(concern, encounter, before.toString())).use { r -> buildList {
            while (r.moveToNext()) add(decode(r.getString(0), concern, encounter, r.getInt(1), r.getBlob(2)))
        } }
        return HealthCareVisitFollowUpPage(values.take(limit), if (values.size > limit) values[limit - 1].value.revision else null)
    }
    fun purge(concern: String, encounter: String? = null) {
        val where = "concern_id=?" + if (encounter == null) "" else " AND encounter_id=?"
        val args = listOfNotNull(concern, encounter).toTypedArray()
        db.delete("visit_followups", where, args); db.delete("visit_followup_events", where, args)
    }
    companion object {
        fun create(db: SQLiteDatabase) {
            db.execSQL("CREATE TABLE visit_followups(id TEXT PRIMARY KEY,concern_id TEXT NOT NULL,encounter_id TEXT NOT NULL UNIQUE," +
                "revision INTEGER NOT NULL,payload BLOB NOT NULL)")
            db.execSQL("CREATE INDEX care_visit_followup_owner ON visit_followups(concern_id)")
            db.execSQL("CREATE TABLE visit_followup_events(operation_id TEXT PRIMARY KEY,concern_id TEXT NOT NULL,encounter_id TEXT NOT NULL," +
                "revision INTEGER NOT NULL,payload BLOB NOT NULL,UNIQUE(concern_id,revision))")
            db.execSQL("CREATE INDEX care_visit_followup_history ON visit_followup_events(concern_id,encounter_id,revision DESC)")
        }
    }
}

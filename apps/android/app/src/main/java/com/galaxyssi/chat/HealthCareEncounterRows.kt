package com.galaxyssi.chat

import android.content.ContentValues
import android.database.Cursor
import android.database.sqlite.SQLiteDatabase
import org.json.JSONObject

/** Only opaque ownership and revision indexes are plaintext; dates and content are authenticated ciphertext. */
internal class HealthCareEncounterRows(private val db: SQLiteDatabase,
    private val pack: (String, String, JSONObject) -> ByteArray, private val unpack: (String, String, ByteArray) -> JSONObject) {
    private fun decode(row: Cursor) = HealthCareEncounter.from(unpack("encounter", "${row.getString(0)}:${row.getInt(2)}", row.getBlob(3))).also {
        check(it.id == row.getString(0) && it.concernId == row.getString(1) && it.revision == row.getInt(2))
    }
    fun get(id: String): HealthCareEncounter? {
        require(HealthProfilePolicy.uuid(id))
        return db.rawQuery("SELECT $COLUMNS FROM encounters WHERE id=?", arrayOf(id)).use { if (it.moveToFirst()) decode(it) else null }
    }
    fun receipt(id: String): HealthCareEncounterReceipt? {
        require(HealthProfilePolicy.uuid(id))
        return db.rawQuery("SELECT concern_id,encounter_id,revision,payload FROM encounter_events WHERE operation_id=?", arrayOf(id)).use { row ->
            if (!row.moveToFirst()) null else HealthCareEncounterReceipt.from(unpack("encounter_event", id, row.getBlob(3))).also {
                check(it.operationId == id && it.encounter.concernId == row.getString(0) && it.encounter.id == row.getString(1) &&
                    it.encounter.revision == row.getInt(2))
            }
        }
    }
    fun write(receipt: HealthCareEncounterReceipt) {
        val value = receipt.encounter
        db.insertOrThrow("encounter_events", null, ContentValues().apply {
            put("operation_id", receipt.operationId); put("concern_id", value.concernId); put("encounter_id", value.id); put("revision", value.revision)
            put("payload", pack("encounter_event", receipt.operationId, receipt.json()))
        })
        check(db.insertWithOnConflict("encounters", null, ContentValues().apply {
            put("id", value.id); put("concern_id", value.concernId); put("revision", value.revision)
            put("payload", pack("encounter", "${value.id}:${value.revision}", value.json()))
        }, SQLiteDatabase.CONFLICT_REPLACE) != -1L) { "Encounter write failed" }
    }
    fun page(concernId: String, before: Int, limit: Int): HealthCareEncounterPage {
        require(HealthProfilePolicy.uuid(concernId) && before > 0 && limit in 1..30)
        val items = db.rawQuery("SELECT $COLUMNS FROM encounters WHERE concern_id=? AND revision<? ORDER BY revision DESC LIMIT ${limit + 1}",
            arrayOf(concernId, before.toString())).use { rows -> buildList { while (rows.moveToNext()) add(decode(rows)) } }
        return HealthCareEncounterPage(items.take(limit), if (items.size > limit) items[limit - 1].revision else null)
    }
    fun history(concernId: String, encounterId: String, before: Int, limit: Int): HealthCareEncounterPage {
        require(HealthProfilePolicy.uuid(concernId) && HealthProfilePolicy.uuid(encounterId) && before > 0 && limit in 1..30)
        val items = db.rawQuery("SELECT operation_id,revision,payload FROM encounter_events WHERE concern_id=? AND encounter_id=? " +
            "AND revision<? ORDER BY revision DESC LIMIT ${limit + 1}", arrayOf(concernId, encounterId, before.toString())).use { rows -> buildList {
            while (rows.moveToNext()) {
                val value = HealthCareEncounterReceipt.from(unpack("encounter_event", rows.getString(0), rows.getBlob(2)))
                check(value.operationId == rows.getString(0) && value.encounter.concernId == concernId && value.encounter.id == encounterId &&
                    value.encounter.revision == rows.getInt(1))
                add(value.encounter)
            }
        } }
        return HealthCareEncounterPage(items.take(limit), if (items.size > limit) items[limit - 1].revision else null)
    }
    fun delete(concernId: String, encounterId: String? = null) {
        require(HealthProfilePolicy.uuid(concernId) && (encounterId == null || HealthProfilePolicy.uuid(encounterId)))
        val args = listOfNotNull(concernId, encounterId).toTypedArray()
        db.delete("encounters", "concern_id=?" + if (encounterId == null) "" else " AND id=?", args)
        db.delete("encounter_events", "concern_id=?" + if (encounterId == null) "" else " AND encounter_id=?", args)
    }
    companion object {
        private const val COLUMNS = "id,concern_id,revision,payload"
        fun create(db: SQLiteDatabase) {
            db.execSQL("CREATE TABLE encounters(id TEXT PRIMARY KEY,concern_id TEXT NOT NULL,revision INTEGER NOT NULL,payload BLOB NOT NULL," +
                "UNIQUE(concern_id,revision))")
            db.execSQL("CREATE TABLE encounter_events(operation_id TEXT PRIMARY KEY,concern_id TEXT NOT NULL,encounter_id TEXT NOT NULL," +
                "revision INTEGER NOT NULL,payload BLOB NOT NULL,UNIQUE(concern_id,revision))")
            db.execSQL("CREATE INDEX care_encounter_history ON encounter_events(concern_id,encounter_id,revision DESC)")
        }
    }
}

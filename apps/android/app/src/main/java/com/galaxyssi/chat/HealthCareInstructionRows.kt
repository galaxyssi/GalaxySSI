package com.galaxyssi.chat

import android.content.ContentValues
import android.database.Cursor
import android.database.sqlite.SQLiteDatabase
import org.json.JSONObject

internal class HealthCareInstructionRows(private val db: SQLiteDatabase,
    private val pack: (String, String, JSONObject) -> ByteArray, private val unpack: (String, String, ByteArray) -> JSONObject) {
    private fun decode(row: Cursor) = HealthCareInstruction.from(unpack("instruction", "${row.getString(0)}:${row.getInt(4)}", row.getBlob(5))).also {
        check(it.id == row.getString(0) && it.concernId == row.getString(1) && it.encounterId == row.getString(2) &&
            it.source.documentId == row.getString(3) && it.revision == row.getInt(4))
    }
    fun get(id: String): HealthCareInstruction? {
        require(HealthProfilePolicy.uuid(id))
        return db.rawQuery("SELECT $COLUMNS FROM clinical_instructions WHERE id=?", arrayOf(id)).use { if (it.moveToFirst()) decode(it) else null }
    }
    fun hasSource(id: String) = db.rawQuery("SELECT 1 FROM clinical_instructions WHERE document_id=? LIMIT 1", arrayOf(id)).use { it.moveToFirst() }
    private fun decodeReceipt(row: Cursor) = HealthCareInstructionReceipt.from(unpack("instruction_event", row.getString(0), row.getBlob(5))).also {
        check(it.operationId == row.getString(0) && it.value.concernId == row.getString(1) && it.value.encounterId == row.getString(2) &&
            it.value.id == row.getString(3) && it.value.revision == row.getInt(4))
    }
    fun receipt(id: String): HealthCareInstructionReceipt? {
        require(HealthProfilePolicy.uuid(id))
        return db.rawQuery("SELECT $EVENT_COLUMNS FROM instruction_events WHERE operation_id=?", arrayOf(id)).use { row ->
            if (row.moveToFirst()) decodeReceipt(row) else null
        }
    }
    fun write(receipt: HealthCareInstructionReceipt) {
        val value = receipt.value
        check(db.insertOrThrow("instruction_events", null, ContentValues().apply {
            put("operation_id", receipt.operationId); put("concern_id", value.concernId); put("encounter_id", value.encounterId)
            put("instruction_id", value.id); put("revision", value.revision); put("payload", pack("instruction_event", receipt.operationId, receipt.json()))
        }) != -1L)
        check(db.insertWithOnConflict("clinical_instructions", null, ContentValues().apply {
            put("id", value.id); put("concern_id", value.concernId); put("encounter_id", value.encounterId); put("document_id", value.source.documentId)
            put("revision", value.revision); put("payload", pack("instruction", "${value.id}:${value.revision}", value.json()))
        }, SQLiteDatabase.CONFLICT_REPLACE) != -1L)
    }
    fun page(concernId: String, encounterId: String, before: Int, limit: Int): HealthCareInstructionPage {
        require(HealthProfilePolicy.uuid(concernId) && HealthProfilePolicy.uuid(encounterId) && before > 0 && limit in 1..30)
        val rows = db.rawQuery("SELECT $COLUMNS FROM clinical_instructions WHERE concern_id=? AND encounter_id=? AND revision<? " +
            "ORDER BY revision DESC LIMIT ${limit + 1}", arrayOf(concernId, encounterId, before.toString())).use { row -> buildList {
            while (row.moveToNext()) add(decode(row))
        } }
        return HealthCareInstructionPage(rows.take(limit), if (rows.size > limit) rows[limit - 1].revision else null)
    }
    fun history(concernId: String, instructionId: String, before: Int, limit: Int): HealthCareInstructionPage {
        require(HealthProfilePolicy.uuid(concernId) && HealthProfilePolicy.uuid(instructionId) && before > 0 && limit in 1..30)
        val rows = db.rawQuery("SELECT $EVENT_COLUMNS FROM instruction_events WHERE concern_id=? AND instruction_id=? AND revision<? " +
            "ORDER BY revision DESC LIMIT ${limit + 1}", arrayOf(concernId, instructionId, before.toString())).use { row -> buildList {
            while (row.moveToNext()) add(decodeReceipt(row).value)
        } }
        return HealthCareInstructionPage(rows.take(limit), if (rows.size > limit) rows[limit - 1].revision else null)
    }
    fun purge(concernId: String, encounterId: String? = null, instructionId: String? = null) {
        val suffix = (if (encounterId != null) " AND encounter_id=?" else "") + if (instructionId != null) " AND %s=?" else ""
        val args = listOfNotNull(concernId, encounterId, instructionId).toTypedArray()
        db.delete("clinical_instructions", "concern_id=?" + suffix.replace("%s", "id"), args)
        db.delete("instruction_events", "concern_id=?" + suffix.replace("%s", "instruction_id"), args)
    }
    companion object {
        private const val COLUMNS = "id,concern_id,encounter_id,document_id,revision,payload"
        private const val EVENT_COLUMNS = "operation_id,concern_id,encounter_id,instruction_id,revision,payload"
        fun create(db: SQLiteDatabase) {
            db.execSQL("CREATE TABLE clinical_instructions(id TEXT PRIMARY KEY,concern_id TEXT NOT NULL,encounter_id TEXT NOT NULL," +
                "document_id TEXT NOT NULL,revision INTEGER NOT NULL,payload BLOB NOT NULL,UNIQUE(concern_id,revision))")
            db.execSQL("CREATE TABLE instruction_events(operation_id TEXT PRIMARY KEY,concern_id TEXT NOT NULL,encounter_id TEXT NOT NULL," +
                "instruction_id TEXT NOT NULL,revision INTEGER NOT NULL,payload BLOB NOT NULL,UNIQUE(concern_id,revision))")
            db.execSQL("CREATE INDEX care_instructions ON clinical_instructions(concern_id,encounter_id,revision DESC)")
            db.execSQL("CREATE INDEX care_instruction_source ON clinical_instructions(document_id)")
            db.execSQL("CREATE INDEX care_instruction_history ON instruction_events(concern_id,instruction_id,revision DESC)")
        }
    }
}

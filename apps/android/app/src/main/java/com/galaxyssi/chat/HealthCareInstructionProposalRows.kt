package com.galaxyssi.chat

import android.content.ContentValues
import android.database.sqlite.SQLiteDatabase
import org.json.JSONObject

internal class HealthCareInstructionProposalRows(private val db: SQLiteDatabase,
    private val pack: (String, String, JSONObject) -> ByteArray, private val unpack: (String, String, ByteArray) -> JSONObject) {
    private fun decode(id: String, instruction: String, concern: String, encounter: String, state: String, bytes: ByteArray) =
        HealthCareInstructionProposal.from(unpack("instruction_proposal", "$id:$instruction:$concern:$encounter:$state", bytes)).also {
            check(it.id == id && it.scope.id == instruction && it.grant.concernId == concern && it.encounterId == encounter && it.state.name == state)
        }
    private fun read(where: String, args: Array<String>): HealthCareInstructionProposal? =
        db.rawQuery("SELECT turn_id,instruction_id,concern_id,encounter_id,state,payload FROM instruction_proposals WHERE $where LIMIT 1", args).use {
            if (it.moveToFirst()) decode(it.getString(0), it.getString(1), it.getString(2), it.getString(3), it.getString(4), it.getBlob(5)) else null
        }
    fun get(id: String) = read("turn_id=?", arrayOf(id))
    fun pending(id: String) = read("instruction_id=? AND state='PENDING'", arrayOf(id))
    fun write(value: HealthCareInstructionProposal) {
        db.insertWithOnConflict("instruction_proposals", null, ContentValues().apply {
            put("turn_id", value.id); put("instruction_id", value.scope.id); put("concern_id", value.grant.concernId)
            put("encounter_id", value.encounterId); put("state", value.state.name)
            put("payload", pack("instruction_proposal", "${value.id}:${value.scope.id}:${value.grant.concernId}:${value.encounterId}:${value.state}", value.json()))
        }, SQLiteDatabase.CONFLICT_REPLACE)
        check(get(value.id) == value) { "Instruction proposal was not persisted" }
    }
    fun purge(concern: String, encounter: String? = null, instruction: String? = null) {
        val args = mutableListOf(concern)
        val where = buildString {
            append("concern_id=?")
            encounter?.let { append(" AND encounter_id=?"); args += it }
            instruction?.let { append(" AND instruction_id=?"); args += it }
        }
        db.delete("instruction_proposals", where, args.toTypedArray())
    }
    companion object {
        fun create(db: SQLiteDatabase) {
            db.execSQL("CREATE TABLE instruction_proposals(turn_id TEXT PRIMARY KEY,instruction_id TEXT NOT NULL,concern_id TEXT NOT NULL,encounter_id TEXT NOT NULL,state TEXT NOT NULL,payload BLOB NOT NULL)")
            db.execSQL("CREATE UNIQUE INDEX care_instruction_pending ON instruction_proposals(instruction_id) WHERE state='PENDING'")
            db.execSQL("CREATE INDEX care_instruction_proposal_owner ON instruction_proposals(concern_id,encounter_id,instruction_id)")
        }
    }
}

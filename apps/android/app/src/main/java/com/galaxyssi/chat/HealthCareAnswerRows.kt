package com.galaxyssi.chat

import android.content.ContentValues
import android.database.sqlite.SQLiteDatabase
import org.json.JSONObject
import java.util.UUID

internal class HealthCareAnswerRows(private val db: SQLiteDatabase,
    private val pack: (String, String, JSONObject) -> ByteArray,
    private val unpack: (String, String, ByteArray) -> JSONObject, private val index: (String) -> String) {
    private fun decode(id: String, state: String, bytes: ByteArray) =
        HealthCareAnswerDraft.from(unpack("answer_draft", "$id:$state", bytes)).also { check(it.id == id && it.state.name == state) }
    fun get(id: String): HealthCareAnswerDraft? = db.rawQuery("SELECT state,payload FROM answer_drafts WHERE id=?", arrayOf(id)).use {
        if (it.moveToFirst()) decode(id, it.getString(0), it.getBlob(1)) else null
    }
    fun page(issue: HealthCareConcern, after: String = "", limit: Int = 30): HealthCareAnswerPage {
        require((after.isEmpty() || HealthProfilePolicy.uuid(after)) && limit in 1..30)
        val scope = HealthCareQuestionPolicy.scope(issue)
        val items = db.rawQuery("SELECT id,state,payload FROM answer_drafts WHERE concern_id=? AND scope_key=? AND state='PENDING' AND id>? ORDER BY id LIMIT ${limit + 1}",
            arrayOf(issue.id, index(scope), after)).use { row -> buildList {
                while (row.moveToNext()) add(decode(row.getString(0), row.getString(1), row.getBlob(2)).also {
                    check(it.grant.concernId == issue.id && it.scope == scope)
                })
            } }
        return HealthCareAnswerPage(items.take(limit), if (items.size > limit) items[limit - 1].id else null)
    }
    fun propose(grant: HealthCareDiscussionGrant, issue: HealthCareConcern, question: HealthCareQuestion,
        source: AgentTranscriptEntry, quote: String, answer: String, now: Long): HealthCareAnswerDraft {
        db.rawQuery("SELECT id,state,payload FROM answer_drafts WHERE question_id=? AND turn_id=?", arrayOf(question.id, grant.turnId)).use {
            if (it.moveToFirst()) return decode(it.getString(0), it.getString(1), it.getBlob(2))
        }
        return HealthCareAnswerDraft(UUID.randomUUID().toString(), grant, question.id, question.revision,
            HealthCareQuestionPolicy.basis(issue), HealthCareQuestionPolicy.scope(issue), source.id, quote, answer, now).also(::write)
    }
    fun write(value: HealthCareAnswerDraft) {
        db.insertWithOnConflict("answer_drafts", null, ContentValues().apply {
            put("id", value.id); put("concern_id", value.grant.concernId); put("scope_key", index(value.scope))
            put("question_id", value.questionId); put("turn_id", value.grant.turnId); put("state", value.state.name)
            put("payload", pack("answer_draft", "${value.id}:${value.state}", value.json()))
        }, SQLiteDatabase.CONFLICT_REPLACE)
    }
    fun delete(concernId: String) { db.delete("answer_drafts", "concern_id=?", arrayOf(concernId)) }
    companion object {
        fun create(db: SQLiteDatabase) {
            db.execSQL("CREATE TABLE answer_drafts(id TEXT PRIMARY KEY,concern_id TEXT NOT NULL,scope_key TEXT NOT NULL,question_id TEXT NOT NULL,turn_id TEXT NOT NULL,state TEXT NOT NULL,payload BLOB NOT NULL,UNIQUE(question_id,turn_id))")
            db.execSQL("CREATE INDEX care_answer_pages ON answer_drafts(concern_id,scope_key,state,id)")
        }
    }
}

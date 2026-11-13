package com.galaxyssi.chat

import android.content.ContentValues
import android.database.sqlite.SQLiteDatabase
import java.util.UUID
import org.json.JSONObject

/** Called under the care store's transaction; sensitive content stays in authenticated encrypted rows. */
internal class HealthCareQuestionRows(private val db: SQLiteDatabase,
    private val pack: (String, String, JSONObject) -> ByteArray,
    private val unpack: (String, String, ByteArray) -> JSONObject,
    private val index: (String) -> String) {
    fun get(id: String): HealthCareQuestion? = db.rawQuery("SELECT revision,payload FROM questions WHERE id=?", arrayOf(id)).use {
        if (!it.moveToFirst()) null else decode(id, it.getInt(0), it.getBlob(1))
    }
    private fun decode(id: String, revision: Int, bytes: ByteArray) = HealthCareQuestion.from(unpack("question", "$id:$revision", bytes)).also {
        check(it.id == id && it.revision == revision)
    }
    fun page(issue: HealthCareConcern, after: String = "", limit: Int = 30): HealthCareQuestionPage {
        require((after.isEmpty() || HealthProfilePolicy.uuid(after)) && limit in 1..30)
        val scope = index(HealthCareQuestionPolicy.scope(issue))
        val rows = db.rawQuery("SELECT id,revision,payload FROM questions WHERE concern_id=? AND scope_key=? AND id>? ORDER BY id LIMIT ${limit + 1}",
            arrayOf(issue.id, scope, after)).use { row -> buildList {
                while (row.moveToNext()) add(decode(row.getString(0), row.getInt(1), row.getBlob(2)).also {
                    check(it.concernId == issue.id && index(it.scope) == scope)
                })
            } }
        return HealthCareQuestionPage(rows.take(limit), if (rows.size > limit) rows[limit - 1].id else null)
    }
    fun propose(issue: HealthCareConcern, grant: HealthCareDiscussionGrant, key: String, question: String, purpose: String, now: Long): HealthCareQuestion {
        require(key.matches(Regex("[a-z][a-z0-9_.]{0,79}")) && question.isNotBlank() && question.length <= 500 && purpose.isNotBlank() && purpose.length <= 1000)
        val scope = HealthCareQuestionPolicy.scope(issue)
        val scoped = index(scope); val keyed = index(key)
        db.rawQuery("SELECT id,revision,payload FROM questions WHERE concern_id=? AND scope_key=? AND question_key=?",
            arrayOf(issue.id, scoped, keyed)).use { row -> if (row.moveToFirst()) return decode(row.getString(0), row.getInt(1), row.getBlob(2)).also {
                check(it.concernId == issue.id && it.scope == scope && it.key == key)
                if (!grant.related.keys.containsAll(it.related)) throw HealthCareConflict()
            } }
        return HealthCareQuestion(UUID.randomUUID().toString(), issue.id, key, question, purpose, HealthCareQuestionPolicy.basis(issue),
            scope, issue.assessment.record, issue.assessment.measuredAt, grant.turnId, 1, now, now,
            related = grant.related.keys).also(::write)
    }
    fun review(issue: HealthCareConcern, id: String, expected: Int, state: HealthCareQuestionState, answer: String, now: Long): HealthCareQuestion {
        val before = get(id) ?: throw HealthCareConflict()
        if (before.concernId != issue.id || before.scope != HealthCareQuestionPolicy.scope(issue) || before.revision != expected) throw HealthCareConflict()
        val next = before.copy(state = state, answer = answer.trim(), basis = HealthCareQuestionPolicy.basis(issue),
            record = issue.assessment.record, measuredAt = issue.assessment.measuredAt)
        if (next == before) return before
        return next.copy(revision = before.revision + 1, updatedAt = maxOf(now, before.updatedAt)).also(::write)
    }
    private fun write(value: HealthCareQuestion) {
        val encrypted = pack("question", "${value.id}:${value.revision}", value.json())
        db.insertWithOnConflict("questions", null, ContentValues().apply {
            put("id", value.id); put("concern_id", value.concernId); put("scope_key", index(value.scope)); put("question_key", index(value.key))
            put("revision", value.revision); put("payload", encrypted)
        }, SQLiteDatabase.CONFLICT_REPLACE)
        db.insertOrThrow("question_history", null, ContentValues().apply {
            put("question_id", value.id); put("revision", value.revision); put("payload", encrypted)
        })
    }
    fun delete(concernId: String) {
        db.execSQL("DELETE FROM question_history WHERE question_id IN (SELECT id FROM questions WHERE concern_id=?)", arrayOf(concernId))
        db.delete("questions", "concern_id=?", arrayOf(concernId))
    }
    companion object {
        fun create(db: SQLiteDatabase) {
            db.execSQL("CREATE TABLE questions(id TEXT PRIMARY KEY,concern_id TEXT NOT NULL,scope_key TEXT NOT NULL,question_key TEXT NOT NULL,revision INTEGER NOT NULL,payload BLOB NOT NULL,UNIQUE(concern_id,scope_key,question_key))")
            db.execSQL("CREATE INDEX care_question_pages ON questions(concern_id,scope_key,id)")
            db.execSQL("CREATE TABLE question_history(question_id TEXT NOT NULL,revision INTEGER NOT NULL,payload BLOB NOT NULL,PRIMARY KEY(question_id,revision))")
        }
    }
}

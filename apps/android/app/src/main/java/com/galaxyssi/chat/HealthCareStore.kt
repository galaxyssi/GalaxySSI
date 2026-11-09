package com.galaxyssi.chat

import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import java.io.Closeable
import java.util.UUID
import org.json.JSONObject

/** Durable care issues and their revisions are independent of the lifetime of an Agent conversation. */
internal class HealthCareStore(context: Context, private val name: String = DEFAULT_DB) : Closeable {
    private val app = context.applicationContext
    private val helper = Database(app, name)
    private val db get() = helper.writableDatabase
    private fun metricKey(metric: HealthMetric) = AgentMemoryIndexKey.token("$name|care-metric|self|${metric.name}")
    private fun questionRows() = HealthCareQuestionRows(db, ::pack, ::unpack) { AgentMemoryIndexKey.token("$name|care-question|self|$it") }
    private fun answerRows() = HealthCareAnswerRows(db, ::pack, ::unpack) { AgentMemoryIndexKey.token("$name|care-answer|self|$it") }
    private fun agendaRows() = HealthCareAgendaRows(db, ::concern, ::reminders)
    private fun feedbackRows() = HealthCareFeedbackRows(db, ::pack, ::unpack)
    private fun encounterRows() = HealthCareEncounterRows(db, ::pack, ::unpack)
    private fun instructionRows() = HealthCareInstructionRows(db, ::pack, ::unpack)
    fun instruction(id: String) = instructionRows().get(id)
    fun instructions(id: String, encounterId: String, before: Int = Int.MAX_VALUE, limit: Int = 30) = instructionRows().page(id, encounterId, before, limit)
    fun instructionHistory(id: String, instructionId: String, before: Int = Int.MAX_VALUE, limit: Int = 30) = instructionRows().history(id, instructionId, before, limit)
    private fun documentRows() = HealthCareDocumentRows(db, ::pack, ::unpack) { AgentMemoryIndexKey.token("$name|care-document|self|$it") }
    fun encounterDocuments(id: String, encounterId: String, before: Int = Int.MAX_VALUE, limit: Int = 30) =
        documentRows().page(id, encounterId, before, limit)
    fun encounterDocument(id: String) = documentRows().get(id)
    fun encounter(id: String) = encounterRows().get(id)
    fun encounters(id: String, beforeRevision: Int = Int.MAX_VALUE, limit: Int = 30, expectedRevision: Int? = null): HealthCareEncounterPage = transaction {
        val issue = concern(id) ?: throw HealthCareConflict()
        require(beforeRevision == Int.MAX_VALUE || expectedRevision != null)
        if (expectedRevision != null && issue.revision != expectedRevision) throw HealthCareConflict()
        encounterRows().page(id, beforeRevision, limit).copy(concernRevision = issue.revision)
    }
    fun encounterHistory(id: String, encounterId: String, beforeRevision: Int = Int.MAX_VALUE, limit: Int = 30) =
        encounterRows().history(id, encounterId, beforeRevision, limit)
    fun feedback(id: String, actionId: String? = null, beforeRevision: Int = Int.MAX_VALUE, limit: Int = 30) =
        feedbackRows().page(id, actionId, beforeRevision, limit)
    fun prepareAgendaBatch(limit: Int = 30): Boolean = transaction { agendaRows().prepareBatch(limit) }
    fun agenda(filter: HealthCareAgendaFilter, dayEnd: Long, after: HealthCareAgendaCursor? = null, limit: Int = 30): HealthCareAgendaPage =
        transaction { agendaRows().page(filter, dayEnd, after, limit) }
    private fun aad(kind: String, id: String) = "$name|health-care-v1|self|$kind|$id".toByteArray(Charsets.UTF_8)
    private fun pack(kind: String, id: String, json: JSONObject): ByteArray {
        val plain = json.toString().toByteArray(Charsets.UTF_8)
        return try { AgentStorageCipher.encryptBinary(plain, aad(kind, id)) } finally { plain.fill(0) }
    }
    private fun unpack(kind: String, id: String, encrypted: ByteArray): JSONObject {
        val plain = AgentStorageCipher.decryptBinary(encrypted, aad(kind, id))
        return try { JSONObject(String(plain, Charsets.UTF_8)) } finally { plain.fill(0) }
    }
    @Synchronized private fun <T> transaction(notify: Boolean = false, block: () -> T): T {
        db.beginTransactionNonExclusive()
        var committed = false
        return try { block().also { db.setTransactionSuccessful(); committed = true } }
        finally {
            db.endTransaction()
            if (committed && notify) {
                app.contentResolver.notifyChange(changes(app, name), null)
                if (name == DEFAULT_DB) {
                    HealthReminderWork.sourceRemindersChanged(app)
                    HealthCareResearchWork.changed(app)
                }
            }
        }
    }
    fun settings(): HealthCareSettings = db.rawQuery("SELECT version,payload FROM settings WHERE id=1", null).use {
        if (!it.moveToFirst()) HealthCareSettings() else {
            val version = it.getString(0)
            val j = unpack("settings", version, it.getBlob(1))
            check(j.getString("version") == version)
            HealthCareSettings(j.getBoolean("enabled"), version)
        }
    }
    fun configure(enabled: Boolean, expectedVersion: String): HealthCareSettings = transaction(true) {
        val before = settings()
        if (before.version != expectedVersion) throw HealthCareConflict()
        if (before.enabled == enabled) return@transaction before
        val next = HealthCareSettings(enabled, UUID.randomUUID().toString())
        db.insertWithOnConflict("settings", null, ContentValues().apply {
            put("id", 1); put("version", next.version)
            put("payload", pack("settings", next.version, JSONObject().put("enabled", enabled).put("version", next.version)))
        }, SQLiteDatabase.CONFLICT_REPLACE)
        if (!enabled) {
            invalidateReminders(System.currentTimeMillis(), null)
            var after = ""
            while (true) {
                val page = researchAuthorizations(after)
                if (page.isEmpty()) break
                page.filter { it.active }.forEach { revokeResearchInternal(it.scope.concernId, it.id, System.currentTimeMillis()) }
                after = page.last().scope.concernId
            }
        }
        next
    }
    private fun decode(row: Cursor): HealthCareConcern {
        val value = HealthCareConcern.from(unpack("concern", "${row.getString(0)}:${row.getInt(1)}", row.getBlob(2)))
        check(value.id == row.getString(0) && value.revision == row.getInt(1) && value.updatedAt == row.getLong(3))
        check(metricKey(value.metric) == row.getString(4) && value.open == (row.getInt(5) == 1) && value.stage.name == row.getString(6))
        check(value.nextDue == if (row.isNull(7)) null else row.getLong(7))
        check(HealthCarePriority.rank(value.assessment) == row.getInt(8))
        return value
    }
    fun concern(id: String): HealthCareConcern? {
        require(HealthProfilePolicy.uuid(id))
        return db.rawQuery("SELECT $COLUMNS FROM concerns WHERE id=?", arrayOf(id)).use { if (it.moveToFirst()) decode(it) else null }
    }
    fun forMetric(metric: HealthMetric): HealthCareConcern? = db.rawQuery("SELECT $COLUMNS FROM concerns WHERE metric_key=?",
        arrayOf(metricKey(metric))).use { if (it.moveToFirst()) decode(it) else null }
    fun evaluated(metric: HealthMetric, evaluationVersion: String = ""): String? = evaluation(metric)?.let {
        if (it.optBoolean("dismissed") || it.optString("assessment_version") == evaluationVersion) it.getString("token") else null
    }
    private fun evaluation(metric: HealthMetric): JSONObject? = db.rawQuery("SELECT token,payload FROM evaluations WHERE metric_key=?", arrayOf(metricKey(metric))).use {
        if (!it.moveToFirst()) null else {
            val token = it.getString(0); val j = unpack("evaluation", "${metricKey(metric)}:$token", it.getBlob(1))
            check(j.getString("metric") == metric.name && j.getString("token") == token); j
        }
    }
    private fun persist(value: HealthCareConcern, event: String) {
        require(event.isNotBlank() && event.length <= 120)
        val encrypted = pack("concern", "${value.id}:${value.revision}", value.json())
        db.insertWithOnConflict("concerns", null, ContentValues().apply {
            put("id", value.id); put("revision", value.revision); put("payload", encrypted); put("updated_at", value.updatedAt)
            put("metric_key", metricKey(value.metric)); put("open", if (value.open) 1 else 0); put("stage", value.stage.name)
            put("priority", HealthCarePriority.rank(value.assessment))
            if (value.nextDue == null) putNull("due_at") else put("due_at", value.nextDue)
        }, SQLiteDatabase.CONFLICT_REPLACE)
        db.insertOrThrow("history", null, ContentValues().apply {
            put("concern_id", value.id); put("revision", value.revision)
            put("payload", pack("history", "${value.id}:${value.revision}", JSONObject().put("event", event).put("concern", value.json())))
        })
        if (!HealthCareResearchPolicy.eligible(value)) researchAuthorization(value.id)?.takeIf { it.active }?.let {
            revokeResearchInternal(value.id, it.id, value.updatedAt)
        }
        reminders(value.id).filter { reminder ->
            val action = value.actions.firstOrNull { it.id == reminder.actionId }
            action == null || action.state != HealthCareActionState.CONFIRMED ||
                value.stage in setOf(HealthCareStage.PAUSED, HealthCareStage.CLOSED) ||
                reminder.anchor != HealthCareFollowUpPolicy.anchor(value, action)
        }.forEach { writeReminder(it.copy(state = HealthCareReminderState.CANCELLED, updatedAt = value.updatedAt), false) }
        agendaRows().replace(value)
    }
    fun applyEvaluation(metric: HealthMetric, token: String, expectedSettings: String, expectedRevision: Int?,
        assessment: HealthCareAssessment?, now: Long, evaluationVersion: String = ""): HealthCareConcern? = transaction(true) {
        val settings = settings()
        if (!settings.enabled || settings.version != expectedSettings) throw HealthCareConflict()
        val prior = forMetric(metric)
        if (prior?.revision != expectedRevision) throw HealthCareConflict()
        if (evaluated(metric, evaluationVersion) == token) return@transaction prior
        val next = HealthCarePolicy.reconcile(prior, metric, assessment, token, now)
        if (next != null && next != prior) persist(next, "measurement_assessed")
        db.insertWithOnConflict("evaluations", null, ContentValues().apply {
            put("metric_key", metricKey(metric)); put("token", token)
            put("payload", pack("evaluation", "${metricKey(metric)}:$token", JSONObject().put("metric", metric.name).put("token", token)
                .put("assessment_version", evaluationVersion)))
        }, SQLiteDatabase.CONFLICT_REPLACE)
        next
    }
    fun update(id: String, expectedRevision: Int, event: String, change: (HealthCareConcern) -> HealthCareConcern): HealthCareConcern = transaction(true) {
        val before = concern(id) ?: throw HealthCareConflict()
        if (before.revision != expectedRevision) throw HealthCareConflict()
        val next = change(before)
        require(next.id == before.id && next.metric == before.metric && next.createdAt == before.createdAt && next.profileId == before.profileId)
        require(next.inputVersion == before.inputVersion && next.assessment == before.assessment && next.revision == before.revision)
        if (next == before) return@transaction before
        next.copy(revision = before.revision + 1, updatedAt = maxOf(before.updatedAt, next.updatedAt, System.currentTimeMillis())).also { persist(it, event) }
    }
    fun confirmContext(id: String, expectedRevision: Int, context: HealthCareContext) = update(id, expectedRevision, "context_confirmed") {
        require(context.record == it.assessment.record)
        if (it.context != context) db.delete("evaluations", "metric_key=?", arrayOf(metricKey(it.metric)))
        it.copy(context = context)
    }
    fun questions(issue: HealthCareConcern, after: String = "", limit: Int = 30) = questionRows().page(issue, after, limit)
    fun question(id: String) = questionRows().get(id)
    fun answers(issue: HealthCareConcern, after: String = "", limit: Int = 30) = answerRows().page(issue, after, limit)
    fun answer(id: String) = answerRows().get(id)
    fun proposeAnswer(grant: HealthCareDiscussionGrant, questionId: String, expectedQuestion: Int,
        source: AgentTranscriptEntry, quote: String, answer: String, now: Long): HealthCareAnswerDraft = transaction(true) {
        val issue = concern(grant.concernId) ?: throw HealthCareConflict()
        val question = question(questionId) ?: throw HealthCareConflict()
        if (discussionGrant(grant.turnId) != grant || discussion(grant.conversationId) != issue.id ||
            issue.revision != grant.revision || issue.profileLink != grant.profileLink ||
            !settings().enabled || settings().version != grant.settingsVersion ||
            issue.stage in setOf(HealthCareStage.PAUSED, HealthCareStage.CLOSED) ||
            question.concernId != issue.id || question.scope != HealthCareQuestionPolicy.scope(issue) ||
            question.revision != expectedQuestion || !HealthCareAnswerPolicy.userSource(grant, source, quote)) throw HealthCareConflict()
        require(answer.isNotBlank() && answer.length <= 2000)
        answerRows().propose(grant, issue, question, source, quote, answer.trim(), now)
    }
    fun reviewAnswer(id: String, accept: Boolean, answer: String, privacy: HealthPrivacyPolicy,
        source: AgentTranscriptEntry?, now: Long): HealthCareAnswerDraft = transaction(true) {
        val draft = answerRows().get(id) ?: throw HealthCareConflict()
        val issue = concern(draft.grant.concernId) ?: throw HealthCareConflict()
        if (!privacy.metrics || !privacy.profile || draft.scope != HealthCareQuestionPolicy.scope(issue)) throw HealthCareConflict()
        if (draft.state != HealthCareAnswerState.PENDING) return@transaction draft
        if (accept) {
            val question = question(draft.questionId) ?: throw HealthCareConflict()
            if (!HealthCareAnswerPolicy.current(draft, issue, question, settings(), privacy) ||
                discussion(draft.grant.conversationId) != issue.id || source?.id != draft.sourceId ||
                !HealthCareAnswerPolicy.userSource(draft.grant, source, draft.quote)) throw HealthCareConflict()
            require(answer.isNotBlank() && answer.length <= 2000)
            val next = questionRows().review(issue, question.id, question.revision, HealthCareQuestionState.ANSWERED, answer, now)
            if (next != question) persist(issue.copy(revision = issue.revision + 1, updatedAt = maxOf(now, issue.updatedAt),
                questionVersion = UUID.randomUUID().toString(), stage = if (issue.stage in setOf(HealthCareStage.PAUSED, HealthCareStage.CLOSED))
                    issue.stage else HealthCareStage.REASSESS), "answer_draft_accepted")
        }
        draft.copy(state = if (accept) HealthCareAnswerState.ACCEPTED else HealthCareAnswerState.DISMISSED,
            reviewedAt = maxOf(now, draft.createdAt), reviewedAnswer = if (accept) answer.trim() else "").also { answerRows().write(it) }
    }
    fun proposeQuestion(grant: HealthCareDiscussionGrant, key: String, question: String, purpose: String, now: Long): HealthCareQuestion = transaction(true) {
        val issue = concern(grant.concernId) ?: throw HealthCareConflict()
        if (!grant.questionsShared || discussionGrant(grant.turnId) != grant || discussion(grant.conversationId) != issue.id || issue.revision != grant.revision ||
            issue.profileLink != grant.profileLink || !settings().enabled || settings().version != grant.settingsVersion ||
            !researchGrantCurrent(grant) || issue.stage in setOf(HealthCareStage.CLOSED, HealthCareStage.PAUSED)) throw HealthCareConflict()
        questionRows().propose(issue, grant, key, question, purpose, now)
    }
    fun reviewQuestion(id: String, expectedRevision: Int, questionId: String, expectedQuestionRevision: Int,
        state: HealthCareQuestionState, answer: String, now: Long): HealthCareQuestion = transaction(true) {
        val issue = concern(id) ?: throw HealthCareConflict()
        if (issue.revision != expectedRevision || !settings().enabled) throw HealthCareConflict()
        val before = questionRows().get(questionId) ?: throw HealthCareConflict()
        val next = questionRows().review(issue, questionId, expectedQuestionRevision, state, answer, now)
        if (next != before) persist(issue.copy(revision = issue.revision + 1, updatedAt = maxOf(now, issue.updatedAt),
            questionVersion = UUID.randomUUID().toString(), stage = if (issue.stage in setOf(HealthCareStage.CLOSED, HealthCareStage.PAUSED))
                issue.stage else HealthCareStage.REASSESS), "question_reviewed")
        next
    }
    fun page(after: HealthCareCursor? = null, includeClosed: Boolean = false, limit: Int = 30, includePaused: Boolean = true): HealthCarePage {
        require(limit in 1..30)
        val args = arrayListOf<String>()
        val where = arrayListOf(if (includeClosed) "1=1" else "open=1")
        if (!includePaused) where += "stage!='PAUSED'"
        if (after != null) {
            require(after.priority in 0..1)
            where += "(priority<? OR (priority=? AND (updated_at<? OR (updated_at=? AND id<?))))"
            args += listOf(after.priority.toString(), after.priority.toString(), after.updatedAt.toString(), after.updatedAt.toString(), after.id)
        }
        val items = db.rawQuery("SELECT $COLUMNS FROM concerns WHERE ${where.joinToString(" AND ")} ORDER BY priority DESC,updated_at DESC,id DESC LIMIT ${limit + 1}",
            args.toTypedArray()).use { rows -> buildList { while (rows.moveToNext()) add(decode(rows)) } }
        val visible = items.take(limit)
        return HealthCarePage(visible, if (items.size > limit) visible.last().let {
            HealthCareCursor(it.updatedAt, it.id, HealthCarePriority.rank(it.assessment))
        } else null)
    }
    fun revision(id: String, revision: Int): HealthCareConcern? {
        require(HealthProfilePolicy.uuid(id) && revision > 0)
        return db.rawQuery("SELECT payload FROM history WHERE concern_id=? AND revision=?", arrayOf(id, revision.toString())).use {
            if (!it.moveToFirst()) null else HealthCareConcern.from(unpack("history", "$id:$revision", it.getBlob(0)).getJSONObject("concern"))
                .also { value -> check(value.id == id && value.revision == revision) }
        }
    }
    fun history(id: String, beforeRevision: Int = Int.MAX_VALUE): List<HealthCareConcern> {
        require(HealthProfilePolicy.uuid(id))
        return db.rawQuery("SELECT revision,payload FROM history WHERE concern_id=? AND revision<? ORDER BY revision DESC LIMIT 30",
            arrayOf(id, beforeRevision.toString())).use { rows -> buildList {
            while (rows.moveToNext()) {
                val revision = rows.getInt(0)
                add(HealthCareConcern.from(unpack("history", "$id:$revision", rows.getBlob(1)).getJSONObject("concern")).also {
                    check(it.id == id && it.revision == revision)
                })
            }
        } }
    }
    fun due(now: Long): List<HealthCareConcern> = db.rawQuery("SELECT $COLUMNS FROM concerns WHERE open=1 AND due_at<=? ORDER BY due_at,id LIMIT 30",
        arrayOf(now.toString())).use { rows -> buildList { while (rows.moveToNext()) add(decode(rows)) } }
    fun nextDue(): Long? = db.rawQuery("SELECT MIN(due_at) FROM concerns WHERE open=1", null).use {
        it.moveToFirst(); if (it.isNull(0)) null else it.getLong(0)
    }
    private fun discussionBinding(conversationId: String): JSONObject? = db.rawQuery(
        "SELECT payload FROM discussions WHERE conversation_id=?", arrayOf(conversationId)
    ).use { row ->
        if (!row.moveToFirst()) null else unpack("discussion", conversationId, row.getBlob(0)).also {
            check(it.getString("conversation") == conversationId)
        }
    }
    fun discussion(conversationId: String): String? = discussionBinding(conversationId)?.let {
        val id = it.getString("concern")
        val boundScope = it.optJSONObject("profile_scope")?.let(HealthCareProfileScope::from)
        val issue = concern(id)
        if (issue != null && issue.profileLink?.scope != boundScope) null else id
    }
    fun bindDiscussion(id: String, expectedRevision: Int, conversationId: String): HealthCareConcern = transaction(true) {
        require(HealthProfilePolicy.uuid(conversationId))
        val before = concern(id) ?: throw HealthCareConflict()
        if (before.revision != expectedRevision) throw HealthCareConflict()
        discussionBinding(conversationId)?.let {
            if (it.getString("concern") != id || it.optJSONObject("profile_scope")?.let(HealthCareProfileScope::from) != before.profileLink?.scope)
                throw HealthCareConflict()
        }
        db.insertWithOnConflict("discussions", null, ContentValues().apply {
            put("conversation_id", conversationId)
            put("payload", pack("discussion", conversationId, JSONObject().put("conversation", conversationId).put("concern", id)
                .apply { before.profileLink?.scope?.let { put("profile_scope", it.json()) } }))
        }, SQLiteDatabase.CONFLICT_IGNORE)
        before.copy(conversationId = conversationId, revision = before.revision + 1,
            updatedAt = maxOf(before.updatedAt, System.currentTimeMillis())).also { persist(it, "discussion_bound") }
    }
    fun approveDiscussion(grant: HealthCareDiscussionGrant) = transaction {
        val current = concern(grant.concernId) ?: throw HealthCareConflict()
        if (discussion(grant.conversationId) != current.id || current.revision != grant.revision || current.profileLink != grant.profileLink ||
            !HealthCareDiscussionPolicy.questionScopeCurrent(grant, current) ||
            !settings().enabled || settings().version != grant.settingsVersion || !researchGrantCurrent(grant)) throw HealthCareConflict()
        discussionGrant(grant.turnId)?.let {
            if (it != grant) throw HealthCareConflict()
            return@transaction
        }
        db.insertOrThrow("discussion_grants", null, ContentValues().apply {
            put("turn_id", grant.turnId)
            put("payload", pack("discussion_grant", grant.turnId, grant.json()))
        })
        Unit
    }
    fun discussionGrant(turnId: String): HealthCareDiscussionGrant? = db.rawQuery(
        "SELECT payload FROM discussion_grants WHERE turn_id=?", arrayOf(turnId)
    ).use { row -> if (!row.moveToFirst()) null else
        HealthCareDiscussionGrant.from(unpack("discussion_grant", turnId, row.getBlob(0))).also { check(it.turnId == turnId) } }
    fun researchAuthorization(concernId: String): HealthCareResearchAuthorization? = db.rawQuery(
        "SELECT id,payload FROM research_authorizations WHERE concern_id=?", arrayOf(concernId)).use { row ->
        if (!row.moveToFirst()) null else HealthCareResearchAuthorization.from(unpack("research_authorization", concernId, row.getBlob(1))).also {
            check(it.id == row.getString(0) && it.scope.concernId == concernId)
        }
    }
    fun researchAuthorizations(after: String = ""): List<HealthCareResearchAuthorization> = db.rawQuery(
        "SELECT concern_id,id,payload FROM research_authorizations WHERE concern_id>? ORDER BY concern_id LIMIT 30", arrayOf(after)).use { rows -> buildList {
        while (rows.moveToNext()) add(HealthCareResearchAuthorization.from(unpack("research_authorization", rows.getString(0), rows.getBlob(2))).also {
            check(it.scope.concernId == rows.getString(0) && it.id == rows.getString(1))
        })
    } }
    private fun writeResearchAuthorization(value: HealthCareResearchAuthorization) {
        db.insertWithOnConflict("research_authorizations", null, ContentValues().apply {
            put("concern_id", value.scope.concernId); put("id", value.id)
            put("payload", pack("research_authorization", value.scope.concernId, value.json()))
        }, SQLiteDatabase.CONFLICT_REPLACE)
    }
    fun authorizeResearch(value: HealthCareResearchAuthorization, expectedAuthorization: String?) = transaction(true) {
        val scope = value.scope
        val issue = concern(scope.concernId) ?: throw HealthCareConflict()
        if (!value.active || researchAuthorization(issue.id)?.id != expectedAuthorization ||
            !HealthCareDiscussionPolicy.questionScopeCurrent(scope, issue) ||
            !settings().enabled || settings().version != scope.settingsVersion || issue.revision != scope.revision ||
            discussion(scope.conversationId) != issue.id || issue.conversationId != scope.conversationId ||
            !HealthCareResearchPolicy.eligible(issue) || issue.profileLink != scope.profileLink) throw HealthCareConflict()
        researchAuthorization(issue.id)?.let { revokeResearchInternal(issue.id, it.id, System.currentTimeMillis()) }
        writeResearchAuthorization(value)
    }
    fun revokeResearch(concernId: String, expectedId: String, now: Long) = transaction(true) {
        revokeResearchInternal(concernId, expectedId, now)
    }
    private fun revokeResearchInternal(concernId: String, expectedId: String, now: Long) {
        val value = researchAuthorization(concernId) ?: return
        if (value.id != expectedId) throw HealthCareConflict()
        if (value.active) writeResearchAuthorization(value.copy(revokedAt = maxOf(1, now)))
        var after = ""
        while (true) {
            val page = researchJobs(concernId, after, unfinishedOnly = true)
            if (page.isEmpty()) break
            page.forEach { writeResearchJob(it.copy(state = HealthCareResearchState.CANCELLED, cancellationPending = true)) }
            after = page.last().turnId
        }
    }
    private fun decodeResearchJob(row: Cursor): HealthCareResearchJob = HealthCareResearchJob.from(
        unpack("research_job", row.getString(0), row.getBlob(5))).also {
        check(it.turnId == row.getString(0) && it.concernId == row.getString(1) && it.authorizationId == row.getString(2) &&
            it.trigger == row.getString(3) && it.state.name == row.getString(4) && it.createdAt == row.getLong(6) &&
            it.cancellationPending == (row.getInt(7) == 1))
    }
    fun researchJob(turnId: String): HealthCareResearchJob? = db.rawQuery("SELECT $RESEARCH_COLUMNS FROM research_jobs WHERE turn_id=?",
        arrayOf(turnId)).use { if (it.moveToFirst()) decodeResearchJob(it) else null }
    fun latestResearchJob(concernId: String): HealthCareResearchJob? = db.rawQuery(
        "SELECT $RESEARCH_COLUMNS FROM research_jobs WHERE concern_id=? ORDER BY created_at DESC,turn_id DESC LIMIT 1",
        arrayOf(concernId)).use { if (it.moveToFirst()) decodeResearchJob(it) else null }
    fun previousCompletedResearch(job: HealthCareResearchJob): HealthCareResearchJob? = db.rawQuery(
        "SELECT $RESEARCH_COLUMNS FROM research_jobs WHERE concern_id=? AND created_at<=? AND turn_id!=? AND state='COMPLETED' " +
            "ORDER BY created_at DESC,turn_id DESC LIMIT 1", arrayOf(job.concernId, job.createdAt.toString(), job.turnId)).use {
        if (it.moveToFirst()) decodeResearchJob(it).takeIf { prior -> prior.conversationId == job.conversationId } else null
    }
    fun priorResearchEvidence(job: HealthCareResearchJob, grant: HealthCareDiscussionGrant): List<HealthCareEvidence> =
        db.rawQuery("SELECT e.id,e.turn_id,e.payload FROM research_jobs r JOIN evidence_reads e " +
            "ON e.concern_id=r.concern_id AND e.turn_id=r.turn_id WHERE r.concern_id=? AND r.created_at<=? " +
            "AND r.turn_id!=? AND r.state='COMPLETED' ORDER BY r.created_at DESC,r.turn_id DESC,e.id LIMIT 8",
            arrayOf(job.concernId, job.createdAt.toString(), job.turnId)).use { rows ->
            buildList {
                while (rows.moveToNext()) {
                    val id = rows.getString(0)
                    val value = HealthCareEvidence.from(unpack("evidence", id, rows.getBlob(2)))
                    check(value.id == id && value.grant.concernId == job.concernId && value.grant.turnId == rows.getString(1))
                    if (HealthCareResearchHandoff.reusable(value, grant)) add(value)
                }
            }
        }
    fun pendingResearchCancellations(after: String = ""): List<HealthCareResearchJob> = db.rawQuery(
        "SELECT $RESEARCH_COLUMNS FROM research_jobs WHERE cancel_pending=1 AND turn_id>? ORDER BY turn_id LIMIT 30", arrayOf(after)).use { rows ->
        buildList { while (rows.moveToNext()) add(decodeResearchJob(rows)) }
    }
    fun acknowledgeResearchCancellation(expected: HealthCareResearchJob) = transaction {
        if (researchJob(expected.turnId) != expected) throw HealthCareConflict()
        writeResearchJob(expected.copy(cancellationPending = false))
    }
    fun researchJobs(concernId: String, after: String = "", unfinishedOnly: Boolean = false): List<HealthCareResearchJob> = db.rawQuery(
        "SELECT $RESEARCH_COLUMNS FROM research_jobs WHERE concern_id=? AND turn_id>?" +
            (if (unfinishedOnly) " AND state IN ('QUEUED','DISPATCHED')" else "") + " ORDER BY turn_id LIMIT 30", arrayOf(concernId, after)).use { rows ->
        buildList { while (rows.moveToNext()) add(decodeResearchJob(rows)) }
    }
    private fun writeResearchJob(value: HealthCareResearchJob) {
        db.insertWithOnConflict("research_jobs", null, ContentValues().apply {
            put("turn_id", value.turnId); put("concern_id", value.concernId); put("authorization_id", value.authorizationId)
            put("trigger", value.trigger); put("state", value.state.name); put("payload", pack("research_job", value.turnId, value.json()))
            put("created_at", value.createdAt); put("cancel_pending", if (value.cancellationPending) 1 else 0)
        }, SQLiteDatabase.CONFLICT_REPLACE)
    }
    fun queueResearch(authorizationId: String, concernId: String, now: Long): HealthCareResearchJob = transaction {
        val authorization = researchAuthorization(concernId) ?: throw HealthCareConflict()
        val issue = concern(concernId) ?: throw HealthCareConflict()
        if (authorization.id != authorizationId || !authorization.active || !HealthCareResearchPolicy.eligible(issue) ||
            issue.conversationId != authorization.scope.conversationId || !settings().enabled ||
            settings().version != authorization.scope.settingsVersion || issue.profileLink?.scope != authorization.scope.profileLink?.scope) throw HealthCareConflict()
        val trigger = HealthCareResearchPolicy.trigger(issue, now)
        db.rawQuery("SELECT $RESEARCH_COLUMNS FROM research_jobs WHERE authorization_id=? AND trigger=?",
            arrayOf(authorizationId, trigger)).use { if (it.moveToFirst()) {
                val existing = decodeResearchJob(it)
                return@transaction if (existing.state == HealthCareResearchState.QUEUED && existing.revision != issue.revision &&
                    discussionGrant(existing.turnId) == null) existing.copy(revision = issue.revision).also(::writeResearchJob) else existing
            } }
        HealthCareResearchJob(UUID.randomUUID().toString(), authorizationId, concernId, issue.conversationId, trigger,
            issue.revision, now).also(::writeResearchJob)
    }
    fun updateResearchJob(expected: HealthCareResearchJob, state: HealthCareResearchState, detail: String = expected.detail): HealthCareResearchJob = transaction(true) {
        if (researchJob(expected.turnId) != expected || !HealthCareResearchPolicy.transition(expected.state, state) ||
            expected.terminal && detail != expected.detail) throw HealthCareConflict()
        expected.copy(state = state, detail = detail.take(2000), cancellationPending = expected.cancellationPending ||
            state in setOf(HealthCareResearchState.CANCELLED, HealthCareResearchState.SUPERSEDED)).also(::writeResearchJob)
    }
    fun researchGrantCurrent(grant: HealthCareDiscussionGrant): Boolean {
        if (grant.researchAuthorizationId.isEmpty()) return true
        val authorization = researchAuthorization(grant.concernId) ?: return false
        val job = researchJob(grant.turnId) ?: return false
        val issue = concern(grant.concernId) ?: return false
        return authorization.permits(grant) && HealthCareDiscussionPolicy.questionScopeCurrent(grant, issue) && !job.terminal && job.authorizationId == authorization.id &&
            job.concernId == grant.concernId && job.conversationId == grant.conversationId && job.revision == grant.revision &&
            job.trigger == HealthCareResearchPolicy.trigger(issue, System.currentTimeMillis())
    }
    private fun decodePlan(row: Cursor): HealthCarePlan = HealthCarePlan.from(unpack("plan", row.getString(0), row.getBlob(4))).also {
        check(it.id == row.getString(0) && it.grant.concernId == row.getString(1) && it.createdAt == row.getLong(2) && it.state.name == row.getString(3))
    }
    fun plan(id: String): HealthCarePlan? = db.rawQuery("SELECT id,concern_id,created_at,state,payload FROM plans WHERE id=?", arrayOf(id)).use {
        if (it.moveToFirst()) decodePlan(it) else null
    }
    fun pendingPlans(id: String): List<HealthCarePlan> = db.rawQuery(
        "SELECT id,concern_id,created_at,state,payload FROM plans WHERE concern_id=? AND state='PENDING' ORDER BY created_at DESC,id DESC LIMIT 30",
        arrayOf(id)).use { rows -> buildList { while (rows.moveToNext()) add(decodePlan(rows)) } }
    fun hasRecordedPlan(id: String, at: Long): Boolean = db.rawQuery(
        "SELECT 1 FROM plans WHERE concern_id=? AND created_at<=? LIMIT 1", arrayOf(id, at.toString())).use { it.moveToFirst() }
    private fun persistPlan(value: HealthCarePlan) {
        db.insertWithOnConflict("plans", null, ContentValues().apply {
            put("id", value.id); put("concern_id", value.grant.concernId); put("created_at", value.createdAt)
            put("state", value.state.name); put("payload", pack("plan", value.id, value.json()))
        }, SQLiteDatabase.CONFLICT_REPLACE)
    }
    fun evidence(id: String): HealthCareEvidence? = db.rawQuery("SELECT concern_id,turn_id,payload FROM evidence_reads WHERE id=?",
        arrayOf(id)).use { row -> if (!row.moveToFirst()) null else HealthCareEvidence.from(unpack("evidence", id, row.getBlob(2))).also {
            check(it.id == id && it.grant.concernId == row.getString(0) && it.grant.turnId == row.getString(1))
        } }
    fun recordEvidence(values: List<HealthCareEvidence>) = transaction {
        values.forEach { value ->
            val grant = value.grant
            val issue = concern(grant.concernId) ?: throw HealthCareConflict()
            if (discussionGrant(grant.turnId) != grant || !researchGrantCurrent(grant) || discussion(grant.conversationId) != issue.id || issue.revision != grant.revision ||
                !settings().enabled || settings().version != grant.settingsVersion ||
                issue.stage in setOf(HealthCareStage.PAUSED, HealthCareStage.CLOSED)) throw HealthCareConflict()
            val prior = evidence(value.id)
            if (prior != null) {
                if (prior.copy(observedAt = value.observedAt) != value) throw HealthCareConflict()
            } else db.insertOrThrow("evidence_reads", null, ContentValues().apply {
                put("id", value.id); put("concern_id", grant.concernId); put("turn_id", grant.turnId)
                put("payload", pack("evidence", value.id, value.json()))
            })
        }
    }
    fun proposePlan(value: HealthCarePlan): HealthCarePlan = transaction(true) {
        val grant = value.grant
        if (discussionGrant(grant.turnId) != grant || !researchGrantCurrent(grant) || discussion(grant.conversationId) != grant.concernId) throw HealthCareConflict()
        val issue = concern(grant.concernId) ?: throw HealthCareConflict()
        if (issue.revision != grant.revision || issue.inputVersion != value.inputVersion || !settings().enabled ||
            settings().version != grant.settingsVersion || value.state != HealthCarePlanState.PENDING) throw HealthCareConflict()
        plan(value.id)?.let { prior ->
            if (prior.requestHash != value.requestHash || prior.grant != grant) throw HealthCareConflict()
            return@transaction prior
        }
        val grounded = value.copy(sources = value.sources.map { source ->
            val receipt = evidence(source.evidenceId) ?: throw HealthCareEvidenceMissing()
            if (!HealthCareEvidencePolicy.supports(receipt, grant, source.url, source.quote)) throw HealthCareEvidenceMissing()
            source.copy(evidence = receipt)
        })
        persistPlan(grounded)
        grounded
    }
    fun resolvePlan(id: String, selected: Set<String>, expectedRevision: Int, privacy: HealthPrivacyPolicy,
        sourceVersion: String, now: Long, acceptTarget: Boolean = false, acceptMaintenance: Boolean = false): HealthCareConcern = transaction(true) {
        val proposed = plan(id) ?: throw HealthCareConflict()
        val issue = concern(proposed.grant.concernId) ?: throw HealthCareConflict()
        if (proposed.state != HealthCarePlanState.PENDING || issue.revision != expectedRevision ||
            !HealthCarePlanPolicy.current(proposed, issue, settings(), privacy, sourceVersion)) throw HealthCareConflict()
        if (proposed.sources.any { source -> source.evidence?.let {
            HealthCareEvidencePolicy.supports(it, proposed.grant, source.url, source.quote)
        } != true }) throw HealthCareEvidenceMissing()
        val next = HealthCarePlanPolicy.accept(proposed, issue, selected, now, acceptTarget, acceptMaintenance)
            .copy(revision = issue.revision + 1, updatedAt = maxOf(issue.updatedAt, now))
        persist(next, "agent_plan_confirmed")
        persistPlan(proposed.copy(state = HealthCarePlanState.ACCEPTED, selected = selected, resolvedAt = now,
            targetSelected = acceptTarget, maintenanceSelected = acceptMaintenance))
        next
    }
    fun reassessMaintenance(id: String, expectedRevision: Int, now: Long): HealthCareConcern = update(id, expectedRevision, "maintenance_review_due") {
        if (HealthCareMaintenancePolicy.needsReassessment(it, now)) it.copy(stage = HealthCareStage.REASSESS) else it
    }
    fun nextMaintenanceReview(): Long? = db.rawQuery("SELECT MIN(due_at) FROM concerns WHERE stage='MAINTENANCE'", null).use {
        it.moveToFirst(); if (it.isNull(0)) null else it.getLong(0)
    }
    fun revokeTarget(id: String, expectedRevision: Int, privacy: HealthPrivacyPolicy): HealthCareConcern = update(id, expectedRevision, "individual_target_revoked") {
        if (!privacy.metrics || !privacy.profile) throw HealthCareConflict()
        HealthCareTargetPolicy.revoke(it)
    }
    fun dismissPlan(id: String, now: Long) = transaction(true) {
        val proposed = plan(id) ?: throw HealthCareConflict()
        if (proposed.state == HealthCarePlanState.PENDING) persistPlan(proposed.copy(state = HealthCarePlanState.DISMISSED, resolvedAt = now))
    }
    private fun decodeReminder(row: Cursor): HealthCareReminder = HealthCareReminder.from(
        unpack("reminder", row.getString(0), row.getBlob(5))).also {
        check(it.actionId == row.getString(0) && it.concernId == row.getString(1) && it.token == row.getString(2) &&
            it.dueAt == row.getLong(3) && it.state.name == row.getString(4))
    }
    fun reminder(actionId: String): HealthCareReminder? = db.rawQuery(
        "SELECT $REMINDER_COLUMNS FROM action_reminders WHERE action_id=?", arrayOf(actionId)
    ).use { if (it.moveToFirst()) decodeReminder(it) else null }
    fun reminders(concernId: String): List<HealthCareReminder> = db.rawQuery(
        "SELECT $REMINDER_COLUMNS FROM action_reminders WHERE concern_id=? ORDER BY due,action_id LIMIT 30", arrayOf(concernId)
    ).use { rows -> buildList { while (rows.moveToNext()) add(decodeReminder(rows)) } }
    private fun writeReminder(value: HealthCareReminder, syncAgenda: Boolean = true) {
        db.insertWithOnConflict("action_reminders", null, ContentValues().apply {
            put("action_id", value.actionId); put("concern_id", value.concernId); put("token", value.token)
            put("due", value.dueAt); put("state", value.state.name); put("payload", pack("reminder", value.actionId, value.json()))
        }, SQLiteDatabase.CONFLICT_REPLACE)
        if (syncAgenda) {
            val issue = try { concern(value.concernId) } catch (error: Exception) {
                // Corruption must not prevent cancellation of an already posted reminder.
                if (value.state != HealthCareReminderState.CANCELLED) throw error
                null
            }
            if (issue == null) agendaRows().remove(value.concernId) else agendaRows().replace(issue)
        }
    }
    fun scheduleReminder(concernId: String, actionId: String, expectedRevision: Int, expectedToken: String?,
        privacy: HealthPrivacyPolicy, sourceVersion: String, at: Long, now: Long,
        instructionAvailable: (HealthCareInstructionActionRef) -> Boolean = { false }): HealthCareReminder = transaction(true) {
        val issue = concern(concernId) ?: throw HealthCareConflict()
        if (issue.revision != expectedRevision || reminder(actionId)?.token != expectedToken) throw HealthCareConflict()
        val action = issue.actions.firstOrNull { it.id == actionId } ?: throw HealthCareConflict()
        if (!instructionCurrent(issue, action) || action.instruction?.let { !instructionAvailable(it) } == true) throw HealthCareConflict()
        HealthCareFollowUpPolicy.schedule(issue, action, settings(), privacy, sourceVersion, at, now).also { writeReminder(it) }
    }
    fun cancelReminder(actionId: String, expectedToken: String, now: Long) = transaction(true) {
        val value = reminder(actionId) ?: return@transaction
        if (value.token != expectedToken) throw HealthCareConflict()
        if (value.state != HealthCareReminderState.CANCELLED) writeReminder(value.copy(state = HealthCareReminderState.CANCELLED, updatedAt = now))
    }
    fun markReminderDelivered(actionId: String, expectedToken: String, now: Long) = transaction(true) {
        val value = reminder(actionId) ?: throw HealthCareConflict()
        if (value.token != expectedToken || value.state != HealthCareReminderState.SCHEDULED) throw HealthCareConflict()
        writeReminder(value.copy(state = HealthCareReminderState.DELIVERED, updatedAt = now))
    }
    fun cancelReminders(now: Long, keepPrivacyVersion: String? = null): Int = transaction {
        invalidateReminders(now, keepPrivacyVersion)
    }.also { if (it > 0) app.contentResolver.notifyChange(changes(app, name), null) }
    private fun invalidateReminders(now: Long, keepPrivacyVersion: String?): Int {
        var changed = 0
        var after = ""
        while (true) {
            val page = db.rawQuery("SELECT $REMINDER_COLUMNS FROM action_reminders WHERE action_id>? AND state!='CANCELLED' ORDER BY action_id LIMIT 30",
                arrayOf(after)).use { rows -> buildList { while (rows.moveToNext()) add(decodeReminder(rows)) } }
            if (page.isEmpty()) break
            page.filter { keepPrivacyVersion == null || it.privacyVersion != keepPrivacyVersion }.forEach {
                writeReminder(it.copy(state = HealthCareReminderState.CANCELLED, updatedAt = now))
                changed++
            }
            after = page.last().actionId
        }
        return changed
    }
    fun dueReminders(now: Long): List<HealthCareReminder> = db.rawQuery(
        "SELECT $REMINDER_COLUMNS FROM action_reminders WHERE state='SCHEDULED' AND due<=? ORDER BY due,action_id LIMIT 30",
        arrayOf(now.toString())).use { rows -> buildList { while (rows.moveToNext()) add(decodeReminder(rows)) } }
    fun nextReminder(): Long? = db.rawQuery("SELECT MIN(due) FROM action_reminders WHERE state='SCHEDULED'", null).use {
        it.moveToFirst(); if (it.isNull(0)) null else it.getLong(0)
    }
    fun recordActionFeedback(id: String, expectedRevision: Int, actionId: String, kind: HealthCareFeedbackKind,
        note: String, operationId: String, now: Long): HealthCareFeedbackReceipt = transaction(true) {
        recordFeedback(id, expectedRevision, actionId, kind, note, operationId, now)
    }
    private fun recordFeedback(id: String, expectedRevision: Int, actionId: String, kind: HealthCareFeedbackKind,
        note: String, operationId: String, now: Long): HealthCareFeedbackReceipt {
        require(HealthProfilePolicy.uuid(operationId) && note.isNotBlank() && note.trim().length <= 2000 && now > 0)
        feedbackRows().get(operationId)?.let {
            if (it.concernId != id || it.actionId != actionId || it.revision != expectedRevision + 1 ||
                it.feedback.kind != kind || it.feedback.note != note.trim()) throw HealthCareConflict()
            return it
        }
        val issue = concern(id) ?: throw HealthCareConflict()
        if (issue.revision != expectedRevision) throw HealthCareConflict()
        val action = issue.actions.firstOrNull { it.id == actionId } ?: throw HealthCareConflict()
        val value = HealthCareFeedback(operationId, kind, note.trim(), now, action.basis, HealthCareQuestionPolicy.scope(issue))
        val next = HealthCareFeedbackPolicy.apply(issue, actionId, value).copy(revision = issue.revision + 1)
        persist(next, "action_feedback_recorded")
        return HealthCareFeedbackReceipt(id, actionId, next.revision, action.description, value).also { feedbackRows().write(it) }
    }
    fun finishAction(id: String, expectedRevision: Int, actionId: String, outcome: String, now: Long): HealthCareConcern = transaction(true) {
        recordFeedback(id, expectedRevision, actionId, HealthCareFeedbackKind.COMPLETED, outcome, UUID.randomUUID().toString(), now)
        concern(id) ?: throw HealthCareConflict()
    }
    fun saveEncounter(id: String, expectedRevision: Int, encounterId: String, expectedEncounterRevision: Int?,
        details: HealthCareEncounterDraft, operationId: String, now: Long): HealthCareEncounterReceipt = transaction(true) {
        require(HealthProfilePolicy.uuid(id) && HealthProfilePolicy.uuid(encounterId) && HealthProfilePolicy.uuid(operationId) && now > 0)
        encounterRows().receipt(operationId)?.let {
            if (it.encounter.concernId != id || it.encounter.id != encounterId || it.expectedConcernRevision != expectedRevision ||
                it.expectedEncounterRevision != expectedEncounterRevision || it.encounter.details != details) throw HealthCareConflict()
            return@transaction it
        }
        val issue = concern(id) ?: throw HealthCareConflict()
        val before = encounterRows().get(encounterId)
        if (issue.revision != expectedRevision || before?.revision != expectedEncounterRevision ||
            (before != null && before.concernId != id)) throw HealthCareConflict()
        val value = HealthCareEncounterPolicy.apply(issue, before, encounterId, details, now)
        val receipt = HealthCareEncounterReceipt(operationId, expectedRevision, expectedEncounterRevision, value)
        persist(issue.copy(revision = value.revision, updatedAt = value.updatedAt), "encounter_recorded")
        encounterRows().write(receipt)
        receipt
    }
    fun deleteEncounter(id: String, expectedRevision: Int, encounterId: String, expectedEncounterRevision: Int, now: Long) = transaction(true) {
        require(now > 0 && expectedRevision in 1 until Int.MAX_VALUE)
        val issue = concern(id) ?: throw HealthCareConflict()
        val before = encounterRows().get(encounterId) ?: throw HealthCareConflict()
        if (issue.revision != expectedRevision || before.concernId != id || before.revision != expectedEncounterRevision) throw HealthCareConflict()
        persist(HealthCareInstructionActionPolicy.invalidate(issue) { it.encounterId == encounterId }
            .copy(revision = issue.revision + 1, updatedAt = maxOf(now, issue.updatedAt)), "encounter_deleted")
        encounterRows().delete(id, encounterId)
        documentRows().purge(id, encounterId)
        instructionRows().purge(id, encounterId)
        Unit
    }
    fun linkEncounterDocument(id: String, expectedRevision: Int, encounterId: String, expectedEncounterRevision: Int,
        source: HealthCareDocumentRef, operationId: String, now: Long): HealthCareDocumentLink = transaction(true) {
        require(listOf(id, encounterId, operationId).all(HealthProfilePolicy::uuid) && now > 0)
        documentRows().get(operationId)?.let {
            if (it.concernId != id || it.encounterId != encounterId || it.expectedConcern != expectedRevision ||
                it.expectedEncounter != expectedEncounterRevision || it.source != source) throw HealthCareConflict()
            return@transaction it
        }
        val issue = concern(id) ?: throw HealthCareConflict()
        val visit = encounterRows().get(encounterId) ?: throw HealthCareConflict()
        if (issue.revision != expectedRevision || visit.concernId != id || visit.revision != expectedEncounterRevision) throw HealthCareConflict()
        documentRows().matching(encounterId, source)?.let { return@transaction it }
        val link = HealthCareDocumentLink(operationId, id, encounterId, issue.revision + 1, issue.revision, visit.revision,
            source, maxOf(now, issue.updatedAt))
        persist(issue.copy(revision = link.revision, updatedAt = link.createdAt), "encounter_document_linked")
        documentRows().write(link)
        link
    }
    fun unlinkEncounterDocument(id: String, expectedRevision: Int, linkId: String, expectedLinkRevision: Int, now: Long) = transaction(true) {
        require(now > 0 && expectedRevision in 1 until Int.MAX_VALUE)
        val issue = concern(id) ?: throw HealthCareConflict()
        val link = documentRows().get(linkId) ?: throw HealthCareConflict()
        if (issue.revision != expectedRevision || link.concernId != id || link.revision != expectedLinkRevision) throw HealthCareConflict()
        if (instructionRows().hasSource(linkId)) throw HealthCareSourceInUse()
        persist(issue.copy(revision = issue.revision + 1, updatedAt = maxOf(now, issue.updatedAt)), "encounter_document_unlinked")
        documentRows().remove(linkId)
    }
    fun saveInstruction(id: String, expectedRevision: Int, encounterId: String, instructionId: String, expectedInstruction: Int?,
        source: HealthCareInstructionSource, draft: HealthCareInstructionDraft, operationId: String, now: Long): HealthCareInstructionReceipt = transaction(true) {
        require(listOf(id, encounterId, instructionId, operationId).all(HealthProfilePolicy::uuid) && now > 0)
        instructionRows().receipt(operationId)?.let {
            if (it.expectedConcern != expectedRevision || it.expectedInstruction != expectedInstruction || it.value.id != instructionId ||
                it.value.concernId != id || it.value.encounterId != encounterId || it.value.source != source || it.value.draft != draft) throw HealthCareConflict()
            return@transaction it
        }
        val issue = concern(id) ?: throw HealthCareConflict()
        val visit = encounterRows().get(encounterId) ?: throw HealthCareConflict()
        val link = documentRows().get(source.documentId) ?: throw HealthCareConflict()
        if (issue.revision != expectedRevision || visit.concernId != id || link.concernId != id || link.encounterId != encounterId ||
            link.source.copy(page = source.original.page, pageCount = source.original.pageCount) != source.original ||
            link.source.page != null && link.source != source.original) throw HealthCareConflict()
        val before = instructionRows().get(instructionId)
        if (before?.revision != expectedInstruction || before != null && (before.concernId != id || before.encounterId != encounterId || before.source != source))
            throw HealthCareConflict()
        val time = maxOf(now, issue.updatedAt)
        val value = HealthCareInstruction(instructionId, id, encounterId, Math.addExact(issue.revision, 1), source, draft,
            before?.createdAt ?: time, time)
        val receipt = HealthCareInstructionReceipt(operationId, issue.revision, before?.revision, value)
        persist(HealthCareInstructionActionPolicy.invalidate(issue) { it.instructionId == instructionId }
            .copy(revision = value.revision, updatedAt = time), "instruction_review_saved")
        instructionRows().write(receipt)
        receipt
    }
    fun deleteInstruction(id: String, expectedRevision: Int, instructionId: String, expectedInstruction: Int, now: Long) = transaction(true) {
        require(now > 0)
        val issue = concern(id) ?: throw HealthCareConflict()
        val value = instructionRows().get(instructionId) ?: throw HealthCareConflict()
        if (issue.revision != expectedRevision || value.concernId != id || value.revision != expectedInstruction) throw HealthCareConflict()
        persist(HealthCareInstructionActionPolicy.invalidate(issue) { it.instructionId == instructionId }
            .copy(revision = Math.addExact(issue.revision, 1), updatedAt = maxOf(now, issue.updatedAt)), "instruction_deleted")
        instructionRows().purge(id, instructionId = instructionId)
    }
    fun instructionCurrent(issue: HealthCareConcern, action: HealthCareAction): Boolean {
        val ref = action.instruction ?: return true
        val value = instruction(ref.instructionId) ?: return false
        val link = encounterDocument(ref.documentId) ?: return false
        return action in issue.actions && ref.matches(value) && value.concernId == issue.id &&
            encounter(ref.encounterId)?.concernId == issue.id && link.concernId == issue.id && link.encounterId == ref.encounterId &&
            link.source.copy(page = ref.original.page, pageCount = ref.original.pageCount) == ref.original &&
            (link.source.page == null || link.source == ref.original) && HealthCareInstructionActionPolicy.eligible(value)
    }
    fun confirmInstructionAction(id: String, expectedRevision: Int, instructionId: String, expectedInstruction: Int,
        now: Long): HealthCareAction = transaction(true) {
        val issue = concern(id) ?: throw HealthCareConflict()
        val value = instruction(instructionId) ?: throw HealthCareConflict()
        if (value.concernId != id || value.revision != expectedInstruction) throw HealthCareConflict()
        val action = HealthCareInstructionActionPolicy.confirm(issue, value, now)
        if (!instructionCurrent(issue.copy(actions = issue.actions.filterNot { it.id == action.id } + action), action)) throw HealthCareConflict()
        issue.actions.firstOrNull { it.id == action.id }?.let {
            if (it.instruction != action.instruction) throw HealthCareConflict()
            return@transaction it
        }
        if (issue.revision != expectedRevision) throw HealthCareConflict()
        persist(issue.copy(actions = issue.actions + action, revision = Math.addExact(issue.revision, 1),
            updatedAt = maxOf(now, issue.updatedAt)), "instruction_action_confirmed")
        check(concern(id)?.actions?.singleOrNull { it.id == action.id } == action)
        action
    }
    fun delete(id: String, expectedRevision: Int) = transaction(true) {
        val value = concern(id) ?: throw HealthCareConflict()
        if (value.revision != expectedRevision) throw HealthCareConflict()
        db.delete("history", "concern_id=?", arrayOf(id))
        db.delete("plans", "concern_id=?", arrayOf(id))
        db.delete("evidence_reads", "concern_id=?", arrayOf(id))
        db.delete("action_reminders", "concern_id=?", arrayOf(id))
        agendaRows().remove(id)
        questionRows().delete(id)
        answerRows().delete(id)
        feedbackRows().delete(id)
        encounterRows().delete(id)
        documentRows().purge(id)
        instructionRows().purge(id)
        // Keep only encrypted routing tombstones so a late result cannot revive deleted health data.
        var after = ""
        while (true) {
            val jobs = researchJobs(id, after)
            if (jobs.isEmpty()) break
            jobs.forEach { writeResearchJob(it.copy(state = HealthCareResearchState.CANCELLED, detail = "",
                cancellationPending = it.cancellationPending || !it.terminal)) }
            after = jobs.last().turnId
        }
        db.delete("research_authorizations", "concern_id=?", arrayOf(id))
        db.delete("concerns", "id=?", arrayOf(id))
        // A policy refresh must not recreate a dismissed issue for unchanged source data.
        evaluation(value.metric)?.let { marker ->
            val token = marker.getString("token")
            db.update("evaluations", ContentValues().apply {
                put("payload", pack("evaluation", "${metricKey(value.metric)}:$token", marker.put("dismissed", true)))
            }, "metric_key=?", arrayOf(metricKey(value.metric)))
        }
        Unit
    }
    override fun close() = helper.close()
    private class Database(context: Context, name: String) : SQLiteOpenHelper(context, name, null, 15) {
        init { setWriteAheadLoggingEnabled(true) }
        override fun onCreate(db: SQLiteDatabase) {
            db.execSQL("CREATE TABLE settings(id INTEGER PRIMARY KEY,version TEXT NOT NULL,payload BLOB NOT NULL)")
            db.execSQL("CREATE TABLE concerns(id TEXT PRIMARY KEY,revision INTEGER NOT NULL,payload BLOB NOT NULL,updated_at INTEGER NOT NULL," +
                "metric_key TEXT NOT NULL UNIQUE,open INTEGER NOT NULL,stage TEXT NOT NULL,due_at INTEGER,priority INTEGER NOT NULL DEFAULT 0)")
            priorityIndexes(db)
            db.execSQL("CREATE INDEX care_due ON concerns(open,due_at,id)")
            db.execSQL("CREATE TABLE history(concern_id TEXT NOT NULL,revision INTEGER NOT NULL,payload BLOB NOT NULL,PRIMARY KEY(concern_id,revision))")
            db.execSQL("CREATE TABLE evaluations(metric_key TEXT PRIMARY KEY,token TEXT NOT NULL,payload BLOB NOT NULL)")
            discussions(db)
            plans(db)
            reminders(db)
            evidence(db)
            research(db)
            HealthCareQuestionRows.create(db)
            HealthCareAnswerRows.create(db)
            HealthCareAgendaRows.create(db)
            HealthCareFeedbackRows.create(db)
            HealthCareEncounterRows.create(db)
            HealthCareDocumentRows.create(db)
            HealthCareInstructionRows.create(db)
        }
        private fun discussions(db: SQLiteDatabase) {
            // Bindings survive concern deletion so an old sensitive conversation cannot become an ordinary chat.
            db.execSQL("CREATE TABLE discussions(conversation_id TEXT PRIMARY KEY,payload BLOB NOT NULL)")
            db.execSQL("CREATE TABLE discussion_grants(turn_id TEXT PRIMARY KEY,payload BLOB NOT NULL)")
        }
        override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
            check(oldVersion in 1..14 && newVersion == 15)
            if (oldVersion < 2) discussions(db)
            if (oldVersion < 3) plans(db)
            if (oldVersion < 4) reminders(db)
            if (oldVersion < 5) evidence(db)
            if (oldVersion < 6) {
                db.execSQL("ALTER TABLE concerns ADD COLUMN priority INTEGER NOT NULL DEFAULT 0")
                db.execSQL("DROP INDEX care_open_pages")
                db.execSQL("DROP INDEX care_all_pages")
                priorityIndexes(db)
            }
            if (oldVersion < 7) research(db)
            if (oldVersion < 8) HealthCareQuestionRows.create(db)
            if (oldVersion < 9) HealthCareAnswerRows.create(db)
            if (oldVersion < 10) HealthCareAgendaRows.create(db)
            if (oldVersion < 11) HealthCareFeedbackRows.create(db)
            if (oldVersion < 12) HealthCareEncounterRows.create(db)
            if (oldVersion < 13) HealthCareDocumentRows.create(db)
            if (oldVersion < 14) HealthCareInstructionRows.create(db)
        }
        private fun research(db: SQLiteDatabase) {
            db.execSQL("CREATE TABLE research_authorizations(concern_id TEXT PRIMARY KEY,id TEXT NOT NULL UNIQUE,payload BLOB NOT NULL)")
            db.execSQL("CREATE TABLE research_jobs(turn_id TEXT PRIMARY KEY,concern_id TEXT NOT NULL,authorization_id TEXT NOT NULL," +
                "trigger TEXT NOT NULL,state TEXT NOT NULL,payload BLOB NOT NULL,created_at INTEGER NOT NULL,cancel_pending INTEGER NOT NULL," +
                "UNIQUE(authorization_id,trigger))")
            db.execSQL("CREATE INDEX care_research_concern ON research_jobs(concern_id,turn_id)")
            db.execSQL("CREATE INDEX care_research_recent ON research_jobs(concern_id,created_at DESC,turn_id DESC)")
            db.execSQL("CREATE INDEX care_research_cancel ON research_jobs(cancel_pending,turn_id)")
        }
        private fun priorityIndexes(db: SQLiteDatabase) {
            db.execSQL("CREATE INDEX care_open_pages ON concerns(open,priority DESC,updated_at DESC,id DESC)")
            db.execSQL("CREATE INDEX care_all_pages ON concerns(priority DESC,updated_at DESC,id DESC)")
        }
        private fun evidence(db: SQLiteDatabase) {
            db.execSQL("CREATE TABLE evidence_reads(id TEXT PRIMARY KEY,concern_id TEXT NOT NULL,turn_id TEXT NOT NULL,payload BLOB NOT NULL)")
            db.execSQL("CREATE INDEX care_evidence_concern ON evidence_reads(concern_id,turn_id)")
        }
        private fun plans(db: SQLiteDatabase) {
            db.execSQL("CREATE TABLE plans(id TEXT PRIMARY KEY,concern_id TEXT NOT NULL,created_at INTEGER NOT NULL,state TEXT NOT NULL,payload BLOB NOT NULL)")
            db.execSQL("CREATE INDEX care_pending_plans ON plans(concern_id,state,created_at DESC,id DESC)")
        }
        private fun reminders(db: SQLiteDatabase) {
            db.execSQL("CREATE TABLE action_reminders(action_id TEXT PRIMARY KEY,concern_id TEXT NOT NULL,token TEXT NOT NULL,due INTEGER NOT NULL,state TEXT NOT NULL,payload BLOB NOT NULL)")
            db.execSQL("CREATE INDEX care_reminder_due ON action_reminders(state,due,action_id)")
            db.execSQL("CREATE INDEX care_reminder_concern ON action_reminders(concern_id,due,action_id)")
        }
    }
    companion object {
        const val DEFAULT_DB = "health_care_v1.db"
        private const val COLUMNS = "id,revision,payload,updated_at,metric_key,open,stage,due_at,priority"
        private const val REMINDER_COLUMNS = "action_id,concern_id,token,due,state,payload"
        private const val RESEARCH_COLUMNS = "turn_id,concern_id,authorization_id,trigger,state,payload,created_at,cancel_pending"
        fun changes(context: Context, name: String = DEFAULT_DB) = android.net.Uri.parse("content://${context.packageName}.health-originals/changes/care/" + android.net.Uri.encode(name))
    }
}

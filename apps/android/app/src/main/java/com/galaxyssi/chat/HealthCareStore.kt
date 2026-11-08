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
        }.forEach { writeReminder(it.copy(state = HealthCareReminderState.CANCELLED, updatedAt = value.updatedAt)) }
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
    fun discussion(conversationId: String): String? = db.rawQuery(
        "SELECT payload FROM discussions WHERE conversation_id=?", arrayOf(conversationId)
    ).use { row ->
        if (!row.moveToFirst()) null else unpack("discussion", conversationId, row.getBlob(0)).let {
            check(it.getString("conversation") == conversationId); it.getString("concern")
        }
    }
    fun bindDiscussion(id: String, expectedRevision: Int, conversationId: String): HealthCareConcern = transaction(true) {
        require(HealthProfilePolicy.uuid(conversationId))
        val before = concern(id) ?: throw HealthCareConflict()
        if (before.revision != expectedRevision || discussion(conversationId)?.let { it != id } == true) throw HealthCareConflict()
        db.insertWithOnConflict("discussions", null, ContentValues().apply {
            put("conversation_id", conversationId)
            put("payload", pack("discussion", conversationId, JSONObject().put("conversation", conversationId).put("concern", id)))
        }, SQLiteDatabase.CONFLICT_IGNORE)
        before.copy(conversationId = conversationId, revision = before.revision + 1,
            updatedAt = maxOf(before.updatedAt, System.currentTimeMillis())).also { persist(it, "discussion_bound") }
    }
    fun approveDiscussion(grant: HealthCareDiscussionGrant) = transaction {
        val current = concern(grant.concernId) ?: throw HealthCareConflict()
        if (discussion(grant.conversationId) != current.id || current.revision != grant.revision ||
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
            !settings().enabled || settings().version != scope.settingsVersion || issue.revision != scope.revision ||
            discussion(scope.conversationId) != issue.id || issue.conversationId != scope.conversationId ||
            !HealthCareResearchPolicy.eligible(issue)) throw HealthCareConflict()
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
            settings().version != authorization.scope.settingsVersion) throw HealthCareConflict()
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
        return authorization.permits(grant) && !job.terminal && job.authorizationId == authorization.id &&
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
    private fun writeReminder(value: HealthCareReminder) {
        db.insertWithOnConflict("action_reminders", null, ContentValues().apply {
            put("action_id", value.actionId); put("concern_id", value.concernId); put("token", value.token)
            put("due", value.dueAt); put("state", value.state.name); put("payload", pack("reminder", value.actionId, value.json()))
        }, SQLiteDatabase.CONFLICT_REPLACE)
    }
    fun scheduleReminder(concernId: String, actionId: String, expectedRevision: Int, expectedToken: String?,
        privacy: HealthPrivacyPolicy, sourceVersion: String, at: Long, now: Long): HealthCareReminder = transaction(true) {
        val issue = concern(concernId) ?: throw HealthCareConflict()
        if (issue.revision != expectedRevision || reminder(actionId)?.token != expectedToken) throw HealthCareConflict()
        val action = issue.actions.firstOrNull { it.id == actionId } ?: throw HealthCareConflict()
        HealthCareFollowUpPolicy.schedule(issue, action, settings(), privacy, sourceVersion, at, now).also(::writeReminder)
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
    fun finishAction(id: String, expectedRevision: Int, actionId: String, outcome: String, now: Long) =
        update(id, expectedRevision, "action_outcome_recorded") { HealthCareFollowUpPolicy.finish(it, actionId, outcome, now) }
    fun delete(id: String, expectedRevision: Int) = transaction(true) {
        val value = concern(id) ?: throw HealthCareConflict()
        if (value.revision != expectedRevision) throw HealthCareConflict()
        db.delete("history", "concern_id=?", arrayOf(id))
        db.delete("plans", "concern_id=?", arrayOf(id))
        db.delete("evidence_reads", "concern_id=?", arrayOf(id))
        db.delete("action_reminders", "concern_id=?", arrayOf(id))
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
    private class Database(context: Context, name: String) : SQLiteOpenHelper(context, name, null, 7) {
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
        }
        private fun discussions(db: SQLiteDatabase) {
            // Bindings survive concern deletion so an old sensitive conversation cannot become an ordinary chat.
            db.execSQL("CREATE TABLE discussions(conversation_id TEXT PRIMARY KEY,payload BLOB NOT NULL)")
            db.execSQL("CREATE TABLE discussion_grants(turn_id TEXT PRIMARY KEY,payload BLOB NOT NULL)")
        }
        override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
            check(oldVersion in 1..6 && newVersion == 7)
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
            research(db)
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

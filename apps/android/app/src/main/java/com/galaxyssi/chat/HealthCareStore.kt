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
            if (committed && notify) app.contentResolver.notifyChange(changes(app, name), null)
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
        next
    }
    private fun decode(row: Cursor): HealthCareConcern {
        val value = HealthCareConcern.from(unpack("concern", "${row.getString(0)}:${row.getInt(1)}", row.getBlob(2)))
        check(value.id == row.getString(0) && value.revision == row.getInt(1) && value.updatedAt == row.getLong(3))
        check(metricKey(value.metric) == row.getString(4) && value.open == (row.getInt(5) == 1) && value.stage.name == row.getString(6))
        check(value.nextDue == if (row.isNull(7)) null else row.getLong(7))
        return value
    }
    fun concern(id: String): HealthCareConcern? {
        require(HealthProfilePolicy.uuid(id))
        return db.rawQuery("SELECT $COLUMNS FROM concerns WHERE id=?", arrayOf(id)).use { if (it.moveToFirst()) decode(it) else null }
    }
    fun forMetric(metric: HealthMetric): HealthCareConcern? = db.rawQuery("SELECT $COLUMNS FROM concerns WHERE metric_key=?",
        arrayOf(metricKey(metric))).use { if (it.moveToFirst()) decode(it) else null }
    fun evaluated(metric: HealthMetric): String? = db.rawQuery("SELECT token,payload FROM evaluations WHERE metric_key=?", arrayOf(metricKey(metric))).use {
        if (!it.moveToFirst()) null else {
            val token = it.getString(0); val j = unpack("evaluation", "${metricKey(metric)}:$token", it.getBlob(1))
            check(j.getString("metric") == metric.name && j.getString("token") == token); token
        }
    }
    private fun persist(value: HealthCareConcern, event: String) {
        require(event.isNotBlank() && event.length <= 120)
        val encrypted = pack("concern", "${value.id}:${value.revision}", value.json())
        db.insertWithOnConflict("concerns", null, ContentValues().apply {
            put("id", value.id); put("revision", value.revision); put("payload", encrypted); put("updated_at", value.updatedAt)
            put("metric_key", metricKey(value.metric)); put("open", if (value.open) 1 else 0); put("stage", value.stage.name)
            if (value.nextDue == null) putNull("due_at") else put("due_at", value.nextDue)
        }, SQLiteDatabase.CONFLICT_REPLACE)
        db.insertOrThrow("history", null, ContentValues().apply {
            put("concern_id", value.id); put("revision", value.revision)
            put("payload", pack("history", "${value.id}:${value.revision}", JSONObject().put("event", event).put("concern", value.json())))
        })
    }
    fun applyEvaluation(metric: HealthMetric, token: String, expectedSettings: String, expectedRevision: Int?,
        assessment: HealthCareAssessment?, now: Long): HealthCareConcern? = transaction(true) {
        val settings = settings()
        if (!settings.enabled || settings.version != expectedSettings) throw HealthCareConflict()
        val prior = forMetric(metric)
        if (prior?.revision != expectedRevision) throw HealthCareConflict()
        if (evaluated(metric) == token) return@transaction prior
        val next = HealthCarePolicy.reconcile(prior, metric, assessment, token, now)
        if (next != null && next != prior) persist(next, "measurement_assessed")
        db.insertWithOnConflict("evaluations", null, ContentValues().apply {
            put("metric_key", metricKey(metric)); put("token", token)
            put("payload", pack("evaluation", "${metricKey(metric)}:$token", JSONObject().put("metric", metric.name).put("token", token)))
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
            where += "(updated_at<? OR (updated_at=? AND id<?))"
            args += listOf(after.updatedAt.toString(), after.updatedAt.toString(), after.id)
        }
        val items = db.rawQuery("SELECT $COLUMNS FROM concerns WHERE ${where.joinToString(" AND ")} ORDER BY updated_at DESC,id DESC LIMIT ${limit + 1}",
            args.toTypedArray()).use { rows -> buildList { while (rows.moveToNext()) add(decode(rows)) } }
        val visible = items.take(limit)
        return HealthCarePage(visible, if (items.size > limit) visible.last().let { HealthCareCursor(it.updatedAt, it.id) } else null)
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
            !settings().enabled || settings().version != grant.settingsVersion) throw HealthCareConflict()
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
    fun proposePlan(value: HealthCarePlan): HealthCarePlan = transaction(true) {
        val grant = value.grant
        if (discussionGrant(grant.turnId) != grant || discussion(grant.conversationId) != grant.concernId) throw HealthCareConflict()
        val issue = concern(grant.concernId) ?: throw HealthCareConflict()
        if (issue.revision != grant.revision || issue.inputVersion != value.inputVersion || !settings().enabled ||
            settings().version != grant.settingsVersion || value.state != HealthCarePlanState.PENDING) throw HealthCareConflict()
        plan(value.id)?.let { prior ->
            if (prior.requestHash != value.requestHash || prior.grant != grant) throw HealthCareConflict()
            return@transaction prior
        }
        persistPlan(value)
        value
    }
    fun resolvePlan(id: String, selected: Set<String>, expectedRevision: Int, privacy: HealthPrivacyPolicy,
        sourceVersion: String, now: Long): HealthCareConcern = transaction(true) {
        val proposed = plan(id) ?: throw HealthCareConflict()
        val issue = concern(proposed.grant.concernId) ?: throw HealthCareConflict()
        if (proposed.state != HealthCarePlanState.PENDING || issue.revision != expectedRevision ||
            !HealthCarePlanPolicy.current(proposed, issue, settings(), privacy, sourceVersion)) throw HealthCareConflict()
        val next = HealthCarePlanPolicy.accept(proposed, issue, selected, now)
            .copy(revision = issue.revision + 1, updatedAt = maxOf(issue.updatedAt, now))
        persist(next, "agent_plan_confirmed")
        persistPlan(proposed.copy(state = HealthCarePlanState.ACCEPTED, selected = selected, resolvedAt = now))
        next
    }
    fun dismissPlan(id: String, now: Long) = transaction(true) {
        val proposed = plan(id) ?: throw HealthCareConflict()
        if (proposed.state == HealthCarePlanState.PENDING) persistPlan(proposed.copy(state = HealthCarePlanState.DISMISSED, resolvedAt = now))
    }
    fun delete(id: String, expectedRevision: Int) = transaction(true) {
        val value = concern(id) ?: throw HealthCareConflict()
        if (value.revision != expectedRevision) throw HealthCareConflict()
        db.delete("history", "concern_id=?", arrayOf(id))
        db.delete("plans", "concern_id=?", arrayOf(id))
        db.delete("concerns", "id=?", arrayOf(id))
        // Keep the evaluation marker: reopening the page must not immediately recreate a deleted issue.
        Unit
    }
    override fun close() = helper.close()
    private class Database(context: Context, name: String) : SQLiteOpenHelper(context, name, null, 3) {
        init { setWriteAheadLoggingEnabled(true) }
        override fun onCreate(db: SQLiteDatabase) {
            db.execSQL("CREATE TABLE settings(id INTEGER PRIMARY KEY,version TEXT NOT NULL,payload BLOB NOT NULL)")
            db.execSQL("CREATE TABLE concerns(id TEXT PRIMARY KEY,revision INTEGER NOT NULL,payload BLOB NOT NULL,updated_at INTEGER NOT NULL," +
                "metric_key TEXT NOT NULL UNIQUE,open INTEGER NOT NULL,stage TEXT NOT NULL,due_at INTEGER)")
            db.execSQL("CREATE INDEX care_open_pages ON concerns(open,updated_at DESC,id DESC)")
            db.execSQL("CREATE INDEX care_all_pages ON concerns(updated_at DESC,id DESC)")
            db.execSQL("CREATE INDEX care_due ON concerns(open,due_at,id)")
            db.execSQL("CREATE TABLE history(concern_id TEXT NOT NULL,revision INTEGER NOT NULL,payload BLOB NOT NULL,PRIMARY KEY(concern_id,revision))")
            db.execSQL("CREATE TABLE evaluations(metric_key TEXT PRIMARY KEY,token TEXT NOT NULL,payload BLOB NOT NULL)")
            discussions(db)
            plans(db)
        }
        private fun discussions(db: SQLiteDatabase) {
            // Bindings survive concern deletion so an old sensitive conversation cannot become an ordinary chat.
            db.execSQL("CREATE TABLE discussions(conversation_id TEXT PRIMARY KEY,payload BLOB NOT NULL)")
            db.execSQL("CREATE TABLE discussion_grants(turn_id TEXT PRIMARY KEY,payload BLOB NOT NULL)")
        }
        override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
            check(oldVersion in 1..2 && newVersion == 3)
            if (oldVersion < 2) discussions(db)
            plans(db)
        }
        private fun plans(db: SQLiteDatabase) {
            db.execSQL("CREATE TABLE plans(id TEXT PRIMARY KEY,concern_id TEXT NOT NULL,created_at INTEGER NOT NULL,state TEXT NOT NULL,payload BLOB NOT NULL)")
            db.execSQL("CREATE INDEX care_pending_plans ON plans(concern_id,state,created_at DESC,id DESC)")
        }
    }
    companion object {
        const val DEFAULT_DB = "health_care_v1.db"
        private const val COLUMNS = "id,revision,payload,updated_at,metric_key,open,stage,due_at"
        fun changes(context: Context, name: String = DEFAULT_DB) = android.net.Uri.parse("content://${context.packageName}.health-originals/changes/care/" + android.net.Uri.encode(name))
    }
}

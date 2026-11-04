package com.galaxyssi.chat

import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import java.io.Closeable
import org.json.JSONObject

internal data class HealthPageCursor(val measuredAt: Long, val id: String)
internal data class HealthRecordPage(val records: List<HealthObservation>, val next: HealthPageCursor?)
internal sealed class HealthSaveResult {
    data class Saved(val record: HealthObservation) : HealthSaveResult()
    data class Duplicate(val id: String) : HealthSaveResult()
    object Conflict : HealthSaveResult()
}

/** Indexed metadata stays separate from authenticated, individually encrypted measurement payloads. */
internal class HealthRecordStore(context: Context, private val name: String = "health_records_v1.db") : Closeable {
    private val app = context.applicationContext
    private val helper = Database(context.applicationContext, name)
    private val pendingVersions = linkedMapOf<HealthMetric, String>()
    internal val tableDatabase: SQLiteDatabase get() = helper.writableDatabase
    private fun aad(id: String, revision: Int) = "$name|health|$id|$revision".toByteArray(Charsets.UTF_8)
    private fun dedupe(record: HealthObservation) = AgentMemoryIndexKey.token("$name|health-duplicate-v1|${HealthObservationPolicy.duplicateKey(record)}")
    private fun evidenceKey(draft: HealthDraft): String? = draft.evidence?.let {
        AgentMemoryIndexKey.token("$name|health-evidence-v1|${it.originalId}|${it.page}|${it.candidateId}|${draft.metric.name}")
    }
    fun recordForEvidence(draft: HealthDraft): HealthObservation? {
        val key = evidenceKey(draft) ?: return null
        return helper.readableDatabase.rawQuery("SELECT id,revision,payload,metric,measured_at FROM observations WHERE evidence_key=? AND deleted=0", arrayOf(key))
            .use { if (it.moveToFirst()) decode(it).also { record -> check(evidenceKey(record.draft) == key) { "Health evidence index mismatch" } } else null }
    }
    fun duplicateFor(draft: HealthDraft): String? = recordForEvidence(draft)?.id ?: helper.readableDatabase.rawQuery(
        "SELECT id FROM observations WHERE dedupe=? AND deleted=0", arrayOf(dedupe(HealthObservationPolicy.observation(draft)))
    ).use { if (it.moveToFirst()) it.getString(0) else null }
    private fun encode(record: HealthObservation): ByteArray {
        val bytes = record.json().toString().toByteArray(Charsets.UTF_8)
        return try { AgentStorageCipher.encryptBinary(bytes, aad(record.id, record.revision)) } finally { bytes.fill(0) }
    }
    private fun decode(cursor: Cursor): HealthObservation {
        val id = cursor.getString(0)
        val revision = cursor.getInt(1)
        val bytes = AgentStorageCipher.decryptBinary(cursor.getBlob(2), aad(id, revision))
        return try { HealthObservation.from(JSONObject(String(bytes, Charsets.UTF_8))).also {
            check(it.id == id && it.revision == revision && HealthObservationPolicy.validate(it.draft) == null) { "Invalid health record" }
            if (cursor.getColumnIndex("metric") >= 0) check(it.draft.metric.name == cursor.getString(3) && it.draft.measuredAt == cursor.getLong(4)) {
                "Health index does not match the authenticated record"
            }
        } } finally { bytes.fill(0) }
    }
    fun count(): Long = helper.readableDatabase.rawQuery("SELECT COUNT(*) FROM observations WHERE deleted=0", null)
        .use { it.moveToFirst(); it.getLong(0) }
    fun metricVersion(metric: HealthMetric): String = helper.readableDatabase.rawQuery("SELECT token FROM health_metric_clocks WHERE metric=?", arrayOf(metric.name))
        .use { if (it.moveToFirst()) it.getString(0) else "" }
    fun metricVersions(metrics: Set<HealthMetric>): Map<HealthMetric, String> {
        require(metrics.isNotEmpty())
        val names = metrics.map { it.name }.toTypedArray()
        val placeholders = names.joinToString(",") { "?" }
        return helper.readableDatabase.rawQuery("SELECT metric,token FROM health_metric_clocks WHERE metric IN ($placeholders)", names).use {
            val result = metrics.associateWith { "" }.toMutableMap()
            while (it.moveToNext()) result[HealthMetric.valueOf(it.getString(0))] = it.getString(1)
            result.toMap()
        }
    }
    private fun changed(metric: HealthMetric) {
        val token = java.util.UUID.randomUUID().toString()
        helper.writableDatabase.insertWithOnConflict("health_metric_clocks", null, ContentValues().apply { put("metric", metric.name); put("token", token) }, SQLiteDatabase.CONFLICT_REPLACE)
        pendingVersions[metric] = token
    }
    @Synchronized internal fun publishCommittedChanges() {
        if (pendingVersions.isEmpty()) return
        runCatching {
            if (helper.writableDatabase.inTransaction()) return
            val versions = pendingVersions.toMap(); pendingVersions.clear()
            if (versions.any { (metric, token) -> metricVersion(metric) == token }) app.contentResolver.notifyChange(changes(app, name), null)
        }
    }
    fun revision(id: String, revision: Int): HealthObservation? = helper.readableDatabase.rawQuery(
        "SELECT id,revision,payload FROM revisions WHERE id=? AND revision=? AND deleted=0", arrayOf(id, revision.toString())
    ).use { if (it.moveToFirst()) decode(it) else null }

    fun record(id: String): HealthObservation? = helper.readableDatabase.rawQuery(
        "SELECT id,revision,payload,metric,measured_at FROM observations WHERE id=? AND deleted=0", arrayOf(id)
    ).use { if (it.moveToFirst()) decode(it) else null }

    fun page(after: HealthPageCursor? = null, metric: HealthMetric? = null, limit: Int = PAGE_SIZE, originalId: String? = null,
             metrics: Set<HealthMetric>? = null): HealthRecordPage {
        require(limit in 1..PAGE_SIZE)
        if (metrics != null && metrics.isEmpty()) return HealthRecordPage(emptyList(), null)
        if (metric != null && metrics != null && metric !in metrics) return HealthRecordPage(emptyList(), null)
        if (metric == null && metrics != null && metrics.size > 1 && metrics.size < HealthMetric.entries.size)
            return catalogPage(after, metrics, limit, originalId)
        val args = mutableListOf<String>()
        val conditions = mutableListOf("deleted=0")
        val selectedMetric = metric ?: metrics?.singleOrNull()
        if (selectedMetric != null) { conditions += "metric=?"; args += selectedMetric.name }
        if (originalId != null) { conditions += "original_id=?"; args += originalId }
        if (after != null) { conditions += "(measured_at<? OR (measured_at=? AND id<?))"; args += listOf(after.measuredAt.toString(), after.measuredAt.toString(), after.id) }
        val records = helper.readableDatabase.rawQuery("SELECT id,revision,payload,metric,measured_at FROM observations WHERE " +
            conditions.joinToString(" AND ") + " ORDER BY measured_at DESC,id DESC LIMIT ${limit + 1}", args.toTypedArray()).use {
            buildList { while (it.moveToNext()) add(decode(it).also { record ->
                if (originalId != null) check(record.draft.evidence?.originalId == originalId) { "Health original index mismatch" }
                if (metrics != null) check(record.draft.metric in metrics) { "Health catalog index mismatch" }
            }) }
        }
        val visible = records.take(limit)
        val next = if (records.size > limit) visible.last().let { HealthPageCursor(it.draft.measuredAt, it.id) } else null
        return HealthRecordPage(visible, next)
    }

    /** Bound each indexed metric stream before merging IDs; decrypt at most one page plus lookahead. */
    private fun catalogPage(after: HealthPageCursor?, metrics: Set<HealthMetric>, limit: Int, originalId: String?): HealthRecordPage {
        val args = arrayListOf<String>()
        val streams = metrics.sortedBy { it.ordinal }.map { metric ->
            val conditions = mutableListOf("metric=?", "deleted=0"); args += metric.name
            if (originalId != null) { conditions += "original_id=?"; args += originalId }
            if (after != null) {
                conditions += "(measured_at<? OR (measured_at=? AND id<?))"
                args += listOf(after.measuredAt.toString(), after.measuredAt.toString(), after.id)
            }
            "SELECT id,measured_at FROM (SELECT id,measured_at FROM observations WHERE ${conditions.joinToString(" AND ")} " +
                "ORDER BY measured_at DESC,id DESC LIMIT ${limit + 1})"
        }
        val candidateIds = "SELECT id FROM (${streams.joinToString(" UNION ALL ")}) ORDER BY measured_at DESC,id DESC LIMIT ${limit + 1}"
        val records = helper.readableDatabase.rawQuery("SELECT id,revision,payload,metric,measured_at FROM observations WHERE id IN ($candidateIds) " +
            "ORDER BY measured_at DESC,id DESC LIMIT ${limit + 1}", args.toTypedArray()).use { cursor -> buildList {
                while (cursor.moveToNext()) add(decode(cursor).also { record ->
                    check(record.draft.metric in metrics) { "Health catalog index mismatch" }
                    if (originalId != null) check(record.draft.evidence?.originalId == originalId) { "Health original index mismatch" }
                })
            } }
        val visible = records.take(limit)
        return HealthRecordPage(visible, if (records.size > limit) visible.last().let { HealthPageCursor(it.draft.measuredAt, it.id) } else null)
    }

    fun trendChunk(spec: HealthTrendSpec, after: HealthPageCursor? = null, signal: android.os.CancellationSignal? = null): HealthRecordPage {
        val conditions = arrayListOf("deleted=0", "metric=?", "measured_at>=?", "measured_at<?")
        val args = arrayListOf(spec.metric.name, spec.from.toString(), spec.until.toString())
        if (spec.source.originalId.isNotBlank()) { conditions += "original_id=?"; args += spec.source.originalId }
        if (spec.source.manualOnly) conditions += "original_id IS NULL"
        if (after != null) { conditions += "(measured_at<? OR (measured_at=? AND id<?))"; args += listOf(after.measuredAt.toString(), after.measuredAt.toString(), after.id) }
        val rows = helper.readableDatabase.rawQuery("SELECT id,revision,payload,metric,measured_at FROM observations WHERE ${conditions.joinToString(" AND ")} " +
            "ORDER BY measured_at DESC,id DESC LIMIT ${PAGE_SIZE + 1}", args.toTypedArray(), signal).use { cursor -> buildList {
                while (cursor.moveToNext()) add(decode(cursor).also { record ->
                    check(record.draft.metric == spec.metric && record.draft.measuredAt >= spec.from && record.draft.measuredAt < spec.until)
                    if (spec.source.originalId.isNotBlank()) check(record.draft.evidence?.originalId == spec.source.originalId) { "Health trend original mismatch" }
                })
            } }
        val visible = rows.take(PAGE_SIZE)
        return HealthRecordPage(visible, if (rows.size > PAGE_SIZE) visible.last().let { HealthPageCursor(it.draft.measuredAt, it.id) } else null)
    }
    fun exportChunk(scope: HealthRecordExportScope, after: HealthPageCursor? = null, signal: android.os.CancellationSignal? = null): HealthRecordPage {
        val args = arrayListOf<String>()
        fun conditions(metric: HealthMetric?): String {
            val terms = arrayListOf("deleted=0", "measured_at>=?", "measured_at<?"); args += listOf(scope.from.toString(), scope.until.toString())
            metric?.let { terms += "metric=?"; args += it.name }
            if (scope.originalId.isNotEmpty()) { terms += "original_id=?"; args += scope.originalId }
            after?.let { terms += "(measured_at<? OR (measured_at=? AND id<?))"; args += listOf(it.measuredAt.toString(), it.measuredAt.toString(), it.id) }
            return terms.joinToString(" AND ")
        }
        val query = if (scope.metrics.size == HealthMetric.entries.size) {
            "SELECT id,revision,payload,metric,measured_at FROM observations WHERE ${conditions(null)} ORDER BY measured_at DESC,id DESC LIMIT 31"
        } else {
            val parts = scope.metrics.sortedBy { it.ordinal }.map { metric -> "SELECT id,measured_at FROM (SELECT id,measured_at FROM observations WHERE ${conditions(metric)} ORDER BY measured_at DESC,id DESC LIMIT 31)" }
            "SELECT id,revision,payload,metric,measured_at FROM observations WHERE id IN (SELECT id FROM (${parts.joinToString(" UNION ALL ")}) ORDER BY measured_at DESC,id DESC LIMIT 31) ORDER BY measured_at DESC,id DESC LIMIT 31"
        }
        val rows = helper.readableDatabase.rawQuery(query, args.toTypedArray(), signal).use { cursor -> buildList {
            while (cursor.moveToNext()) add(decode(cursor).also {
                check(it.draft.metric in scope.metrics && it.draft.measuredAt >= scope.from && it.draft.measuredAt < scope.until)
                if (scope.originalId.isNotEmpty()) check(it.draft.evidence?.originalId == scope.originalId) { "Health export source mismatch" }
            })
        } }
        val visible = rows.take(PAGE_SIZE)
        return HealthRecordPage(visible, if (rows.size > PAGE_SIZE) visible.last().let { HealthPageCursor(it.draft.measuredAt, it.id) } else null)
    }
    fun trendRecords(spec: HealthTrendSpec, after: HealthPageCursor? = null, numericOnly: Boolean = false,
                     cancelled: () -> Unit = {}, signal: android.os.CancellationSignal? = null): HealthRecordPage {
        val rows = arrayListOf<HealthObservation>(); var cursor = after
        do {
            cancelled(); val page = trendChunk(spec, cursor, signal)
            for (record in page.records) { cancelled(); if (spec.matches(record, numericOnly)) rows += record; if (rows.size > PAGE_SIZE) break }
            cursor = page.next
        } while (rows.size <= PAGE_SIZE && cursor != null)
        val visible = rows.take(PAGE_SIZE)
        return HealthRecordPage(visible, if (rows.size > PAGE_SIZE) visible.last().let { HealthPageCursor(it.draft.measuredAt, it.id) } else null)
    }
    fun trendSourceIds(spec: HealthTrendSpec, after: String = "", signal: android.os.CancellationSignal? = null): List<String> = helper.readableDatabase.rawQuery(
        "SELECT DISTINCT original_id FROM observations WHERE deleted=0 AND metric=? AND measured_at>=? AND measured_at<? " +
            "AND original_id IS NOT NULL AND original_id>? ORDER BY original_id LIMIT 31", arrayOf(spec.metric.name, spec.from.toString(), spec.until.toString(), after), signal
    ).use { cursor -> buildList { while (cursor.moveToNext()) add(cursor.getString(0)) } }

    @Synchronized fun save(draft: HealthDraft): HealthSaveResult {
        val database = helper.writableDatabase
        database.beginTransaction()
        return try { saveWithinTransaction(draft).also { database.setTransactionSuccessful() } }
        finally { database.endTransaction(); publishCommittedChanges() }
    }
    private fun saveWithinTransaction(draft: HealthDraft): HealthSaveResult {
        val record = HealthObservationPolicy.observation(draft)
        val encrypted = encode(record)
        val duplicateKey = dedupe(record)
        val database = helper.writableDatabase
        return try {
            val previous = database.rawQuery("SELECT revision,metric FROM observations WHERE id=? AND deleted=0", arrayOf(record.id))
                .use { if (it.moveToFirst()) it.getInt(0) to HealthMetric.valueOf(it.getString(1)) else null }
            val existing = previous?.first ?: 0
            if (existing != draft.revision) return HealthSaveResult.Conflict
            val priorEvidence = recordForEvidence(draft)
            if (priorEvidence != null && priorEvidence.id != record.id) return HealthSaveResult.Duplicate(priorEvidence.id)
            val duplicate = database.rawQuery("SELECT id FROM observations WHERE dedupe=? AND deleted=0 AND id<>?",
                arrayOf(duplicateKey, record.id)).use { if (it.moveToFirst()) it.getString(0) else null }
            if (duplicate != null) return HealthSaveResult.Duplicate(duplicate)
            val values = ContentValues().apply {
                put("id", record.id); put("revision", record.revision); put("metric", draft.metric.name)
                put("measured_at", draft.measuredAt); put("payload", encrypted); put("dedupe", duplicateKey)
                put("deleted", 0)
                put("original_id", draft.evidence?.originalId)
                put("evidence_key", evidenceKey(draft))
            }
            if (existing == 0) database.insertOrThrow("observations", null, values)
            else check(database.update("observations", values, "id=? AND revision=? AND deleted=0", arrayOf(record.id, existing.toString())) == 1)
            database.insertOrThrow("revisions", null, ContentValues().apply {
                put("id", record.id); put("revision", record.revision); put("payload", encrypted)
                put("changed_at", record.receivedAt); put("deleted", 0)
            })
            changed(record.draft.metric); previous?.second?.takeIf { it != record.draft.metric }?.let(::changed)
            database.delete("drafts", "draft_key=?", arrayOf(draftKey(draft)))
            HealthSaveResult.Saved(record)
        } finally { encrypted.fill(0) }
    }

    @Synchronized fun delete(id: String, revision: Int): Boolean {
        val database = helper.writableDatabase
        database.beginTransaction()
        return try {
            val value = record(id) ?: return false
            if (value.revision != revision) return false
            val removed = value.copy(revision = revision + 1, receivedAt = System.currentTimeMillis())
            val encrypted = encode(removed)
            try {
                check(database.update("observations", ContentValues().apply {
                    put("deleted", 1); put("revision", removed.revision); put("payload", encrypted)
                }, "id=? AND revision=?", arrayOf(id, revision.toString())) == 1)
                database.insertOrThrow("revisions", null, ContentValues().apply {
                    put("id", id); put("revision", removed.revision); put("payload", encrypted)
                    put("changed_at", System.currentTimeMillis()); put("deleted", 1)
                })
                changed(value.draft.metric)
                database.delete("drafts", "draft_key=?", arrayOf("edit:$id"))
                database.setTransactionSuccessful()
                true
            } finally { encrypted.fill(0) }
        } finally { database.endTransaction(); publishCommittedChanges() }
    }

    fun history(id: String, beforeRevision: Int = Int.MAX_VALUE): List<HealthObservation> = helper.readableDatabase.rawQuery(
        "SELECT id,revision,payload FROM revisions WHERE id=? AND revision<? ORDER BY revision DESC LIMIT 50", arrayOf(id, beforeRevision.toString())
    ).use { buildList { while (it.moveToNext()) add(decode(it)) } }

    fun saveDraft(draft: HealthDraft) {
        val key = draftKey(draft)
        if (!draft.hasInput()) { clearDraft(key); return }
        val bytes = draft.json().toString().toByteArray(Charsets.UTF_8)
        val encrypted = try { AgentStorageCipher.encryptBinary(bytes, aad(key, 1)) } finally { bytes.fill(0) }
        try { check(helper.writableDatabase.insertWithOnConflict("drafts", null, ContentValues().apply {
            put("draft_key", key); put("payload", encrypted)
        }, SQLiteDatabase.CONFLICT_REPLACE) != -1L) { "Health draft was not saved" } }
        finally { encrypted.fill(0) }
    }
    fun draft(key: String): HealthDraft? = helper.readableDatabase.rawQuery("SELECT payload FROM drafts WHERE draft_key=?", arrayOf(key)).use {
        if (!it.moveToFirst()) null else {
            val bytes = AgentStorageCipher.decryptBinary(it.getBlob(0), aad(key, 1))
            try { HealthDraft.from(JSONObject(String(bytes, Charsets.UTF_8))) } finally { bytes.fill(0) }
        }
    }
    fun clearDraft(key: String) { helper.writableDatabase.delete("drafts", "draft_key=?", arrayOf(key)) }
    override fun close() = helper.close()

    private class Database(context: Context, name: String) : SQLiteOpenHelper(context, name, null, 4) {
        init { setWriteAheadLoggingEnabled(true) }
        override fun onConfigure(db: SQLiteDatabase) { db.setForeignKeyConstraintsEnabled(true) }
        override fun onCreate(db: SQLiteDatabase) {
            db.execSQL("CREATE TABLE observations(id TEXT PRIMARY KEY,revision INTEGER NOT NULL,metric TEXT NOT NULL," +
                "measured_at INTEGER NOT NULL,payload BLOB NOT NULL,dedupe TEXT NOT NULL,deleted INTEGER NOT NULL DEFAULT 0,original_id TEXT,evidence_key TEXT)")
            db.execSQL("CREATE UNIQUE INDEX observation_dedupe ON observations(dedupe) WHERE deleted=0")
            db.execSQL("CREATE INDEX observation_page ON observations(deleted,measured_at DESC,id DESC)")
            db.execSQL("CREATE INDEX observation_metric_page ON observations(metric,deleted,measured_at DESC,id DESC)")
            db.execSQL("CREATE INDEX observation_original_page ON observations(original_id,deleted,measured_at DESC,id DESC)")
            db.execSQL("CREATE UNIQUE INDEX observation_evidence ON observations(evidence_key) WHERE deleted=0 AND evidence_key IS NOT NULL")
            db.execSQL("CREATE TABLE revisions(id TEXT NOT NULL REFERENCES observations(id),revision INTEGER NOT NULL," +
                "payload BLOB NOT NULL,changed_at INTEGER NOT NULL,deleted INTEGER NOT NULL,PRIMARY KEY(id,revision))")
            db.execSQL("CREATE TABLE drafts(draft_key TEXT PRIMARY KEY,payload BLOB NOT NULL)")
            HealthTableStore.createSchema(db)
            createClocks(db)
        }
        override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
            check(oldVersion in 1..3 && newVersion == 4) { "Unsupported health schema upgrade" }
            if (oldVersion < 2) {
                db.execSQL("ALTER TABLE observations ADD COLUMN original_id TEXT")
                db.execSQL("ALTER TABLE observations ADD COLUMN evidence_key TEXT")
                db.execSQL("CREATE INDEX observation_original_page ON observations(original_id,deleted,measured_at DESC,id DESC)")
                db.execSQL("CREATE UNIQUE INDEX observation_evidence ON observations(evidence_key) WHERE deleted=0 AND evidence_key IS NOT NULL")
            }
            if (oldVersion < 3) HealthTableStore.createSchema(db)
            createClocks(db)
        }
        private fun createClocks(db: SQLiteDatabase) { db.execSQL("CREATE TABLE IF NOT EXISTS health_metric_clocks(metric TEXT PRIMARY KEY,token TEXT NOT NULL)") }
    }
    companion object {
        const val PAGE_SIZE = 30
        fun changes(context: Context, name: String = "health_records_v1.db") = android.net.Uri.parse("content://${context.packageName}.health-originals/changes/observations/" + android.net.Uri.encode(name))
        fun draftKey(draft: HealthDraft) = when {
            draft.recordId.isNotBlank() -> "edit:${draft.recordId}"
            draft.evidence != null -> "ocr:${draft.evidence.jobId}:${draft.evidence.page}:${draft.evidence.candidateId}"
            else -> "new:${draft.metric.name}"
        }
    }
}

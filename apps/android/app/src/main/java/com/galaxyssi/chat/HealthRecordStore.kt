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
    private val helper = Database(context.applicationContext, name)
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

    fun record(id: String): HealthObservation? = helper.readableDatabase.rawQuery(
        "SELECT id,revision,payload,metric,measured_at FROM observations WHERE id=? AND deleted=0", arrayOf(id)
    ).use { if (it.moveToFirst()) decode(it) else null }

    fun page(after: HealthPageCursor? = null, metric: HealthMetric? = null, limit: Int = PAGE_SIZE, originalId: String? = null): HealthRecordPage {
        require(limit in 1..PAGE_SIZE)
        val args = mutableListOf<String>()
        val conditions = mutableListOf("deleted=0")
        if (metric != null) { conditions += "metric=?"; args += metric.name }
        if (originalId != null) { conditions += "original_id=?"; args += originalId }
        if (after != null) { conditions += "(measured_at<? OR (measured_at=? AND id<?))"; args += listOf(after.measuredAt.toString(), after.measuredAt.toString(), after.id) }
        val records = helper.readableDatabase.rawQuery("SELECT id,revision,payload,metric,measured_at FROM observations WHERE " +
            conditions.joinToString(" AND ") + " ORDER BY measured_at DESC,id DESC LIMIT ${limit + 1}", args.toTypedArray()).use {
            buildList { while (it.moveToNext()) add(decode(it).also { record ->
                if (originalId != null) check(record.draft.evidence?.originalId == originalId) { "Health original index mismatch" }
            }) }
        }
        val visible = records.take(limit)
        val next = if (records.size > limit) visible.last().let { HealthPageCursor(it.draft.measuredAt, it.id) } else null
        return HealthRecordPage(visible, next)
    }

    @Synchronized fun save(draft: HealthDraft): HealthSaveResult {
        val record = HealthObservationPolicy.observation(draft)
        val encrypted = encode(record)
        val duplicateKey = dedupe(record)
        val database = helper.writableDatabase
        database.beginTransaction()
        return try {
            val existing = database.rawQuery("SELECT revision FROM observations WHERE id=? AND deleted=0", arrayOf(record.id))
                .use { if (it.moveToFirst()) it.getInt(0) else 0 }
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
            database.delete("drafts", "draft_key=?", arrayOf(draftKey(draft)))
            database.setTransactionSuccessful()
            HealthSaveResult.Saved(record)
        } finally { database.endTransaction(); encrypted.fill(0) }
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
                database.delete("drafts", "draft_key=?", arrayOf("edit:$id"))
                database.setTransactionSuccessful()
                true
            } finally { encrypted.fill(0) }
        } finally { database.endTransaction() }
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

    private class Database(context: Context, name: String) : SQLiteOpenHelper(context, name, null, 2) {
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
        }
        override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
            check(oldVersion == 1 && newVersion == 2) { "Unsupported health schema upgrade" }
            db.execSQL("ALTER TABLE observations ADD COLUMN original_id TEXT")
            db.execSQL("ALTER TABLE observations ADD COLUMN evidence_key TEXT")
            db.execSQL("CREATE INDEX observation_original_page ON observations(original_id,deleted,measured_at DESC,id DESC)")
            db.execSQL("CREATE UNIQUE INDEX observation_evidence ON observations(evidence_key) WHERE deleted=0 AND evidence_key IS NOT NULL")
        }
    }
    companion object {
        const val PAGE_SIZE = 30
        fun draftKey(draft: HealthDraft) = when {
            draft.recordId.isNotBlank() -> "edit:${draft.recordId}"
            draft.evidence != null -> "ocr:${draft.evidence.jobId}:${draft.evidence.page}:${draft.evidence.candidateId}"
            else -> "new:${draft.metric.name}"
        }
    }
}

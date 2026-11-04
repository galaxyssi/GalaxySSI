package com.galaxyssi.chat

import android.content.ContentValues
import android.database.sqlite.SQLiteDatabase
import org.json.JSONObject

internal enum class HealthRestoreKind { NEW, DUPLICATE, CONFLICT }
internal data class HealthRestoreMatch(val kind: HealthRestoreKind, val existing: HealthObservation? = null, val deleted: Boolean = false)
internal data class HealthRestoreConflict(val record: HealthObservation, val existing: HealthObservation?, val deleted: Boolean)
internal data class HealthRestoreConflictPage(val rows: List<HealthRestoreConflict>, val next: String?)
internal data class HealthRestoreOriginalState(val duplicate: HealthOriginal?, val available: Boolean, val sameId: HealthOriginal?)
internal data class HealthRestorePreparedOriginal(val original: HealthOriginal, val wrappedKey: ByteArray, val present: Boolean)

internal data class HealthRestoreSourceLink(val recordId: String, val revision: Int, val metric: HealthMetric, val evidence: HealthEvidence) {
    fun json() = JSONObject().put("record", recordId).put("revision", revision).put("metric", metric.name).put("evidence", evidence.json())
    companion object {
        fun from(j: JSONObject) = HealthRestoreSourceLink(j.getString("record"), j.getInt("revision"),
            HealthMetric.valueOf(j.getString("metric")), HealthEvidence.from(j.getJSONObject("evidence")))
    }
}

internal data class HealthRestoreCounts(val added: Long, val duplicates: Long, val conflicts: Long,
    val originalsAdded: Int, val originalsReused: Int, val repaired: Int, val missing: Int,
    val sourcesAdded: Long = 0, val sourcesReused: Long = 0, val sourcesSkipped: Long = 0) {
    fun json() = JSONObject().put("added", added).put("duplicates", duplicates).put("conflicts", conflicts)
        .put("originals_added", originalsAdded).put("originals_reused", originalsReused).put("repaired", repaired).put("missing", missing)
        .put("sources_added", sourcesAdded).put("sources_reused", sourcesReused).put("sources_skipped", sourcesSkipped)
    companion object {
        fun from(j: JSONObject) = HealthRestoreCounts(j.getLong("added"), j.getLong("duplicates"), j.getLong("conflicts"),
            j.getInt("originals_added"), j.getInt("originals_reused"), j.getInt("repaired"), j.getInt("missing"),
            j.optLong("sources_added"), j.optLong("sources_reused"), j.optLong("sources_skipped"))
    }
}
internal data class HealthRestoreReceipt(val id: String, val packageId: String, val createdAt: Long,
    val counts: HealthRestoreCounts, val first: Long, val last: Long)
internal class HealthRestoreChanged : IllegalStateException()
internal class HealthRestoreOwnerMismatch : IllegalStateException()
internal class HealthRestoreOriginalUnavailable : IllegalStateException()

internal object HealthRestoreReceipts {
    fun createSchema(db: SQLiteDatabase) {
        db.execSQL("CREATE TABLE health_restore_batches(id TEXT PRIMARY KEY,package_id TEXT NOT NULL,created_at INTEGER NOT NULL,payload BLOB NOT NULL)")
        db.execSQL("CREATE INDEX health_restore_batch_time ON health_restore_batches(created_at DESC,id DESC)")
    }

    private fun aad(db: SQLiteDatabase, id: String, packageId: String, created: Long) =
        "health-restore-receipt-v1|${db.path}|$id|$packageId|$created".toByteArray(Charsets.UTF_8)

    fun insert(db: SQLiteDatabase, receipt: HealthRestoreReceipt) {
        check(db.inTransaction())
        val bytes = receipt.counts.json().put("first", receipt.first).put("last", receipt.last).toString().toByteArray(Charsets.UTF_8)
        try {
            val sealed = AgentStorageCipher.encryptBinary(bytes, aad(db, receipt.id, receipt.packageId, receipt.createdAt))
            db.insertOrThrow("health_restore_batches", null, ContentValues().apply {
                put("id", receipt.id); put("package_id", receipt.packageId); put("created_at", receipt.createdAt); put("payload", sealed)
            })
        } finally { bytes.fill(0) }
    }

    fun committed(db: SQLiteDatabase, id: String) = db.rawQuery("SELECT 1 FROM health_restore_batches WHERE id=?", arrayOf(id))
        .use { it.moveToFirst() }

    fun recent(db: SQLiteDatabase): List<HealthRestoreReceipt> =
        db.rawQuery("SELECT id,package_id,created_at,payload FROM health_restore_batches ORDER BY created_at DESC,id DESC LIMIT 10", null)
            .use { rows -> buildList {
                while (rows.moveToNext()) {
                    val id = rows.getString(0); val packageId = rows.getString(1); val time = rows.getLong(2)
                    val bytes = AgentStorageCipher.decryptBinary(rows.getBlob(3), aad(db, id, packageId, time))
                    try {
                        val value = JSONObject(String(bytes, Charsets.UTF_8))
                        add(HealthRestoreReceipt(id, packageId, time, HealthRestoreCounts.from(value), value.getLong("first"), value.getLong("last")))
                    }
                    finally { bytes.fill(0) }
                }
            } }
}

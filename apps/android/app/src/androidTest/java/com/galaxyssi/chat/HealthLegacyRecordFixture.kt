package com.galaxyssi.chat

import android.content.ContentValues
import android.content.Context

internal fun seedLegacyHealthObservation(context: Context, name: String, version: Int, draft: HealthDraft): HealthObservation {
    require(version in 2..5 && !context.getDatabasePath(name).exists())
    val record = HealthObservationPolicy.observation(draft)
    val plain = record.json().toString().toByteArray()
    val encrypted = try { AgentStorageCipher.encryptBinary(plain, "$name|health|${record.id}|1".toByteArray()) } finally { plain.fill(0) }
    try {
        context.openOrCreateDatabase(name, 0, null).use { db ->
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
            if (version >= 3) HealthTableStore.createSchema(db)
            if (version >= 4) db.execSQL("CREATE TABLE health_metric_clocks(metric TEXT PRIMARY KEY,token TEXT NOT NULL)")
            if (version >= 5) {
                db.execSQL("ALTER TABLE observations ADD COLUMN external_key TEXT")
                db.execSQL("CREATE UNIQUE INDEX observation_external ON observations(external_key) WHERE external_key IS NOT NULL")
            }
            db.insertOrThrow("observations", null, ContentValues().apply {
                put("id", record.id); put("revision", 1); put("metric", draft.metric.name); put("measured_at", draft.measuredAt)
                put("payload", encrypted); put("original_id", draft.evidence?.originalId)
                put("dedupe", AgentMemoryIndexKey.token("$name|health-duplicate-v1|${HealthObservationPolicy.duplicateKey(record)}"))
                draft.evidence?.let {
                    put("evidence_key", AgentMemoryIndexKey.token("$name|health-evidence-v1|${it.originalId}|${it.page}|${it.candidateId}|${draft.metric.name}"))
                }
            })
            db.insertOrThrow("revisions", null, ContentValues().apply {
                put("id", record.id); put("revision", 1); put("payload", encrypted)
                put("changed_at", record.receivedAt); put("deleted", 0)
            })
            db.version = version
        }
        return record
    } finally { encrypted.fill(0) }
}

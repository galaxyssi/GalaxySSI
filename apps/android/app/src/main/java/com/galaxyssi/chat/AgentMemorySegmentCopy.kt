package com.galaxyssi.chat

import android.content.ContentValues
import android.database.sqlite.SQLiteDatabase

/** The pending job pins both files: maintenance services it before any segment reclamation. */
internal class AgentMemorySegmentCopy(private val sql: SQLiteDatabase,
    private val segments: AgentMemoryPayloadSegments, private val aad: (String) -> ByteArray) {
    fun resume(checkActive: () -> Unit): AgentMemorySegmentMaintenance.Result? {
        val job = segments.catalog.copyJob() ?: return null
        checkActive()
        val scope = aad(job.key)
        val state = segments.copyState(job, scope)
        val current = sql.rawQuery("SELECT 1 FROM encrypted_values WHERE storage_key=? AND encrypted_value=? LIMIT 1",
            arrayOf(job.key, job.value)).use { it.moveToFirst() }
        if (!current) {
            // This also handles a completed source commit followed by process death before job cleanup.
            // Reclamation checks live SQL references, so a committed destination cannot be deleted.
            val published = sql.rawQuery("SELECT encrypted_value FROM encrypted_values WHERE storage_key=? " +
                "AND segment_id=? AND length(encrypted_value)<=256 LIMIT 1", arrayOf(job.key, job.destination)).use {
                if (it.moveToFirst()) it.getString(0) else null
            }
            if (published != null) {
                check(state.complete && segments.isCopiedReference(published, state, scope)) { "Invalid published memory copy" }
                segments.copyStep(state, scope, checkActive)
            }
            segments.catalog.finishCopy(job)
            return AgentMemorySegmentMaintenance.Result(1, 0, 0, 0, false)
        }
        val next = segments.copyStep(state, scope, checkActive)
        val saved = if (next == state) job else segments.checkpointCopy(job, next, scope)
        if (!next.complete) return AgentMemorySegmentMaintenance.Result(1, 0, 0, 0, false)
        checkActive()
        val reference = segments.copiedReference(next, scope)
        val values = ContentValues().apply {
            put("encrypted_value", reference.value); put("segment_id", reference.segment); put("segment_bytes", reference.bytes)
        }
        sql.beginTransactionNonExclusive()
        try {
            check(sql.update("encrypted_values", values, "storage_key=? AND encrypted_value=?",
                arrayOf(job.key, job.value)) == 1) { "Memory changed during copy publication" }
            sql.setTransactionSuccessful()
        } finally { sql.endTransaction() }
        segments.catalog.finishCopy(saved)
        return AgentMemorySegmentMaintenance.Result(1, 1, 0, 0, false)
    }
}

package com.galaxyssi.chat

import android.util.Base64

/** A persisted copy job pins both files; all reclamation services it before visiting the catalog. */
internal class KnowledgePayloadCopy(private val segments: KnowledgePayloadSegments) {
    fun begin(row: KnowledgePayloadCompaction.Row, segment: String) {
        val source = segments.decodeReference(row.key, row.value)
        check(source.segment.toString() == segment && source.length == row.bytes) { "Payload copy membership mismatch" }
        val state = segments.files.beginCopy(source)
        segments.catalog.beginCopy(AgentMemorySegmentCatalog.CopyJob(row.key, row.value, segment,
            state.destination.toString(), encode(row.key, state)))
    }

    fun resume(db: KnowledgeSqlite, checkActive: () -> Unit): Boolean {
        val job = segments.catalog.copyJob() ?: return false
        checkActive()
        val state = decode(job)
        val current = db.rawQuery("SELECT reference,segment,bytes FROM knowledge_payloads WHERE item_key=?",
            arrayOf(job.key)).use { c -> if (c.moveToFirst()) Triple(c.getString(0), c.getString(1), c.getLong(2)) else null }
        if (current?.first != job.value) {
            if (current?.second == job.destination) {
                check(state.complete && segments.decodeReference(job.key, current.first) == state.target &&
                    current.third == state.target.length) { "Invalid published knowledge copy" }
                segments.files.copyStep(state, segments.aad(job.key), COPY_BUDGET, checkActive)
            }
            // A committed publication or a later user write made the old job obsolete. Never remove files here.
            segments.catalog.finishCopy(job)
            return true
        }
        val observed = requireNotNull(current)
        check(observed.second == job.source && observed.third == state.source.length) { "Payload copy source changed" }
        val next = segments.files.copyStep(state, segments.aad(job.key), COPY_BUDGET, checkActive)
        if (next != state) segments.catalog.checkpointCopy(job, job.copy(checkpoint = encode(job.key, next)))
        if (next.complete) {
            KnowledgePayloadCompaction.publish(db, KnowledgePayloadCompaction.Row(job.key, job.value, observed.third),
                segments.encodeReference(job.key, next.target))
            // Keep the complete job until a later transaction observes the committed destination reference.
        }
        return true
    }

    internal fun decode(job: AgentMemorySegmentCatalog.CopyJob): MemorySegmentCopy.State {
        require(job.checkpoint.length <= 512) { "Invalid knowledge copy checkpoint size" }
        val cipher = Base64.decode(job.checkpoint, Base64.NO_WRAP)
        val plain = try { AgentStorageCipher.decryptBinary(cipher, segments.copyAad(job.key)) } finally { cipher.fill(0) }
        val state = try { MemorySegmentCopy.State.parse(plain) } finally { plain.fill(0) }
        check(state.source == segments.decodeReference(job.key, job.value) &&
            state.source.segment.toString() == job.source && state.destination.toString() == job.destination) {
            "Knowledge copy checkpoint identity mismatch"
        }
        return state
    }

    private fun encode(key: String, state: MemorySegmentCopy.State): String {
        val plain = state.bytes()
        val cipher = try { AgentStorageCipher.encryptBinary(plain, segments.copyAad(key)) } finally { plain.fill(0) }
        return try { Base64.encodeToString(cipher, Base64.NO_WRAP) } finally { cipher.fill(0) }
    }

    companion object { const val COPY_BUDGET = 1024 * 1024 }
}

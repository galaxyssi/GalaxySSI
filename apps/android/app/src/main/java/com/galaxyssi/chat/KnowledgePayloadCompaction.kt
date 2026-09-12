package com.galaxyssi.chat

/** Exclusive lease plus source writer reservation. Never remove a file relocated in this transaction. */
internal class KnowledgePayloadCompaction(private val segments: KnowledgePayloadSegments) {
    data class Row(val key: String, val value: String, val bytes: Long)

    fun run(db: KnowledgeSqlite, limit: Int, checkActive: () -> Unit): KnowledgePayloadSegments.Reclaimed {
        require(limit in 1..32)
        checkActive()
        if (!KnowledgePayloadUsage.ready(db)) return pending()
        if (KnowledgePayloadCopy(segments).resume(db, checkActive)) return pending()
        var removed = 0L
        var last: Long? = null
        for (entry in segments.catalog.next(limit)) {
            try { checkActive() } catch (yield: MemoryMaintenanceYield) {
                if (last == null) throw yield
                return KnowledgePayloadSegments.Reclaimed(removed, false)
            }
            val segment = entry.segment.toString()
            val live = db.rawQuery("SELECT 1 FROM knowledge_payloads WHERE segment=? LIMIT 1",
                arrayOf(segment)).use { it.moveToFirst() }
            if (live) {
                val bytes = KnowledgePayloadUsage.bytes(db, segment)
                val size = segments.files.size(entry.segment)
                check(bytes > 0 && bytes <= size) { "Knowledge payload live-byte accounting mismatch" }
                if (bytes <= size / 2) {
                    val rows = db.rawQuery("SELECT item_key,reference,bytes FROM knowledge_payloads " +
                        "WHERE segment=? ORDER BY item_key LIMIT 8", arrayOf(segment)).use { c -> buildList {
                        while (c.moveToNext()) add(Row(c.getString(0), c.getString(1), c.getLong(2)))
                    } }
                    segments.files.seal(entry.segment)
                    var remaining = COPY_BYTES
                    var moved = 0
                    for (row in rows) {
                        try { checkActive() } catch (yield: MemoryMaintenanceYield) {
                            if (moved == 0) throw yield
                            break
                        }
                        if (row.bytes > COPY_BYTES && moved == 0) {
                            KnowledgePayloadCopy(segments).begin(row, segment)
                            return KnowledgePayloadSegments.Reclaimed(removed, false)
                        }
                        if (row.bytes > remaining) break
                        val reference = segments.decodeReference(row.key, row.value)
                        check(reference.segment == entry.segment && reference.length == row.bytes) { "Payload membership mismatch" }
                        // At most 1 MiB per transaction. Larger records use durable frame checkpoints.
                        val next = segments.files.relocate(reference, segments.aad(row.key))
                        publish(db, row, segments.encodeReference(row.key, next))
                        remaining -= row.bytes; moved++
                    }
                    check(moved > 0) { "Knowledge compaction made no progress" }
                    segments.catalog.advance(entry, removed = false, revisit = true)
                    // Commit new references first. A later transaction checks durable membership and reclaims.
                    return KnowledgePayloadSegments.Reclaimed(removed, false)
                }
            } else removed = Math.addExact(removed, segments.files.remove(entry.segment))
            segments.catalog.advance(entry, removed = !live)
            last = entry.id
        }
        return KnowledgePayloadSegments.Reclaimed(removed, last?.let { !segments.catalog.hasAfter(it) } ?: true)
    }

    companion object {
        const val COPY_BYTES = 1024L * 1024
        fun publish(db: KnowledgeSqlite, row: Row, values: android.content.ContentValues) {
            db.update("knowledge_payloads", values, "item_key=? AND reference=? AND bytes=?",
                arrayOf(row.key, row.value, row.bytes.toString()))
            db.rawQuery("SELECT changes()", null).use {
                check(it.moveToFirst() && it.getLong(0) == 1L) { "Knowledge payload changed during copy publication" }
            }
        }
        private fun pending() = KnowledgePayloadSegments.Reclaimed(0, false)
    }
}

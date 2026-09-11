package com.galaxyssi.chat

import android.content.ContentValues
import android.database.sqlite.SQLiteDatabase
import java.util.UUID

/** Bounded maintenance, under exclusive segment access. Never runs in a source transaction. */
internal class AgentMemorySegmentMaintenance(private val sql: SQLiteDatabase,
    private val segments: AgentMemoryPayloadSegments, private val aad: (String) -> ByteArray) {
    data class Result(val visited: Int, val moved: Int, val removed: Int, val reclaimedBytes: Long,
        val cycleComplete: Boolean)
    private data class Row(val key: String, val value: String, val bytes: Long)

    fun run(maxSegments: Int, maxRows: Int, checkActive: () -> Unit = {}): Result {
        require(maxSegments in 1..32 && maxRows in 1..32)
        check(!sql.inTransaction()) { "Memory maintenance must not join an application transaction" }
        AgentMemorySegmentCopy(sql, segments, aad).resume(checkActive)?.let { return it }
        var visited = 0; var moved = 0; var removed = 0; var reclaimed = 0L
        var remainingBytes = COPY_BYTES
        var lastId: Long? = null
        checkActive()
        for (entry in segments.catalog.next(maxSegments)) {
            checkActive()
            visited++
            val movedBefore = moved
            if (referenced(entry.segment) && moved < maxRows) {
                val live = sql.rawQuery("SELECT coalesce(sum(segment_bytes),0) FROM encrypted_values WHERE segment_id=?",
                    arrayOf(entry.segment.toString())).use { check(it.moveToFirst()); it.getLong(0) }
                if (live > 0 && live <= segments.size(entry.segment) / 2) {
                    val rows = rows(entry.segment, maxRows - moved)
                    segments.seal(entry.segment)
                    rows.firstOrNull()?.takeIf { it.bytes > COPY_BYTES }?.let { row ->
                        checkActive()
                        segments.beginCopy(row.key, row.value, aad(row.key), entry.segment, row.bytes)
                        return Result(visited, moved, removed, reclaimed, false)
                    }
                    sql.beginTransactionNonExclusive()
                    try {
                        for (row in rows) {
                            checkActive()
                            if (row.bytes > remainingBytes) break
                            val next = segments.relocate(row.key, row.value, aad(row.key), entry.segment, row.bytes, checkActive)
                            val values = ContentValues().apply {
                                put("encrypted_value", next.value); put("segment_id", next.segment); put("segment_bytes", next.bytes)
                            }
                            check(sql.update("encrypted_values", values, "storage_key=? AND encrypted_value=?",
                                arrayOf(row.key, row.value)) == 1) { "Memory changed during exclusive compaction" }
                            remainingBytes -= row.bytes; moved++
                        }
                        checkActive()
                        sql.setTransactionSuccessful()
                    } finally { sql.endTransaction() }
                }
            }
            val disposable = !referenced(entry.segment)
            if (disposable) { reclaimed = Math.addExact(reclaimed, segments.remove(entry.segment)); removed++ }
            val revisit = !disposable && moved > movedBefore
            segments.catalog.advance(entry, disposable, revisit)
            if (revisit) return Result(visited, moved, removed, reclaimed, false)
            lastId = entry.id
        }
        return Result(visited, moved, removed, reclaimed, lastId?.let { !segments.catalog.hasAfter(it) } ?: true)
    }

    private fun referenced(id: UUID) = sql.rawQuery(
        "SELECT 1 FROM encrypted_values WHERE segment_id=? LIMIT 1", arrayOf(id.toString())
    ).use { it.moveToFirst() }

    private fun rows(id: UUID, limit: Int) = sql.rawQuery(
        "SELECT storage_key,encrypted_value,segment_bytes FROM encrypted_values WHERE segment_id=? ORDER BY storage_key LIMIT ?",
        arrayOf(id.toString(), limit.toString())
    ).use { c -> buildList {
        while (c.moveToNext()) {
            val row = Row(c.getString(0), c.getString(1), c.getLong(2))
            check(row.bytes > 0 && row.value.startsWith(AgentMemoryPayloadSegments.PREFIX)) { "Invalid memory segment catalog row" }
            add(row)
        }
    } }

    private companion object { const val COPY_BYTES = 1024L * 1024 }
}

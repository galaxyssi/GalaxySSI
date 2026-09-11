package com.galaxyssi.chat

import android.content.ContentValues
import android.os.Looper

internal data class KnowledgeVectorFeedState(val epoch: String, val head: Long, val completedChunks: Long,
    val bootstrapAfter: String, val bootstrapComplete: Boolean)
internal data class KnowledgeVectorChange(val sequence: Long, val key: String, val removed: Boolean,
    val revision: String, val chunkCount: Int)
internal data class KnowledgeVectorChangePage(val state: KnowledgeVectorFeedState, val rows: List<KnowledgeVectorChange>,
    val nextSequence: Long, val hasMore: Boolean)

/** Bounded keyset replay. No automatic truncation before a native consumer has durably applied a checkpoint. */
internal class KnowledgeVectorChanges(private val storage: AgentKnowledgeDatabase, private val modelKey: String) {
    fun state(): KnowledgeVectorFeedState? = storage.access(::state)

    internal fun state(db: KnowledgeSqlite): KnowledgeVectorFeedState? = db.rawQuery(
        "SELECT CASE WHEN length(epoch)=32 THEN epoch ELSE '' END,head,completed_chunks," +
            "CASE WHEN length(bootstrap_after)<=64 THEN bootstrap_after ELSE 'invalid' END,bootstrap_complete " +
            "FROM knowledge_vector_feed_state WHERE model_key=?", arrayOf(modelKey)).use {
        if (!it.moveToFirst()) return@use null
        val result = KnowledgeVectorFeedState(it.getString(0), it.getLong(1), it.getLong(2), it.getString(3), it.getLong(4) == 1L)
        check(result.epoch.matches(EPOCH) && result.head >= 0 && result.completedChunks >= 0)
        check(result.bootstrapAfter.isEmpty() || result.bootstrapAfter.matches(HASH))
        check(it.getLong(4) in 0L..1L)
        result
    }

    fun page(epoch: String, after: Long = 0, limit: Int = 128): KnowledgeVectorChangePage = storage.access { db ->
        require(after >= 0 && limit in 1..512)
        val current = requireNotNull(state(db)) { "Vector change feed is not registered" }
        check(current.epoch == epoch) { "Vector change feed was replaced; rebuild this consumer" }
        require(after <= current.head) { "Vector change checkpoint is ahead of its source" }
        val rows = db.rawQuery("SELECT sequence,CASE WHEN length(item_key)=64 THEN item_key ELSE '' END,operation," +
            "CASE WHEN length(revision)=64 THEN revision ELSE '' END,chunk_count,previous FROM knowledge_vector_changes " +
            "WHERE model_key=? AND sequence>? AND sequence<=? ORDER BY sequence LIMIT ?",
            arrayOf(modelKey, after.toString(), current.head.toString(), limit.toString())).use { cursor ->
            buildList {
                var previous = after
                while (cursor.moveToNext()) {
                    val sequence = cursor.getLong(0)
                    val count = cursor.getLong(4)
                    val key = cursor.getString(1)
                    val revision = cursor.getString(3)
                    check(cursor.getLong(5) == previous) { "Vector change history has a gap; rebuild this consumer" }
                    check(sequence > previous && sequence <= current.head && count in 0..Int.MAX_VALUE.toLong())
                    check(cursor.getLong(2) in 0L..1L && key.matches(HASH) && revision.matches(HASH))
                    add(KnowledgeVectorChange(sequence, key, cursor.getLong(2) == 0L, revision, count.toInt()))
                    previous = sequence
                }
            }
        }
        check(rows.isNotEmpty() || after == current.head) { "Vector change history is missing; rebuild this consumer" }
        val next = rows.lastOrNull()?.sequence ?: after
        KnowledgeVectorChangePage(current, rows, next, next < current.head)
    }

    /** One restartable legacy backfill page; it must never run on the UI thread. */
    fun bootstrap(limit: Int = 64): Boolean {
        check(Looper.myLooper() != Looper.getMainLooper()) { "Vector change backfill requires a worker thread" }
        require(limit in 1..256)
        return storage.transaction { db ->
            val current = requireNotNull(state(db)) { "Register the vector model before backfill" }
            if (current.bootstrapComplete) return@transaction true
            val keys = db.rawQuery("SELECT item_key FROM knowledge_vector_docs WHERE model_key=? AND complete=1 " +
                "AND item_key>? ORDER BY item_key LIMIT ?", arrayOf(modelKey, current.bootstrapAfter, limit.toString())).use {
                buildList { while (it.moveToNext()) add(it.getString(0).also { key -> check(key.matches(HASH)) }) }
            }
            for (key in keys) db.update("knowledge_vector_docs", ContentValues().apply { put("feed_tracked", 1) },
                "model_key=? AND item_key=? AND complete=1 AND feed_tracked=0", arrayOf(modelKey, key))
            val complete = keys.size < limit
            db.update("knowledge_vector_feed_state", ContentValues().apply {
                put("bootstrap_after", keys.lastOrNull() ?: current.bootstrapAfter)
                put("bootstrap_complete", if (complete) 1 else 0)
            }, "model_key=?", arrayOf(modelKey))
            complete
        }
    }
    companion object {
        private val HASH = Regex("[a-f0-9]{64}")
        private val EPOCH = Regex("[a-f0-9]{32}")
    }
}

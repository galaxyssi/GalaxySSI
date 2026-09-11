package com.galaxyssi.chat

import android.os.Looper

internal data class KnowledgeVectorBatchResult(val committedChunks: Int, val staleResults: Int, val pending: Boolean)

/** One bounded work quantum, not a lifetime action cap. Resume calls continue committed checkpoints. */
internal class KnowledgeVectorIndexer(private val ledger: KnowledgeVectorLedger, private val encoder: KnowledgeVectorEncoder) {
    init { require(ledger.spec == encoder.spec) }

    fun runBatch(maxChunks: Int = 8, cancelled: () -> Boolean = { false }): KnowledgeVectorBatchResult {
        check(Looper.myLooper() != Looper.getMainLooper()) { "Vector indexing must run off the UI thread" }
        require(maxChunks in 1..256)
        if (cancelled()) return KnowledgeVectorBatchResult(0, 0, true)
        ledger.ensureRegistered()
        if (!ledger.changes().bootstrap()) return KnowledgeVectorBatchResult(0, 0, true)
        var committed = 0
        var stale = 0
        var current: KnowledgeVectorJob? = null
        repeat(maxChunks) {
            if (cancelled()) return KnowledgeVectorBatchResult(committed, stale, true)
            val job = current ?: ledger.nextJob() ?: return KnowledgeVectorBatchResult(committed, stale, false)
            // Model work happens outside the database transaction and its monitor.
            val chunk = KnowledgeEmbeddingChunks.next(job.item.content, job.next, encoder.spec.contextTokens, encoder::tokenCount)
            if (chunk == null) {
                if (!ledger.finishWhitespace(job)) stale++
                current = null
            } else {
                val vector = encoder.embed(chunk.text)
                try {
                    if (cancelled()) return KnowledgeVectorBatchResult(committed, stale, true)
                    if (ledger.append(job, chunk, vector)) {
                        committed++
                        current = if (chunk.next == job.item.content.length) null
                            else job.copy(next = chunk.next, count = job.count + 1)
                    } else { stale++; current = null }
                } finally { vector.fill(0f) }
            }
        }
        return KnowledgeVectorBatchResult(committed, stale, true)
    }
}

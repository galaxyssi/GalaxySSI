package com.galaxyssi.chat

import java.io.Closeable
import java.util.concurrent.atomic.AtomicLong

/** A bounded replay slice per call; the caller schedules further work off the UI thread. */
internal class KnowledgeNativeIndex(private val storage: AgentKnowledgeDatabase, private val spec: KnowledgeVectorSpec,
    private val cacheBytes: Long) : Closeable {
    private val ledger = storage.vectors(spec)
    private val feed = ledger.changes()
    private val handle = AtomicLong()
    private var sourceEpoch = ""
    var needsMaintenance = false
        private set
    var readyStamp: KnowledgeCorpusStamp? = null
        private set

    /** Inspect/reopen a committed graph without registration, backfill or vector replay. */
    fun tryReady(active: () -> Unit): Boolean {
        validateBudget()
        active()
        val state = feed.state()
        if (state == null || !state.bootstrapComplete) { readyStamp = null; return false }
        val stamp = KnowledgeCorpusStamp(state.epoch, state.head, state.completedChunks)
        if (readyStamp == stamp) return true
        readyStamp = null
        if (sourceEpoch != state.epoch) { close(); sourceEpoch = state.epoch }
        if (handle.get() == 0L) {
            val files = KnowledgeNativeFiles(storage.nativeIndexDirectory(ledger.modelKey), ledger.modelKey, state.epoch)
            if (!files.directory.exists()) {
                if (state.completedChunks != 0L) return false
                active()
                readyStamp = stamp
                return true
            }
            active()
            // A null root opens an existing authenticated index; it cannot create a graph.
            handle.set(files.open(spec.dimensions, cacheBytes, null).also { check(it > 0) })
            needsMaintenance = !KnowledgeNativeBridge.recordsPartitioned(handle.get())
        }
        active()
        val checkpoint = KnowledgeNativeWire.checkpoint(KnowledgeNativeBridge.checkpoint(handle.get()))
        check(checkpoint.epoch == state.epoch)
        if (checkpoint.sequence != state.head || checkpoint.pending != null) return false
        active()
        readyStamp = stamp
        return true
    }

    private fun validateBudget() {
        check(cacheBytes >= (KnowledgeNativeFiles.SHARDS + 1) * 16L * 1024) { "Insufficient native pager budget" }
    }

    /** Background maintenance only; ready foreground reads never migrate records. */
    fun advance(active: () -> Unit): Boolean {
        val caughtUp = tryReady(active) || synchronize(active = active)
        active()
        val id = handle.get()
        val partitioned = id == 0L || !needsMaintenance || KnowledgeNativeBridge.migrateRecords(id)
        needsMaintenance = !partitioned
        active()
        return caughtUp && partitioned
    }

    fun synchronize(maxPages: Int = 4, active: () -> Unit): Boolean {
        require(maxPages in 1..16)
        validateBudget()
        readyStamp = null
        ledger.ensureRegistered()
        active()
        if (!feed.bootstrap()) return false
        val state = requireNotNull(feed.state())
        if (sourceEpoch != state.epoch) { close(); sourceEpoch = state.epoch }
        val files = KnowledgeNativeFiles(storage.nativeIndexDirectory(ledger.modelKey), ledger.modelKey, state.epoch)
        if (handle.get() == 0L) {
            val root = if (files.directory.exists()) null else firstVector(active)
            if (root == null && !files.directory.exists()) {
                check(state.completedChunks == 0L) { "Completed vector source is missing" }
                readyStamp = KnowledgeCorpusStamp(state.epoch, state.head, 0)
                return true
            }
            active()
            val opened = try { files.open(spec.dimensions, cacheBytes, root) } finally { root?.fill(0f) }
            check(opened > 0)
            handle.set(opened)
            needsMaintenance = !KnowledgeNativeBridge.recordsPartitioned(opened)
            active()
        }
        repeat(maxPages) {
            active()
            val id = handle.get().also { check(it > 0) }
            val checkpoint = KnowledgeNativeWire.checkpoint(KnowledgeNativeBridge.checkpoint(id))
            check(checkpoint.epoch == state.epoch)
            val page = feed.page(state.epoch, checkpoint.sequence, 1)
            if (page.rows.isEmpty()) {
                check(checkpoint.pending == null)
                readyStamp = KnowledgeCorpusStamp(page.state.epoch, page.state.head, page.state.completedChunks)
                return true
            }
            val change = page.rows.single()
            val event = KnowledgeNativeEvent(change.sequence, checkpoint.sequence, change.key, change.revision, change.chunkCount.toLong(), change.removed)
            if (checkpoint.pending != null) check(checkpoint.pending.event == event) { "Native replay event no longer matches the source feed" }
            val encoded = KnowledgeNativeWire.event(event)
            try {
                if (change.removed) {
                    KnowledgeNativeWire.checkpoint(KnowledgeNativeBridge.beginEvent(id, encoded, false))
                } else {
                    val next = checkpoint.pending?.next ?: 0
                    check(next <= Int.MAX_VALUE)
                    ledger.pageByKey(change.key, next.toInt(), 64, active).use { vectors ->
                        val obsolete = vectors == null || vectors.revision != change.revision || vectors.total != change.chunkCount
                        KnowledgeNativeWire.checkpoint(KnowledgeNativeBridge.beginEvent(id, encoded, obsolete))
                        if (!obsolete && vectors!!.rows.isNotEmpty()) {
                            active()
                            append(id, encoded, vectors)
                        }
                    }
                }
            } finally { encoded.fill(0) }
        }
        active()
        val final = KnowledgeNativeWire.checkpoint(KnowledgeNativeBridge.checkpoint(handle.get()))
        val current = requireNotNull(feed.state())
        if (current.epoch == final.epoch && current.head == final.sequence && final.pending == null) {
            readyStamp = KnowledgeCorpusStamp(current.epoch, current.head, current.completedChunks)
            return true
        }
        return false
    }

    private fun append(id: Long, event: ByteArray, page: KnowledgeVectorPage) {
        val metadata = LongArray(page.rows.size * 3)
        val values = FloatArray(page.rows.size * spec.dimensions)
        try {
            page.rows.forEachIndexed { index, row ->
                metadata[index * 3] = row.ordinal.toLong(); metadata[index * 3 + 1] = row.start.toLong(); metadata[index * 3 + 2] = row.end.toLong()
                row.values.copyInto(values, index * spec.dimensions)
            }
            KnowledgeNativeWire.checkpoint(KnowledgeNativeBridge.append(id, event, metadata, values))
        } finally { metadata.fill(0); values.fill(0f) }
    }
    private fun firstVector(active: () -> Unit): FloatArray? {
        val key = storage.access { db -> db.rawQuery("SELECT item_key FROM knowledge_vector_docs WHERE model_key=? " +
            "AND complete=1 AND chunk_count>0 ORDER BY item_key LIMIT 1", arrayOf(ledger.modelKey)).use {
            if (it.moveToFirst()) it.getString(0) else null
        } } ?: return null
        active()
        return ledger.pageByKey(key, 0, 1, active)?.use { page -> page.rows.firstOrNull()?.values?.copyOf() }
    }
    fun search(query: FloatArray): List<KnowledgeVectorMatch> {
        val stamp = requireNotNull(readyStamp) { "Native replay is not current" }
        if (stamp.completedChunks == 0L) return emptyList()
        val id = handle.get().also { check(it > 0) }
        return KnowledgeNativeWire.matches(KnowledgeNativeBridge.search(id, query, 128, 256))
    }
    internal fun physicalNodeCount(): Long = handle.get().let { if (it == 0L) 0 else KnowledgeNativeBridge.nodeCount(it) }
    fun cancel() { handle.get().takeIf { it != 0L }?.let(KnowledgeNativeBridge::cancel) }
    override fun close() {
        handle.getAndSet(0).takeIf { it != 0L }?.let(KnowledgeNativeBridge::closeIndex)
        readyStamp = null
        needsMaintenance = false
    }
}

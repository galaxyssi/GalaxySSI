package com.galaxyssi.chat

import android.os.Looper
import java.io.Closeable
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong

/** Optional, independently owned embedding session used by the normal store/RAG search path. */
internal class KnowledgeSemanticSearch(
    private val storage: AgentKnowledgeDatabase, private val spec: KnowledgeVectorSpec,
    private val encoderFactory: () -> KnowledgeVectorEncoder,
    private val budgetBytes: Long = minOf(64L * 1024 * 1024, Runtime.getRuntime().maxMemory() / 8),
    private val ttlMillis: Long = 30_000
) : Closeable {
    private data class Snapshot(val stamp: KnowledgeCorpusStamp, val graph: KnowledgeHnswIndex, val epoch: Long,
        val expiresAtNs: Long)
    private val lock = Any()
    private val epoch = AtomicLong()
    private val closed = AtomicBoolean()
    private val ledger = storage.vectors(spec)
    private val catalog = KnowledgeVectorCatalog(storage, ledger)
    private var snapshot: Snapshot? = null
    private var encoder: KnowledgeVectorEncoder? = null
    @Volatile var status: String = "not_built"
        private set
    init { require(ttlMillis > 0 && budgetBytes > 0); sessions.add(this) }

    fun search(query: String, limit: Int, lexical: () -> List<AgentKnowledgeHit>): List<AgentKnowledgeHit> {
        require(limit in 1..24)
        if (Looper.myLooper() == Looper.getMainLooper()) { status = "requires_worker_thread"; return lexical().take(limit) }
        if (closed.get() || suspended.get()) { status = "suspended"; return lexical().take(limit) }
        return synchronized(lock) {
            var expected = epoch.get()
            try {
                ensureActive(expected)
                val cached = snapshot?.takeIf { it.epoch == expected && System.nanoTime() < it.expiresAtNs && it.stamp == catalog.stamp() }
                val current = cached ?: run {
                    check(epoch.compareAndSet(expected, expected + 1)) { "Semantic retrieval invalidated" }
                    expected++
                    dispose()
                    build(expected).also { snapshot = it }
                }
                val active = encoder ?: encoderFactory().also { opened ->
                    if (opened.spec != spec) { opened.close(); error("Embedding model specification changed") }
                    encoder = opened
                }
                ensureActive(expected)
                val queryVector = active.embed(query)
                val matches = try { current.graph.search(queryVector, 128) } finally { queryVector.fill(0f) }
                ensureActive(expected)
                storage.access {
                    val dense = catalog.resolve(matches.filter { it.similarity >= 0.35 }, current.stamp).map { (match, item) ->
                        check(match.start >= 0 && match.end <= item.content.length)
                        AgentKnowledgeHit(item, match.similarity, item.content.substring(match.start, match.end).take(1000), emptyList())
                    }
                    val fused = KnowledgeHybridRanking.fuse(lexical(), dense, limit)
                    ensureActive(expected)
                    status = "ready:${current.graph.size()}"
                    fused
                }
            } catch (error: Exception) {
                dispose()
                status = "unavailable:${error.javaClass.simpleName}"
                lexical().take(limit)
            }
        }
    }

    private fun build(expected: Long): Snapshot {
        ensureActive(expected)
        val stamp = catalog.stamp()
        val count = catalog.count()
        check(count > 0) { "No completed semantic vectors" }
        val graph = KnowledgeHnswIndex(spec.dimensions, count, budgetBytes)
        try {
            var after = ""
            while (true) {
                ensureActive(expected)
                val keys = catalog.keys(after)
                if (keys.isEmpty()) break
                for (key in keys) {
                    var ordinal = 0
                    do {
                        ensureActive(expected)
                        val next = requireNotNull(ledger.pageByKey(key, ordinal)) { "Knowledge changed during ANN build" }.use { page ->
                            page.rows.forEach { graph.add(key, page.revision, it) }
                            ordinal += page.rows.size
                            ordinal < page.total
                        }
                    } while (next)
                }
                after = keys.last()
            }
            check(graph.size() == count && catalog.stamp() == stamp) { "Knowledge changed during ANN build" }
            ensureActive(expected)
            cleanup.schedule({ expire(expected) }, ttlMillis, TimeUnit.MILLISECONDS)
            return Snapshot(stamp, graph, expected, System.nanoTime() + TimeUnit.MILLISECONDS.toNanos(ttlMillis))
        } catch (error: Throwable) { graph.close(); throw error }
    }

    private fun ensureActive(expected: Long) {
        check(!closed.get() && !suspended.get() && epoch.get() == expected && !Thread.currentThread().isInterrupted) {
            "Semantic retrieval cancelled by lifecycle change"
        }
    }
    fun invalidate(expected: Long = epoch.get()) {
        if (!epoch.compareAndSet(expected, expected + 1)) return
        status = "invalidated"
        // Never wait for inference or graph construction on the UI/lifecycle thread.
        cleanup.execute { synchronized(lock) {
            if (snapshot?.epoch == expected || snapshot == null) dispose()
        } }
    }
    private fun expire(expected: Long) = synchronized(lock) {
        // TTL retires an idle cache; unlike a privacy boundary it must not cancel a legitimate in-flight query.
        if (snapshot?.epoch == expected && epoch.compareAndSet(expected, expected + 1)) {
            dispose()
            status = "invalidated"
        }
    }
    override fun close() {
        if (!closed.compareAndSet(false, true)) return
        sessions.remove(this)
        invalidate()
        cleanup.execute { synchronized(lock) { dispose() } }
    }
    private fun dispose() {
        snapshot?.graph?.close(); snapshot = null
        val previous = encoder; encoder = null
        previous?.close()
    }
    companion object {
        private val sessions = ConcurrentHashMap.newKeySet<KnowledgeSemanticSearch>()
        private val suspended = AtomicBoolean()
        private val cleanup = Executors.newSingleThreadScheduledExecutor { task ->
            Thread(task, "knowledge-semantic-cleanup").apply { isDaemon = true }
        }
        fun clearRuntime(suspend: Boolean = false) {
            if (suspend) suspended.set(true)
            sessions.forEach { it.invalidate() }
        }
        fun resumeRuntime() { suspended.set(false) }
    }
}

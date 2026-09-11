package com.galaxyssi.chat

import android.os.Looper
import java.io.Closeable
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong
import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock

/** Owns the native index and optional encoder; the source database remains authoritative. */
internal class KnowledgeSemanticSearch(
    private val storage: AgentKnowledgeDatabase, private val spec: KnowledgeVectorSpec,
    private val encoderFactory: () -> KnowledgeVectorEncoder,
    private val budgetBytes: Long = minOf(64L * 1024 * 1024, Runtime.getRuntime().maxMemory() / 8),
    private val ttlMillis: Long = 30_000
) : Closeable {
    private data class Snapshot(val index: KnowledgeNativeIndex, val epoch: Long)
    private val lock = ReentrantLock(true)
    private val epoch = AtomicLong()
    private val closed = AtomicBoolean()
    private val indexScheduled = AtomicBoolean()
    private val catalog = KnowledgeVectorCatalog(storage, storage.vectors(spec))
    @Volatile private var snapshot: Snapshot? = null
    private var encoder: KnowledgeVectorEncoder? = null
    @Volatile var status: String = "not_built"
        private set
    init { require(ttlMillis > 0 && budgetBytes > 0); sessions.add(this) }

    fun search(query: String, limit: Int, lexical: () -> List<AgentKnowledgeHit>): List<AgentKnowledgeHit> {
        require(limit in 1..24)
        if (Looper.myLooper() == Looper.getMainLooper()) { status = "requires_worker_thread"; return lexical().take(limit) }
        if (closed.get() || suspended.get()) { status = "suspended"; return lexical().take(limit) }
        // Allow a short cleanup/checkpoint handoff, never an unbounded replay/inference wait.
        val admitted = try { lock.tryLock(25, TimeUnit.MILLISECONDS) }
            catch (_: InterruptedException) { Thread.currentThread().interrupt(); false }
        if (!admitted) { status = "busy"; return lexical().take(limit) }
        val result = try {
            var expected = epoch.get()
            try {
                ensureActive(expected)
                val current = openSnapshot(expected)
                expected = current.epoch
                if (!current.index.tryReady { ensureActive(expected) }) {
                    status = "indexing"
                    scheduleIndex(current)
                    null
                } else if (requireNotNull(current.index.readyStamp).completedChunks == 0L) {
                    status = "ready:0"
                    null
                } else {
                    val stamp = requireNotNull(current.index.readyStamp)
                    val active = encoder ?: encoderFactory().also { opened ->
                        if (opened.spec != spec) { opened.close(); error("Embedding model specification changed") }
                        encoder = opened
                    }
                    ensureActive(expected)
                    val queryVector = active.embed(query)
                    val matches = try { current.index.search(queryVector) } finally { queryVector.fill(0f) }
                    ensureActive(expected)
                    storage.access {
                        val dense = catalog.resolve(matches.filter { it.similarity >= 0.35 }, stamp).map { (match, item) ->
                            check(match.start >= 0 && match.end <= item.content.length)
                            AgentKnowledgeHit(item, match.similarity, item.content.substring(match.start, match.end).take(1000), emptyList())
                        }
                        val fused = KnowledgeHybridRanking.fuse(lexical(), dense, limit)
                        ensureActive(expected)
                        status = "ready:${stamp.completedChunks}"
                        fused
                    }
                }
            } catch (error: Exception) {
                dispose()
                status = "unavailable:${error.javaClass.simpleName}"
                null
            }
        } finally { lock.unlock() }
        // Release the index owner before reading the authoritative lexical fallback.
        return result ?: lexical().take(limit)
    }

    /** Called by the existing durable vector worker; never loads an inference model. */
    fun advanceIndex(cancelled: () -> Boolean = { false }): Boolean = lock.withLock {
        if (closed.get() || suspended.get() || cancelled()) return@withLock true
        val current = openSnapshot(epoch.get())
        try {
            val active = {
                ensureActive(current.epoch)
                check(!cancelled()) { "Native memory indexing worker stopped" }
            }
            val complete = current.index.tryReady(active) || current.index.synchronize(active = active)
            status = if (complete) "ready:${current.index.readyStamp?.completedChunks ?: 0}" else "indexing"
            if (!complete) scheduleIndex(current)
            complete
        } catch (error: Exception) {
            dispose(); status = "unavailable:${error.javaClass.simpleName}"
            throw error
        }
    }
    private fun openSnapshot(expected: Long): Snapshot {
        ensureActive(expected)
        return snapshot?.takeIf { it.epoch == expected } ?: run {
            check(epoch.compareAndSet(expected, expected + 1)) { "Semantic retrieval invalidated" }
            dispose()
            Snapshot(KnowledgeNativeIndex(storage, spec, budgetBytes), expected + 1).also {
                snapshot = it
                cleanup.schedule({ expire(it.epoch) }, ttlMillis, TimeUnit.MILLISECONDS)
            }
        }
    }
    private fun scheduleIndex(current: Snapshot) {
        if (!indexScheduled.compareAndSet(false, true)) return
        indexing.execute {
            var again = false
            try { lock.withLock {
                ensureActive(current.epoch)
                check(snapshot === current)
                val active = { ensureActive(current.epoch) }
                again = !(current.index.tryReady(active) || current.index.synchronize(active = active))
                status = if (again) "indexing" else "ready:${current.index.readyStamp?.completedChunks ?: 0}"
            } } catch (error: Exception) {
                lock.withLock {
                    if (snapshot === current) { dispose(); status = "unavailable:${error.javaClass.simpleName}" }
                }
            } finally {
                indexScheduled.set(false)
                if (again && !closed.get() && !suspended.get() && epoch.get() == current.epoch) scheduleIndex(current)
            }
        }
    }
    private fun ensureActive(expected: Long) {
        check(!closed.get() && !suspended.get() && epoch.get() == expected && !Thread.currentThread().isInterrupted) {
            "Semantic retrieval cancelled by lifecycle change"
        }
    }
    fun invalidate(expected: Long = epoch.get()) {
        if (!epoch.compareAndSet(expected, expected + 1)) return
        status = "invalidated"
        snapshot?.index?.cancel()
        // Never wait for inference or native disk work on a UI/lifecycle thread.
        cleanup.execute { lock.withLock {
            if (snapshot?.epoch == expected || snapshot == null) dispose()
        } }
    }
    private fun expire(expected: Long): Unit = lock.withLock {
        if (snapshot?.epoch != expected) return@withLock
        // Active replay is work, not an idle cache. Its bounded slices still observe privacy cancellation.
        if (indexScheduled.get()) {
            cleanup.schedule({ expire(expected) }, ttlMillis, TimeUnit.MILLISECONDS)
        } else if (epoch.compareAndSet(expected, expected + 1)) {
            dispose()
            status = "invalidated"
        }
    }
    override fun close() {
        if (!closed.compareAndSet(false, true)) return
        sessions.remove(this)
        invalidate()
        cleanup.execute { lock.withLock { dispose() } }
    }
    private fun dispose() {
        val previousIndex = snapshot; snapshot = null
        previousIndex?.index?.close()
        val previous = encoder; encoder = null
        previous?.close()
    }
    companion object {
        private val sessions = ConcurrentHashMap.newKeySet<KnowledgeSemanticSearch>()
        private val suspended = AtomicBoolean()
        private val cleanup = Executors.newSingleThreadScheduledExecutor { task ->
            Thread(task, "knowledge-semantic-cleanup").apply { isDaemon = true }
        }
        private val indexing = Executors.newSingleThreadExecutor { task ->
            Thread(task, "knowledge-native-index").apply { isDaemon = true }
        }
        fun clearRuntime(suspend: Boolean = false) {
            if (suspend) suspended.set(true)
            sessions.forEach { it.invalidate() }
        }
        fun resumeRuntime() {
            if (suspended.getAndSet(false)) sessions.forEach { session ->
                val expected = session.epoch.get()
                indexing.execute { runCatching { session.lock.withLock {
                    // A foreground/worker reopen already owns recovery for a newer generation.
                    if (session.epoch.get() == expected) session.advanceIndex()
                } } }
            }
        }
    }
}

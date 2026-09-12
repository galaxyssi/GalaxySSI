package com.galaxyssi.chat

import java.io.Closeable
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock

/** Bounded active-plus-idle resources. No factory, validation or close runs under the pool lock. */
internal class KnowledgeReadConnectionPool<K : Any, V : Closeable>(private val capacity: Int) : Closeable {
    private class Entry<K, V>(var key: K, var resource: V? = null, var busy: Boolean = true, var discard: Boolean = false)
    private val lock = ReentrantLock(true)
    private val available = lock.newCondition()
    private val entries = linkedSetOf<Entry<K, V>>()
    private var closed = false
    private var opened = 0L
    private var reused = 0L
    private var evicted = 0L
    private var peak = 0

    data class Stats(val opened: Long, val reused: Long, val evicted: Long, val active: Int, val idle: Int, val peak: Int)
    init { require(capacity in 1..64) }

    fun stats() = lock.withLock { Stats(opened, reused, evicted, entries.count { it.busy }, entries.count { !it.busy }, peak) }

    class Lease<V> internal constructor(private val resource: V, private val release: (Boolean) -> Unit) : Closeable {
        private val returned = AtomicBoolean()
        @Volatile private var failed = false
        val value: V get() { check(!returned.get()) { "Read connection lease is closed" }; return resource }
        fun invalidate() { failed = true }
        override fun close() { if (returned.compareAndSet(false, true)) release(failed) }
    }

    fun borrow(key: K, valid: (V) -> Boolean = { true }, create: () -> V): Lease<V> {
        val entry: Entry<K, V>
        val previous: V?
        val sameKey: Boolean
        lock.lockInterruptibly()
        try {
            var selected: Entry<K, V>?
            while (true) {
                check(!closed) { "Read connection pool is closed" }
                selected = entries.firstOrNull { !it.busy && it.key == key }
                if (selected != null) break
                if (entries.size < capacity) {
                    selected = Entry(key)
                    entries.add(selected)
                    peak = maxOf(peak, entries.size)
                    break
                }
                selected = entries.firstOrNull { !it.busy }
                if (selected != null) break
                available.await()
            }
            entry = requireNotNull(selected)
            sameKey = entry.key == key
            previous = entry.resource
            entry.key = key; entry.resource = null; entry.busy = true; entry.discard = false
        } finally { lock.unlock() }
        var resource = previous
        try {
            if (resource != null && sameKey && valid(resource)) {
                lock.withLock { reused++ }
            } else {
                if (resource != null) {
                    val stale = resource; resource = null
                    stale.close()
                    lock.withLock { evicted++ }
                }
                resource = create()
                lock.withLock { opened++ }
            }
            val ready = requireNotNull(resource)
            lock.withLock {
                check(!closed) { "Read connection pool closed during open" }
                entry.resource = ready
            }
            return Lease(ready) { failed -> release(entry, failed) }
        } catch (failure: Throwable) {
            try { resource?.close() } catch (cleanup: Throwable) { failure.addSuppressed(cleanup) }
            finally { remove(entry) }
            throw failure
        }
    }

    fun <R> read(key: K, valid: (V) -> Boolean = { true }, create: () -> V, action: (V) -> R): R =
        borrow(key, valid, create).use { lease ->
            try { action(lease.value) } catch (failure: Throwable) { lease.invalidate(); throw failure }
        }

    private fun release(entry: Entry<K, V>, failed: Boolean) {
        val resource = lock.withLock {
            check(entry in entries && entry.busy)
            if (!failed && !closed && !entry.discard) {
                entry.busy = false
                entries.remove(entry); entries.add(entry)
                available.signalAll()
                return
            }
            val result = entry.resource
            entry.resource = null
            result
        }
        try { resource?.close() } finally { remove(entry) }
    }

    /** Physical retirement must refuse a live lease; owner shutdown may defer disposal until release. */
    fun invalidate(matches: (K) -> Boolean, requireIdle: Boolean = false) {
        val disposing = lock.withLock {
            val selected = entries.filter { matches(it.key) }
            check(!requireIdle || selected.none { it.busy }) { "Cannot retire a leased read connection" }
            selected.mapNotNull { entry ->
                entry.discard = true
                if (entry.busy) null else {
                    entry.busy = true
                    (entry to entry.resource).also { entry.resource = null }
                }
            }
        }
        var failure: Throwable? = null
        for ((entry, resource) in disposing) {
            try { resource?.close() }
            catch (error: Throwable) { if (failure == null) failure = error else failure.addSuppressed(error) }
            finally { remove(entry) }
        }
        failure?.let { throw it }
    }

    private fun remove(entry: Entry<K, V>) = lock.withLock { entries.remove(entry); available.signalAll() }

    override fun close() {
        lock.withLock { closed = true; available.signalAll() }
        invalidate({ true })
    }
}

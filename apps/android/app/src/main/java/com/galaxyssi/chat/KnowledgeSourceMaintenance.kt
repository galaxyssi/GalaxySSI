package com.galaxyssi.chat

import java.io.Closeable
import java.util.concurrent.CopyOnWriteArraySet
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/** Checkpoints live in SQLite. Reopening resumes work without enabling or loading any model. */
internal class KnowledgeSourceMaintenance(private val owner: AgentKnowledgeDatabase) {
    private val scheduled = AtomicBoolean()
    private val listeners = CopyOnWriteArraySet<() -> Unit>()
    @Volatile var failure: String? = null
        private set
    @Volatile private var closed = false
    fun request(db: KnowledgeSqlite) {
        if (closed || failure != null || scheduled.get() || KnowledgeSourceDirectory.state(db).complete) return
        if (!scheduled.compareAndSet(false, true)) return
        executor.schedule({
            var complete = false
            try {
                if (!closed) complete = owner.transaction { KnowledgeSourceDirectory.advance(it) }
            } catch (error: Exception) {
                if (!closed) failure = error.message ?: error.javaClass.simpleName
            } finally {
                scheduled.set(false)
                if (!closed) {
                    if (complete || failure != null) listeners.forEach { runCatching(it) }
                    else runCatching { owner.access { request(it) } }
                }
            }
        }, 10, TimeUnit.MILLISECONDS)
    }
    fun observe(listener: () -> Unit): Closeable {
        check(!closed)
        listeners.add(listener)
        // Covers completion between the page's not-ready result and observer registration.
        executor.execute {
            if (!closed && listener in listeners) runCatching {
                if (failure != null || owner.access { KnowledgeSourceDirectory.state(it).complete }) listener()
            }
        }
        return Closeable { listeners.remove(listener) }
    }
    fun retry() { failure = null; owner.access { request(it) } }
    fun close() { closed = true; listeners.clear() }
    companion object {
        private val executor = Executors.newSingleThreadScheduledExecutor { task ->
            Thread(task, "knowledge-source-directory").apply { isDaemon = true; priority = Thread.MIN_PRIORITY }
        }
    }
}

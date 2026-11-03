package com.galaxyssi.chat

import java.util.concurrent.Executor

/** One active load and at most one replacement; lifecycle changes invalidate delivery. */
internal class AgentForegroundReload<T>(private val worker: Executor, private val ui: Executor) {
    private data class Request<T>(val generation: Long, val load: (() -> Boolean) -> T,
        val deliver: (Result<T>) -> Unit)
    private var generation = 0L
    private var running = false
    private var pending: Request<T>? = null

    @Synchronized fun invalidate() {
        generation++
        pending = null
    }

    fun request(load: (() -> Boolean) -> T, deliver: (Result<T>) -> Unit) {
        val start = synchronized(this) {
            pending = Request(++generation, load, deliver)
            if (running) false else { running = true; true }
        }
        if (start) worker.execute(::drain)
    }

    private fun current(request: Request<T>) = synchronized(this) { generation == request.generation }

    private fun drain() {
        while (true) {
            val request = synchronized(this) {
                val next = pending
                pending = null
                if (next == null) running = false
                next
            } ?: return
            val result = runCatching { request.load { current(request) } }
            if (current(request)) ui.execute {
                if (current(request)) request.deliver(result)
            }
        }
    }
}

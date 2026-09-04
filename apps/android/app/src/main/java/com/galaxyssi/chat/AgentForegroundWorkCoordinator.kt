package com.galaxyssi.chat

import java.io.Closeable
import java.util.concurrent.ConcurrentHashMap

/**
 * Process-wide foreground activity signal shared by chat and proactive runtimes.
 *
 * A foreground lease is created before a user turn enters an execution lane, so
 * background schedulers stop admitting new work while the turn is still queued.
 */
object AgentForegroundWorkCoordinator {
    private val activeTaskIds = ConcurrentHashMap.newKeySet<String>()

    val hasForegroundWork: Boolean
        get() = activeTaskIds.isNotEmpty()

    val activeCount: Int
        get() = activeTaskIds.size

    fun begin(taskId: String): Lease {
        val normalizedTaskId = taskId.trim()
        require(normalizedTaskId.isNotBlank()) { "Foreground task ID must not be blank" }
        check(activeTaskIds.add(normalizedTaskId)) {
            "Foreground task $normalizedTaskId is already active"
        }
        return Lease(normalizedTaskId)
    }

    class Lease internal constructor(
        private val taskId: String
    ) : Closeable {
        @Volatile
        private var closed = false

        override fun close() {
            if (closed) return
            synchronized(this) {
                if (closed) return
                closed = true
                activeTaskIds.remove(taskId)
            }
        }
    }
}

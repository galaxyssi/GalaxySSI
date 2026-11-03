package com.galaxyssi.chat

/** Concurrent wakes share a pass; wakes arriving during that pass request another observation. */
internal class AgentRecoveryCoalescer {
    private val lock = Any()
    private var running = false
    private var requested = false

    fun run(observe: () -> Int): Int {
        synchronized(lock) {
            requested = true
            if (running) return 0
            running = true
        }
        var total = 0
        try {
            while (true) {
                synchronized(lock) { requested = false }
                total += observe()
                synchronized(lock) {
                    if (!requested) {
                        running = false
                        return total
                    }
                }
            }
        } catch (error: Throwable) {
            synchronized(lock) { running = false }
            throw error
        }
    }
}

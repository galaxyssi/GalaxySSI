package com.galaxyssi.chat

import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/** Serializes the same durable cursor without making an offline task block unrelated live evidence. */
internal class CollaborationEvidenceImportGate {
    private class Entry(val mutex: Mutex = Mutex(), var users: Int = 0)
    private val entries = mutableMapOf<String, Entry>()

    suspend fun <T> withJob(key: String, action: suspend () -> T): T {
        val entry = synchronized(entries) { entries.getOrPut(key, ::Entry).also { it.users++ } }
        try {
            return entry.mutex.withLock { action() }
        } finally {
            synchronized(entries) {
                entry.users--
                if (entry.users == 0) entries.remove(key)
            }
        }
    }

    internal val size: Int get() = synchronized(entries) { entries.size }
}

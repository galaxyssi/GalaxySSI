package com.galaxyssi.chat

import java.io.File
import java.io.RandomAccessFile
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock

/** Acquire before SQLite transactions. Maintenance excludes unpublished appends and live readers. */
internal class MemorySegmentAccess(private val path: File) {
    private class State {
        val mutex = ReentrantLock()
        var depth = 0
        var exclusive = false
    }
    private val state = states.computeIfAbsent(path.canonicalPath) { State() }

    fun <T> readWrite(block: () -> T): T = access(false, block)
    fun <T> maintenance(block: () -> T): T = access(true, block)

    /** Background work yields instead of joining the queue ahead of interactive reads. */
    fun <T : Any> tryMaintenance(block: () -> T): T? {
        if (!state.mutex.tryLock()) return null
        try {
            check(state.depth == 0) { "Cannot start background maintenance inside a storage operation" }
            val parent = requireNotNull(path.parentFile)
            check(parent.isDirectory || parent.mkdirs() || parent.isDirectory)
            RandomAccessFile(path, "rw").use { file ->
                val lock = file.channel.tryLock() ?: return null
                lock.use {
                    state.exclusive = true
                    state.depth = 1
                    try { return block() } finally { state.depth = 0; state.exclusive = false }
                }
            }
        } finally { state.mutex.unlock() }
    }

    private fun <T> access(exclusive: Boolean, block: () -> T): T = state.mutex.withLock {
        if (state.depth > 0) {
            check(!exclusive || state.exclusive) { "Cannot upgrade memory segment access inside a transaction" }
            state.depth++
            try { return block() } finally { state.depth-- }
        }
        val parent = requireNotNull(path.parentFile)
        check(parent.isDirectory || parent.mkdirs() || parent.isDirectory)
        RandomAccessFile(path, "rw").use { file ->
            file.channel.lock(0, Long.MAX_VALUE, !exclusive).use {
                state.exclusive = exclusive
                state.depth = 1
                try { block() } finally { state.depth = 0; state.exclusive = false }
            }
        }
    }

    private companion object {
        val states = ConcurrentHashMap<String, State>()
    }
}

package com.galaxyssi.chat

import java.io.Closeable
import java.io.File
import java.io.RandomAccessFile
import java.nio.channels.FileLock
import java.util.concurrent.ConcurrentHashMap

/** A WAL snapshot may outlive its creating thread; shared leases must not serialize writers. */
internal class KnowledgeSegmentLeases(private val path: File) {
    private class State {
        var readers = 0
        var exclusive = false
        var file: RandomAccessFile? = null
        var lock: FileLock? = null
    }
    private val state = states.computeIfAbsent(path.canonicalPath) { State() }

    fun acquire(): Closeable = synchronized(state) {
        check(!state.exclusive) { "Cannot acquire a snapshot inside segment reclamation" }
        if (state.readers == 0) {
            val file = open()
            try {
                state.lock = file.channel.lock(0, Long.MAX_VALUE, true)
                state.file = file
            } catch (failure: Throwable) { file.close(); throw failure }
        }
        state.readers = Math.addExact(state.readers, 1)
        var closed = false
        Closeable {
            synchronized(state) {
                if (!closed) {
                    closed = true
                    check(state.readers > 0)
                    if (--state.readers == 0) {
                        try { state.lock!!.release() } finally {
                            state.lock = null
                            try { state.file!!.close() } finally { state.file = null }
                        }
                    }
                }
            }
        }
    }

    fun <T> access(block: () -> T): T = acquire().use { block() }

    fun <T : Any> tryReclaim(block: () -> T): T? = synchronized(state) {
        if (state.readers > 0 || state.exclusive) return null
        open().use { file ->
            val lock = file.channel.tryLock() ?: return null
            lock.use {
                state.exclusive = true
                try { block() } finally { state.exclusive = false }
            }
        }
    }

    private fun open(): RandomAccessFile {
        val parent = requireNotNull(path.parentFile)
        check(parent.isDirectory || parent.mkdirs() || parent.isDirectory)
        return RandomAccessFile(path, "rw")
    }

    private companion object { val states = ConcurrentHashMap<String, State>() }
}

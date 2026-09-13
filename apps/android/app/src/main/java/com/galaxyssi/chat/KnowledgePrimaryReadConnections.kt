package com.galaxyssi.chat

import android.system.Os
import android.system.OsConstants
import java.io.Closeable
import java.io.File

/** Only SQLite connections, prepared statements and ciphertext pages are reused; no decoded records. */
internal object KnowledgePrimaryReadConnections {
    private data class Stamp(val device: Long, val inode: Long)
    private data class Key(val root: String, val file: String)
    private class Reader(val sql: KnowledgeSqlite, val stamp: Stamp) : Closeable {
        override fun close() = sql.close()
    }
    private val pool = KnowledgeReadConnectionPool<Key, Reader>(8)
    private val trimming = java.util.concurrent.atomic.AtomicBoolean()
    private val cleanup = java.util.concurrent.Executors.newSingleThreadExecutor { task ->
        Thread(task, "knowledge-read-cache-trim").apply { isDaemon = true }
    }

    internal fun stats() = pool.stats()
    private fun stamp(file: File) = Os.lstat(file.absolutePath).let {
        check(OsConstants.S_ISREG(it.st_mode)) { "Primary partition must be a regular file" }
        Stamp(it.st_dev, it.st_ino)
    }

    fun <T> read(root: File, file: File, open: () -> KnowledgeSqlite, action: (KnowledgeSqlite) -> T): T {
        val key = Key(root.absolutePath, file.absolutePath)
        return pool.read(key, valid = { it.stamp == stamp(file) }, create = {
            val before = stamp(file)
            val db = open()
            try {
                check(before == stamp(file)) { "Primary partition changed while opening" }
                Reader(db, before)
            } catch (error: Throwable) { db.close(); throw error }
        }) { action(it.sql) }
    }

    fun retire(file: File) = pool.invalidate({ it.file == file.absolutePath }, requireIdle = true)
    fun clear(root: File) = pool.invalidate({ it.root == root.absolutePath })

    fun requestTrim() {
        if (pool.stats().let { it.active == 0 && it.idle == 0 }) return
        if (!trimming.compareAndSet(false, true)) return
        cleanup.execute {
            try { pool.invalidate({ true }) }
            catch (error: Exception) { android.util.Log.w("KnowledgeReadCache", "Trim failed: ${error.javaClass.simpleName}") }
            finally { trimming.set(false) }
        }
    }
}

package com.galaxyssi.chat

import android.content.ContentValues
import android.system.ErrnoException
import android.system.Os
import android.system.OsConstants
import java.io.File

/** A separate durable intent survives rollback of the catalog that will publish a new file. */
internal class KnowledgePrimaryAllocations(private val file: File) {
    data class Page(val visited: Int, val orphaned: Int, val bytes: Long, val complete: Boolean)

    fun remember(id: String) {
        require(valid(id))
        open().use { db ->
            db.insertOrThrow("pending", null, ContentValues().apply { put("partition_key", id) })
        }
        // Also covers a prior process dying after creating this file but before syncing its name.
        syncParent()
    }

    /** Caller holds the exclusive cross-process payload lease and no catalog writer transaction. */
    fun replay(isReferenced: (String) -> Boolean, verifyReferenced: (String) -> Unit,
        remove: (String) -> Long, checkActive: () -> Unit, limit: Int = 8): Page {
        require(limit in 1..64)
        checkActive()
        if (!regularOrMissing(file)) return Page(0, 0, 0, true)
        open().use { db ->
            db.beginTransaction()
            try {
                val ids = db.rawQuery("SELECT partition_key FROM pending ORDER BY partition_key LIMIT ?",
                    arrayOf(limit.toString())).use { cursor -> buildList {
                    while (cursor.moveToNext()) add(cursor.getString(0).also { require(valid(it)) })
                } }
                var bytes = 0L
                var orphaned = 0
                for (id in ids) {
                    checkActive()
                    if (isReferenced(id)) verifyReferenced(id) else {
                        bytes = Math.addExact(bytes, remove(id))
                        orphaned++
                    }
                    // If termination follows unlink, replay simply observes an already absent file.
                    db.delete("pending", "partition_key=?", arrayOf(id))
                }
                val complete = db.rawQuery("SELECT 1 FROM pending LIMIT 1", null).use { !it.moveToFirst() }
                db.setTransactionSuccessful()
                return Page(ids.size, orphaned, bytes, complete)
            } finally { db.endTransaction() }
        }
    }

    private fun open(): KnowledgeSqlite {
        regularOrMissing(file)
        val db = KnowledgeSqlite(file.absolutePath)
        try {
            db.execSQL("PRAGMA journal_mode=DELETE")
            db.execSQL("PRAGMA synchronous=FULL")
            db.execSQL("PRAGMA busy_timeout=5000")
            db.execSQL("PRAGMA cache_size=-256")
            db.execSQL("PRAGMA mmap_size=0")
            db.beginTransaction()
            try {
                val version = db.rawQuery("PRAGMA user_version", null).use { check(it.moveToFirst()); it.getInt(0) }
                check(version in 0..1) { "Unsupported primary allocation journal" }
                if (version == 0) {
                    db.execSQL("CREATE TABLE pending(partition_key TEXT PRIMARY KEY) WITHOUT ROWID")
                    db.execSQL("PRAGMA user_version=1")
                }
                db.setTransactionSuccessful()
            } finally { db.endTransaction() }
            return db
        } catch (failure: Throwable) { db.close(); throw failure }
    }

    private fun syncParent() {
        val fd = Os.open(requireNotNull(file.parentFile).absolutePath, OsConstants.O_RDONLY, 0)
        try { Os.fsync(fd) } finally { Os.close(fd) }
    }

    companion object {
        private fun valid(id: String) = id.matches(Regex("[a-f0-9]{32}"))
        internal fun regularOrMissing(file: File): Boolean = try {
            check(OsConstants.S_ISREG(Os.lstat(file.absolutePath).st_mode)) { "Primary allocation path must be a regular file" }
            true
        } catch (failure: ErrnoException) {
            if (failure.errno == OsConstants.ENOENT) false else throw failure
        }
    }
}

package com.galaxyssi.chat

import android.database.sqlite.SQLiteDatabase
import java.io.File
import java.util.UUID

/** Separate durable registration survives a rollback of the source-reference transaction. */
internal class AgentMemorySegmentCatalog(private val path: File) {
    private fun <T> database(block: (SQLiteDatabase) -> T): T {
        val parent = requireNotNull(path.parentFile)
        check(parent.isDirectory || parent.mkdirs() || parent.isDirectory)
        return SQLiteDatabase.openOrCreateDatabase(path, null).use { db ->
            db.execSQL("PRAGMA synchronous=FULL")
            db.execSQL("CREATE TABLE IF NOT EXISTS segments (id INTEGER PRIMARY KEY AUTOINCREMENT, segment TEXT UNIQUE NOT NULL)")
            db.execSQL("CREATE TABLE IF NOT EXISTS progress (id INTEGER PRIMARY KEY CHECK(id=1), cursor INTEGER NOT NULL)")
            block(db)
        }
    }

    fun register(segment: UUID) = database { db ->
        db.execSQL("INSERT INTO segments(segment) VALUES(?)", arrayOf(segment.toString()))
    }

    data class Entry(val id: Long, val segment: UUID)

    fun next(limit: Int): List<Entry> = database { db ->
        require(limit in 1..32)
        val after = db.rawQuery("SELECT cursor FROM progress WHERE id=1", null).use { if (it.moveToFirst()) it.getLong(0) else 0L }
        fun page(cursor: Long) = db.rawQuery("SELECT id,segment FROM segments WHERE id>? ORDER BY id LIMIT ?",
            arrayOf(cursor.toString(), limit.toString())).use { c ->
            buildList { while (c.moveToNext()) add(Entry(c.getLong(0), UUID.fromString(c.getString(1)))) }
        }
        page(after).ifEmpty { page(0) }
    }

    fun advance(entry: Entry, removed: Boolean) = database { db ->
        db.beginTransaction()
        try {
            if (removed) db.execSQL("DELETE FROM segments WHERE id=? AND segment=?", arrayOf(entry.id, entry.segment.toString()))
            db.execSQL("INSERT OR REPLACE INTO progress(id,cursor) VALUES(1,?)", arrayOf(entry.id))
            db.setTransactionSuccessful()
        } finally { db.endTransaction() }
    }
}

package com.galaxyssi.chat

import android.database.sqlite.SQLiteConstraintException
import android.database.sqlite.SQLiteDatabase
import java.util.UUID

/** Disk-backed transaction bookkeeping; never retains every restored identity in a JVM set. */
internal class MemoryReplacementKeys private constructor(private val sql: SQLiteDatabase, private val table: String) {
    var size = 0L
        private set

    fun add(key: String) {
        try { sql.execSQL("INSERT INTO $table(kind,k) VALUES(0,?)", arrayOf(key)) }
        catch (error: SQLiteConstraintException) { throw IllegalArgumentException("Duplicate personal memory identity", error) }
        size = Math.addExact(size, 1)
    }

    fun contains(key: String): Boolean = sql.rawQuery("SELECT 1 FROM $table WHERE kind=0 AND k=?", arrayOf(key))
        .use { it.moveToFirst() }

    fun removeLookup(key: String) { sql.execSQL("INSERT OR IGNORE INTO $table(kind,k) VALUES(1,?)", arrayOf(key)) }

    fun removedLookups(): Sequence<String> = sequence {
        var cursor = ""
        while (true) {
            val page = sql.rawQuery("SELECT k FROM $table WHERE kind=1 AND k>? ORDER BY k LIMIT 128", arrayOf(cursor)).use { c ->
                buildList { while (c.moveToNext()) add(c.getString(0)) }
            }
            if (page.isEmpty()) break
            yieldAll(page)
            cursor = page.last()
        }
    }

    companion object {
        fun <T> transaction(database: AgentEncryptedDatabase, block: (MemoryReplacementKeys) -> T): T = database.indexedTransaction { sql ->
            val table = "memory_replacement_" + UUID.randomUUID().toString().replace("-", "")
            // A normal database table, not TEMP storage whose policy may retain the whole set in RAM.
            sql.execSQL("CREATE TABLE $table(kind INTEGER NOT NULL,k TEXT NOT NULL,PRIMARY KEY(kind,k)) WITHOUT ROWID")
            try { block(MemoryReplacementKeys(sql, table)) }
            finally { sql.execSQL("DROP TABLE $table") }
        }
    }
}

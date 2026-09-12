package com.galaxyssi.chat

import java.io.Closeable

/** A pinned WAL read snapshot: bounded heap without holding the live store's writer monitor. */
internal class KnowledgeBackupSnapshot(private val owner: AgentKnowledgeDatabase, path: String) : Closeable {
    private val lease = owner.payloadLease()
    private val sql = try { KnowledgeSqlite(path) } catch (failure: Throwable) { lease.close(); throw failure }
    private var closed = false
    init {
        try {
            sql.execSQL("PRAGMA query_only=ON")
            sql.execSQL("PRAGMA cache_size=-2048")
            sql.execSQL("PRAGMA mmap_size=0")
            sql.execSQL("BEGIN")
            // Establish the snapshot while the caller still holds the short initialization lock.
            sql.rawQuery("SELECT revision FROM knowledge_browse_revision WHERE id=1", null).use { check(it.moveToFirst()) }
        } catch (failure: Throwable) { try { sql.close() } finally { lease.close() }; throw failure }
    }
    fun items(): Sequence<AgentKnowledgeItem> = sequence {
        checkActive()
        for (item in owner.scan(sql)) { checkActive(); yield(item) }
        checkActive()
    }
    fun checkActive() { check(!closed); owner.checkActive() }
    override fun close() {
        if (closed) return
        closed = true
        try { sql.execSQL("ROLLBACK") } finally { try { sql.close() } finally { lease.close() } }
    }
}

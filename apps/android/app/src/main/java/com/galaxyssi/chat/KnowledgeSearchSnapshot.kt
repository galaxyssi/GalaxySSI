package com.galaxyssi.chat

import java.io.Closeable

/** Thread-confined read view. Ranking never reserves the live writer or its monitor. */
internal class KnowledgeSearchSnapshot(private val owner: AgentKnowledgeDatabase, path: String) : Closeable {
    private val lease = owner.payloadLease()
    private val sql = try { KnowledgeSqlite(path) } catch (failure: Throwable) { lease.close(); throw failure }
    private var closed = false
    init {
        try {
            checkActive()
            sql.execSQL("PRAGMA query_only=ON")
            sql.execSQL("PRAGMA cache_size=-2048")
            sql.execSQL("PRAGMA mmap_size=0")
            sql.execSQL("BEGIN")
            sql.rawQuery("SELECT revision FROM knowledge_browse_revision WHERE id=1", null).use { check(it.moveToFirst()) }
        } catch (failure: Throwable) { try { sql.close() } finally { lease.close() }; throw failure }
    }

    fun candidates(query: String, limit: Int): Sequence<AgentKnowledgeItem> = sequence {
        checkActive()
        for (item in owner.candidates(sql, query, limit, ::checkActive)) {
            checkActive()
            yield(item)
        }
    }

    fun recent(limit: Int): Sequence<AgentKnowledgeItem> = sequence {
        checkActive()
        for (key in owner.keys(sql, limit = limit)) {
            checkActive()
            yield(requireNotNull(owner.read(sql, key)))
        }
    }

    fun <T> access(block: (KnowledgeSqlite) -> T): T {
        checkActive()
        return block(sql).also { checkActive() }
    }

    /** A concurrent replacement or access-policy change must not publish stale evidence. */
    fun validate(hits: List<AgentKnowledgeHit>): List<AgentKnowledgeHit> {
        checkActive()
        return hits.chunked(32).flatMap { page ->
            val expected = page.associate { hit ->
                val key = owner.key("id", hit.item.id)
                key to header(sql, key)
            }
            owner.access { live -> page.filter { hit ->
                checkActive()
                val key = owner.key("id", hit.item.id)
                expected[key]?.let { it == header(live, key) } == true
            } }
        }.also { checkActive() }
    }

    private fun header(db: KnowledgeSqlite, key: String): String? =
        db.rawQuery("SELECT header FROM knowledge_items WHERE item_key=?", arrayOf(key)).use {
            if (it.moveToFirst()) it.getString(0) else null
        }

    fun checkActive() {
        check(!closed) { "Knowledge search snapshot was closed" }
        check(!Thread.currentThread().isInterrupted) { "Knowledge search was interrupted" }
        owner.checkActive()
    }

    override fun close() {
        if (closed) return
        closed = true
        try { sql.execSQL("ROLLBACK") } finally { try { sql.close() } finally { lease.close() } }
    }
}

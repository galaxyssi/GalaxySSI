package com.galaxyssi.chat

import java.io.Closeable

/** Closeable WAL snapshot; keyset reads do not hold the live writer's monitor. */
internal class KnowledgeSourceSnapshot(private val owner: AgentKnowledgeDatabase, path: String,
    private val selection: KnowledgeSourceSelection, expectedRevision: String) : Closeable {
    private val lease = owner.payloadLease()
    private val sql = try { KnowledgeSqlite(path) } catch (failure: Throwable) { lease.close(); throw failure }
    private var closed = false
    internal var loadedKeys = 0L
        private set
    internal var largestKeyPage = 0
        private set
    private val expectedCount: Long
    init {
        try {
            owner.checkActive()
            sql.execSQL("PRAGMA query_only=ON")
            sql.execSQL("PRAGMA cache_size=-2048")
            sql.execSQL("PRAGMA mmap_size=0")
            sql.execSQL("BEGIN")
            check(selection.revision(sql) == expectedRevision) { "Knowledge source changed before projection; retry synchronization" }
            KnowledgeSourceDirectory.state(sql).requireReady()
            expectedCount = sql.rawQuery("SELECT members FROM knowledge_source_directory WHERE group_key=?",
                arrayOf(selection.group)).use { if (it.moveToFirst()) it.getLong(0) else 0L }
            check(expectedCount >= 0 && (expectedCount == 0L) == expectedRevision.endsWith(":absent")) {
                "Knowledge source directory does not match source presence"
            }
        } catch (failure: Throwable) { try { sql.close() } finally { lease.close() }; throw failure }
    }
    fun items(): Sequence<AgentKnowledgeItem> = sequence {
        var after = ""
        var afterUpdated = Long.MIN_VALUE
        var emitted = 0L
        while (true) {
            checkActive()
            val keys = sql.rawQuery(PAGE_SQL, arrayOf(selection.group, afterUpdated.toString(), after)).use { c ->
                buildList { while (c.moveToNext()) add(c.getString(0) to c.getLong(1)) }
            }
            loadedKeys += keys.size
            largestKeyPage = maxOf(largestKeyPage, keys.size)
            if (keys.isEmpty()) break
            for ((key, sortUpdated) in keys) {
                checkActive()
                val item = requireNotNull(owner.read(sql, key))
                selection.verify(item)
                check(item.updatedAtMillis.inv() == sortUpdated) { "Knowledge source order mismatch" }
                check(++emitted <= expectedCount) { "Knowledge source member count mismatch" }
                yield(item)
            }
            after = keys.last().first
            afterUpdated = keys.last().second
        }
        check(emitted == expectedCount) { "Knowledge source members are missing" }
    }
    fun find(id: String): AgentKnowledgeItem {
        checkActive()
        return requireNotNull(owner.read(sql, owner.key("id", id))).also {
            selection.verify(it)
            check(it.id == id) { "Source snapshot identity mismatch" }
        }
    }
    private fun checkActive() { check(!closed) { "Source snapshot was closed" }; owner.checkActive() }
    override fun close() {
        if (closed) return
        closed = true
        try { sql.execSQL("ROLLBACK") } finally { try { sql.close() } finally { lease.close() } }
    }
    companion object {
        const val PAGE_SQL = "SELECT item_key,sort_updated FROM knowledge_source_members " +
            "WHERE group_key=? AND (sort_updated,item_key)>(?,?) ORDER BY sort_updated,item_key LIMIT 64"
    }
}

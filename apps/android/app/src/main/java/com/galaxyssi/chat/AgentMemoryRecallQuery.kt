package com.galaxyssi.chat

import android.database.sqlite.SQLiteDatabase
import org.json.JSONObject
import java.util.PriorityQueue

internal class AgentMemoryRecallQuery(private val database: AgentEncryptedDatabase) {
    internal var decryptedRows = 0L
        private set
    internal var usedIndex = false
        private set
    private val index = AgentMemoryRecallIndex(database)
    private data class Term(val id: Long, val count: Long)

    fun search(query: String, now: Long, limit: Int, scheduleBackfill: Boolean = true): List<AgentMemoryItem> = synchronized(AgentMemoryStorage.lock) {
        if (query.isBlank()) return@synchronized emptyList()
        decryptedRows = 0; usedIndex = false
        var migration: String? = null
        val result = database.indexedTransaction { sql ->
            val source = JSONObject(database.readString(AgentPersonalMemoryRows.META, ""))
            var state = index.state(sql)
            if (state.json.optString("source_revision") != AgentMemoryRecallRevision.content(source)) {
                database.remove(AgentMemoryRecallIndex.MARKER)
                state = index.state(sql)
            }
            val total = source.getLong("count")
            val best = AgentMemoryRecallTopK(query, now, limit)
            if (state.ready) {
                check(index.count(sql) == total) { "Memory recall index count mismatch" }
                index.hasher(state).use { hash ->
                    usedIndex = true
                    val forward = AgentMemoryRecallTerms.forward(query)
                    val reverse = AgentMemoryRecallTerms.reverse(query)
                    val tokens = (forward.flatten() + reverse).toSet().associateWith(hash::token)
                    val terms = lookup(sql, tokens.values.toSet())
                    val ids = forward.mapNotNull { group ->
                        val matches = group.mapNotNull { terms[tokens.getValue(it)] }
                        if (matches.size == group.size) matches.minByOrNull { it.count }?.id else null
                    }.toMutableSet()
                    reverse.mapNotNullTo(ids) { terms[tokens.getValue(it)]?.id }
                    visitCandidates(sql, ids) { id ->
                        val row = sql.rawQuery("SELECT row_key,signature FROM ${AgentMemoryRecallIndex.DOCS} WHERE id=?", arrayOf(id.toString()))
                            .use { check(it.moveToFirst()) { "Memory recall posting references a missing row" }; it.getString(0) to it.getString(1) }
                        consume(row.first, best) { item -> check(index.signature(item, hash) == row.second) {
                            "Memory recall index does not match encrypted source"
                        } }
                    }
                }
            } else {
                migration = state.generation
                var cursor = ""
                while (true) {
                    val keys = database.keysAfter(AgentPersonalMemoryRows.PREFIX, cursor, 128)
                    if (keys.isEmpty()) break
                    keys.forEach { consume(it, best) {} }
                    cursor = keys.last()
                }
                check(decryptedRows == total) { "Personal memory row count mismatch" }
            }
            best.result()
        }
        if (scheduleBackfill) migration?.let { AgentMemoryRecallMigration.resume(index, it) }
        result
    }

    private fun consume(key: String, best: AgentMemoryRecallTopK, verify: (AgentMemoryItem) -> Unit) {
        val row = JSONObject(database.readString(key, ""))
        val item = AgentMemoryItemCodec.decode(row.getJSONObject("item")) ?: error("Invalid recalled memory")
        val position = row.getLong("position")
        check(position >= 0 && AgentPersonalMemoryRows.key(item.id) == key && item.value.isNotBlank())
        verify(item)
        decryptedRows = Math.addExact(decryptedRows, 1)
        best.offer(item, position)
    }

    private fun lookup(sql: SQLiteDatabase, tokens: Set<String>): Map<String, Term> = buildMap {
        tokens.chunked(200).forEach { batch ->
            sql.rawQuery("SELECT token,id,n FROM ${AgentMemoryRecallIndex.TERMS} WHERE token IN (${batch.joinToString(",") { "?" }}) AND n>0",
                batch.toTypedArray()).use { c -> while (c.moveToNext()) put(c.getString(0), Term(c.getLong(1), c.getLong(2))) }
        }
    }

    private fun visitCandidates(sql: SQLiteDatabase, terms: Set<Long>, visit: (Long) -> Unit) {
        class Stream(val term: Long) {
            var page = longArrayOf(); var offset = 0; var after = 0L
            fun head(): Long = page[offset]
            fun advance(): Boolean {
                if (offset < page.size) offset++
                if (offset < page.size) return true
                val values = sql.rawQuery("SELECT doc_id FROM ${AgentMemoryRecallIndex.POSTINGS} WHERE term_id=? AND doc_id>? ORDER BY doc_id LIMIT 16",
                    arrayOf(term.toString(), after.toString())).use { c -> buildList { while (c.moveToNext()) add(c.getLong(0)) } }
                page = values.toLongArray(); offset = 0
                if (page.isNotEmpty()) { check(page.first() > after); after = page.last() }
                return page.isNotEmpty()
            }
        }
        val streams = PriorityQueue<Stream>(compareBy { it.head() })
        terms.forEach { id -> Stream(id).takeIf { it.advance() }?.let(streams::add) }
        var previous = 0L
        while (streams.isNotEmpty()) {
            val stream = streams.remove()
            val id = stream.head()
            if (id != previous) { visit(id); previous = id }
            if (stream.advance()) streams.add(stream)
        }
    }
}

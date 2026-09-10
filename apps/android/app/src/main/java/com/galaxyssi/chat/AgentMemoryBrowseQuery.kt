package com.galaxyssi.chat

import android.database.sqlite.SQLiteDatabase
import org.json.JSONObject

internal class AgentMemoryBrowseQuery(private val database: AgentEncryptedDatabase) {
    private val index = AgentMemoryBrowseIndex(database)
    internal var decryptedRows = 0
        private set
    private data class Row(val key: String, val priority: Int, val time: Long, val position: Long,
        val state: String, val kind: String, val privateFlag: Int, val expiry: Long, val group: String, val size: Long)
    private val ordering = compareBy<Row> { it.priority }.thenBy { it.time }.thenBy { it.position }.thenBy { it.key }

    fun conflictCandidates(item: AgentMemoryItem): List<AgentMemoryItem> = index.read { sql, _, _ ->
        val group = AgentMemoryBrowseIndex.groupKey(item)
        require(group.isNotBlank())
        val result = mutableListOf<AgentMemoryItem>()
        var cursor = ""
        while (true) {
            val keys = sql.rawQuery("SELECT row_key FROM ${AgentMemoryBrowseIndex.ROWS} WHERE group_key=? AND row_key>? ORDER BY row_key LIMIT 100",
                arrayOf(group, cursor)).use { c -> buildList { while (c.moveToNext()) add(c.getString(0)) } }
            if (keys.isEmpty()) break
            keys.forEach { key ->
                val value = JSONObject(database.readString(key, "")).getJSONObject("item")
                val candidate = AgentMemoryItemCodec.decode(value) ?: error("Invalid conflict candidate")
                check(AgentPersonalMemoryRows.key(candidate.id) == key && AgentMemoryBrowseIndex.groupKey(candidate) == group &&
                    AgentMemoryIdentity.sameKey(candidate, item) && candidate.conflictGroupId == item.conflictGroupId)
                result += candidate
            }
            cursor = keys.last()
        }
        result
    }

    fun counts(kinds: Set<AgentMemoryKind>): AgentMemoryBrowseCounts = index.read { sql, _, _ -> counts(sql, kinds) }
    fun kindCounts(): Map<AgentMemoryKind, Long> = index.read { sql, _, _ ->
        sql.rawQuery("SELECT kind,n FROM ${AgentMemoryBrowseIndex.COUNTS} WHERE state='ACTIVE'", null).use { c ->
            buildMap { while (c.moveToNext()) put(AgentMemoryKind.valueOf(c.getString(0)), c.getLong(1)) }
        }
    }
    private fun counts(sql: SQLiteDatabase, kinds: Set<AgentMemoryKind>): AgentMemoryBrowseCounts {
        var active = 0L; var conflicts = 0L; var history = 0L
        sql.rawQuery("SELECT state,kind,n FROM ${AgentMemoryBrowseIndex.COUNTS}", null).use { c ->
            while (c.moveToNext()) {
                val kind = AgentMemoryKind.valueOf(c.getString(1))
                if (kinds.isNotEmpty() && kind !in kinds) continue
                val count = c.getLong(2)
                check(count >= 0)
                when (c.getString(0)) {
                    "ACTIVE" -> active = Math.addExact(active, count)
                    "SUPERSEDED" -> history = Math.addExact(history, count)
                    "GROUP" -> conflicts = Math.addExact(conflicts, count)
                }
            }
        }
        return AgentMemoryBrowseCounts(active, conflicts, history)
    }

    fun page(request: AgentMemoryBrowseRequest): AgentMemoryBrowsePage {
        AgentMemoryBrowseOrder.validate(request)
        return index.read { sql, generation, revision ->
            val scope = AgentMemoryBrowseOrder.scope(request, generation)
            request.cursor?.let { cursor ->
                require(cursor.scope == scope && cursor.priority in 0..1 && cursor.position >= 0 &&
                    cursor.key.matches(Regex("personal-memory:v3:row:[a-f0-9]{64}"))) { "Invalid memory page cursor" }
                if (cursor.revision != revision) throw AgentMemoryPageChanged()
            }
            val kinds = request.kinds.sortedBy { it.name }
            // Each selected kind gets an indexed seek; merge at most (limit+1)*kind-count metadata rows.
            val rows = (if (kinds.isEmpty()) select(sql, request, null)
                else kinds.flatMap { select(sql, request, it) }).sortedWith(if (request.backwards) ordering.reversed() else ordering).take(request.limit + 1)
            val shown = rows.take(request.limit).let { if (request.backwards) it.reversed() else it }
            val entries = shown.map { row ->
                val raw = database.readString(row.key, "")
                val record = JSONObject(raw)
                val item = AgentMemoryItemCodec.decode(record.getJSONObject("item")) ?: error("Cannot decode browsed memory")
                decryptedRows++
                check(AgentPersonalMemoryRows.key(item.id) == row.key && record.getLong("position") >= 0 &&
                    (request.section == AgentMemorySection.CONFLICTS || record.getLong("position") == row.position) &&
                    AgentMemoryBrowseOrder.priority(item) == row.priority && AgentMemoryBrowseOrder.time(item.timestampMillis) == row.time &&
                    item.status.name == row.state && item.kind.name == row.kind &&
                    (request.section == AgentMemorySection.CONFLICTS ||
                        ((if (item.privateMemory) 1 else 0) == row.privateFlag && item.expiresAtMillis == row.expiry)) &&
                    AgentMemoryBrowseIndex.groupKey(item) == row.group) { "Memory browse metadata does not match encrypted source" }
                AgentMemoryBrowseEntry(item, row.size)
            }
            fun cursor(row: Row) = AgentMemoryBrowseCursor(row.priority, row.time, row.position, row.key, revision, scope)
            val next = if (shown.isNotEmpty() && (if (request.backwards) request.cursor != null else rows.size > request.limit)) cursor(shown.last()) else null
            val previous = if (shown.isNotEmpty() && (if (request.backwards) rows.size > request.limit else request.cursor != null)) cursor(shown.first()) else null
            AgentMemoryBrowsePage(entries, counts(sql, request.kinds), next, previous)
        }
    }

    private fun select(sql: SQLiteDatabase, request: AgentMemoryBrowseRequest, kind: AgentMemoryKind?): List<Row> {
        val groups = request.section == AgentMemorySection.CONFLICTS
        val table = if (groups) AgentMemoryBrowseIndex.GROUPS else AgentMemoryBrowseIndex.ROWS
        val predicates = mutableListOf<String>()
        val args = mutableListOf<String>()
        if (!groups) { predicates += "state=?"; args += if (request.section == AgentMemorySection.ACTIVE) "ACTIVE" else "SUPERSEDED" }
        kind?.let { predicates += "kind=?"; args += it.name }
        if (request.publicOnly) {
            predicates += "private=0 AND (expiry=0 OR expiry>CAST(? AS INTEGER))"
            args += request.nowMillis.toString()
        }
        request.cursor?.let { cursor ->
            predicates += "(priority,sort_time,position,row_key)${if (request.backwards) "<" else ">"}(CAST(? AS INTEGER),CAST(? AS INTEGER),CAST(? AS INTEGER),?)"
            args += listOf(cursor.priority.toString(), cursor.time.toString(), cursor.position.toString(), cursor.key)
        }
        val columns = if (groups) "'CONFLICTED',kind,0,0,group_key,n" else "state,kind,private,expiry,group_key,0"
        val where = if (predicates.isEmpty()) "" else " WHERE " + predicates.joinToString(" AND ")
        val order = if (request.backwards) "priority DESC,sort_time DESC,position DESC,row_key DESC" else "priority,sort_time,position,row_key"
        return sql.rawQuery("SELECT row_key,priority,sort_time,position,$columns FROM $table$where " +
            "ORDER BY $order LIMIT ${request.limit + 1}", args.toTypedArray()).use { c ->
            buildList { while (c.moveToNext()) add(Row(c.getString(0), c.getInt(1), c.getLong(2), c.getLong(3),
                c.getString(4), c.getString(5), c.getInt(6), c.getLong(7), c.getString(8), c.getLong(9))) }
        }
    }
}

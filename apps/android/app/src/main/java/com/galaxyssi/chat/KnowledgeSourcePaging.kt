package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject

data class AgentKnowledgeSourceReference(val source: String, val localItemId: String = "")
data class AgentKnowledgeSourceCursor(val updated: Long, val groupKey: String, val revision: Long, val scope: String)
data class AgentKnowledgeSourcePage(val groups: List<AgentKnowledgeSourceGroup>, val total: Int,
    val next: AgentKnowledgeSourceCursor?, val positions: List<AgentKnowledgeSourceCursor> = emptyList(),
    val revision: Long = 0)
class KnowledgeSourcePageChanged : IllegalStateException("Knowledge sources changed; reload the first page")

internal data class KnowledgeSourceMetadata(val id: String, val title: String, val source: String,
    val cloud: AgentKnowledgeCloudAccess, val agent: AgentKnowledgeAgentAccess, val allowed: List<String>, val updated: Long) {
    fun encode() = JSONObject().put("id", id).put("title", title).put("source", source)
        .put("cloud", cloud.name).put("agent", agent.name).put("allowed", JSONArray(allowed)).put("updated", updated)
    companion object {
        fun from(item: AgentKnowledgeItem) = KnowledgeSourceMetadata(item.id, item.title, item.source,
            item.cloudAccess, item.agentAccess, item.allowedAgentIds, item.updatedAtMillis)
        fun decode(json: JSONObject) = KnowledgeSourceMetadata(json.getString("id"), json.getString("title"), json.getString("source"),
            AgentKnowledgeCloudAccess.valueOf(json.getString("cloud")), AgentKnowledgeAgentAccess.valueOf(json.getString("agent")),
            json.getJSONArray("allowed").let { a -> List(a.length()) { a.getString(it) } }, json.getLong("updated"))
    }
}

/** Pagination scans keyed SQL metadata, never all source bodies or all member IDs. */
internal class KnowledgeSourcePaging(private val storage: AgentKnowledgeDatabase) {
    private data class Row(val key: String, val updated: Long, val count: Int)
    fun count(): Int = storage.access(::count)
    private fun count(db: KnowledgeSqlite): Int = db.rawQuery("SELECT count(DISTINCT $GROUP) FROM knowledge_items", null).use {
        check(it.moveToFirst()); it.getInt(0)
    }
    fun page(cursor: AgentKnowledgeSourceCursor?, limit: Int): AgentKnowledgeSourcePage = storage.access { db ->
        require(limit in 1..50) { "Knowledge source page size must be between 1 and 50" }
        val scope = storage.key("source-page", "v1")
        val revision = db.rawQuery("SELECT revision FROM knowledge_browse_revision WHERE id=1", null).use {
            check(it.moveToFirst()); it.getLong(0)
        }
        if (cursor != null) {
            require(cursor.scope == scope && cursor.groupKey.matches(Regex("[si]:[a-f0-9]{64}"))) { "Invalid source cursor" }
            if (cursor.revision != revision) throw KnowledgeSourcePageChanged()
        }
        val having = if (cursor == null) "" else " HAVING max(updated)<CAST(? AS INTEGER) OR (max(updated)=CAST(? AS INTEGER) AND $GROUP>?)"
        val args = cursor?.let { arrayOf(it.updated.toString(), it.updated.toString(), it.groupKey) } ?: emptyArray()
        val rows = db.rawQuery("SELECT $GROUP AS group_key,max(updated),count(*) FROM knowledge_items GROUP BY group_key" +
            having + " ORDER BY max(updated) DESC,group_key LIMIT ${limit + 1}", args).use { c ->
            buildList { while (c.moveToNext()) add(Row(c.getString(0), c.getLong(1), c.getInt(2))) }
        }
        val shown = rows.take(limit)
        val groups = shown.map { row ->
            val (where, value) = predicate(row.key)
            val key = db.rawQuery("SELECT item_key FROM knowledge_items WHERE $where ORDER BY updated DESC,item_key LIMIT 1",
                arrayOf(value)).use { check(it.moveToFirst()); it.getString(0) }
            val summary = requireNotNull(storage.readSourceMetadata(db, key))
            check(summary.updated == row.updated) { "Knowledge source order mismatch" }
            AgentKnowledgeSourceGroup(summary.source, summary.title.substringBeforeLast(" [").ifBlank { summary.title },
                emptySet(), row.count, summary.cloud, summary.agent, summary.allowed, row.updated,
                AgentKnowledgeSourceReference(summary.source, if (summary.source.isBlank()) summary.id else ""))
        }
        val positions = shown.map { AgentKnowledgeSourceCursor(it.updated, it.key, revision, scope) }
        AgentKnowledgeSourcePage(groups, count(db), if (rows.size > limit) positions.last() else null, positions, revision)
    }

    // Access edits resolve membership only on demand, not while constructing the source list.
    fun itemIds(reference: AgentKnowledgeSourceReference): Set<String> = storage.access { db ->
        require(reference.source.isNotBlank() || reference.localItemId.isNotBlank()) { "Missing knowledge source identity" }
        require(reference.source.isBlank() || reference.localItemId.isBlank()) { "Ambiguous knowledge source identity" }
        val where = if (reference.source.isBlank()) "source_key='' AND item_key=?" else "source_key=?"
        val value = if (reference.source.isBlank()) storage.key("id", reference.localItemId) else storage.key("source", reference.source)
        val result = linkedSetOf<String>()
        var after = ""
        while (true) {
            val keys = db.rawQuery("SELECT item_key FROM knowledge_items WHERE $where AND item_key>? ORDER BY item_key LIMIT 64",
                arrayOf(value, after)).use { c -> buildList { while (c.moveToNext()) add(c.getString(0)) } }
            if (keys.isEmpty()) break
            keys.forEach { key ->
                val summary = requireNotNull(storage.readSourceMetadata(db, key))
                check(summary.source == reference.source) { "Knowledge source membership mismatch" }
                result += summary.id
            }
            after = keys.last()
        }
        result
    }
    private fun predicate(groupKey: String): Pair<String, String> =
        if (groupKey.startsWith("s:")) "source_key=?" to groupKey.substring(2)
        else "source_key='' AND item_key=?" to groupKey.substring(2)

    companion object {
        private const val GROUP = "CASE WHEN source_key='' THEN 'i:'||item_key ELSE 's:'||source_key END"
        fun create(db: KnowledgeSqlite) {
            db.execSQL("CREATE TABLE knowledge_browse_revision(id INTEGER PRIMARY KEY CHECK(id=1),revision INTEGER NOT NULL)")
            db.execSQL("INSERT INTO knowledge_browse_revision VALUES(1,0)")
            for (operation in listOf("INSERT", "UPDATE", "DELETE")) {
                db.execSQL("CREATE TRIGGER knowledge_browse_${operation.lowercase()} AFTER $operation ON knowledge_items " +
                    "BEGIN UPDATE knowledge_browse_revision SET revision=revision+1 WHERE id=1; END")
            }
            db.execSQL("CREATE INDEX knowledge_source_recent ON knowledge_items(source_key,updated DESC,item_key)")
        }
    }
}

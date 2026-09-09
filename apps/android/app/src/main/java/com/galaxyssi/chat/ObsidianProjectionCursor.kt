package com.galaxyssi.chat

import org.json.JSONObject

internal data class ObsidianProjectionCheckpoint(val namespace: String, val cursor: AgentKnowledgeSourceCursor, val visited: Int) {
    fun encode(): String = JSONObject().put("namespace", namespace).put("visited", visited)
        .put("updated", cursor.updated).put("key", cursor.groupKey).put("revision", cursor.revision)
        .put("scope", cursor.scope).toString()
    companion object {
        fun decode(raw: String): ObsidianProjectionCheckpoint? = runCatching {
            val json = JSONObject(raw)
            val visited = json.getInt("visited")
            require(visited > 0)
            ObsidianProjectionCheckpoint(json.getString("namespace"), AgentKnowledgeSourceCursor(
                json.getLong("updated"), json.getString("key"), json.getLong("revision"), json.getString("scope")), visited)
        }.getOrNull()
    }
}

/** One page per run. Completion means visited, not necessarily rewritten, sources. */
internal object ObsidianProjectionCursor {
    fun run(namespace: String, previous: ObsidianProjectionCheckpoint?, maximumWrites: Int,
        readPage: (AgentKnowledgeSourceCursor?) -> AgentKnowledgeSourcePage,
        currentRevision: () -> Long,
        visit: (AgentKnowledgeSourceGroup, Int) -> ObsidianProjectionBatchResult,
        save: (ObsidianProjectionCheckpoint?) -> Unit): ObsidianProjectionBatchResult {
        var checkpoint = previous?.takeIf { it.namespace == namespace }
        var page = try { readPage(checkpoint?.cursor) } catch (error: Exception) {
            if (checkpoint == null || (error !is KnowledgeSourcePageChanged && error !is IllegalArgumentException)) throw error
            save(null)
            checkpoint = null
            readPage(null)
        }
        if (checkpoint != null && checkpoint.visited > page.total) {
            save(null)
            checkpoint = null
            page = readPage(null)
        }
        check(page.positions.size == page.groups.size && page.groups.size <= 50)
        var visited = checkpoint?.visited ?: 0
        var written = 0
        var unchanged = 0
        for ((index, group) in page.groups.withIndex()) {
            val result = visit(group, (maximumWrites.coerceIn(0, 32) - written).coerceAtLeast(0))
            if (result.remaining > 0) break
            check(result.written + result.unchanged == 1)
            written += result.written
            unchanged += result.unchanged
            visited++
            // The visitor commits its file/index before progress advances. Replay skips its index.
            save(ObsidianProjectionCheckpoint(namespace, page.positions[index], visited))
        }
        if (currentRevision() != page.revision) {
            save(null)
            return ObsidianProjectionBatchResult(written, unchanged, maxOf(1, page.total - visited))
        }
        val remaining = (page.total - visited).coerceAtLeast(0)
        if (remaining == 0) save(null)
        return ObsidianProjectionBatchResult(written, unchanged, remaining)
    }
}

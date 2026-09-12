package com.galaxyssi.chat

/** Keeps bodies on encrypted disk; one writer transaction still defines the replacement boundary. */
internal class KnowledgeSourceReplacement(private val storage: AgentKnowledgeDatabase,
    private val staging: KnowledgeBackupStaging, private val source: String) {
    fun commit(): KnowledgeSourceMutation = storage.transaction { db ->
        var policy: KnowledgeSourcePolicy? = null
        var after: Long? = null
        val sourceKey = storage.key("source", source)
        while (true) {
            // The source index includes rowid, so this avoids sorting every remaining source key per page.
            val page = db.rawQuery("SELECT rowid,item_key FROM knowledge_items WHERE source_key=?" +
                (if (after == null) "" else " AND rowid>?") + " ORDER BY rowid LIMIT 64",
                if (after == null) arrayOf(sourceKey) else arrayOf(sourceKey, after.toString())).use { cursor ->
                buildList { while (cursor.moveToNext()) add(cursor.getLong(0) to cursor.getString(1)) }
            }
            if (page.isEmpty()) break
            for ((_, key) in page) {
                check(!Thread.currentThread().isInterrupted)
                val item = requireNotNull(storage.read(db, key))
                check(item.source == source) { "Knowledge source membership mismatch" }
                staging.rememberPrevious(item)
                val current = policy
                if (current == null || item.updatedAtMillis < current.updated ||
                    (item.updatedAtMillis == current.updated && key < current.key)) policy = KnowledgeSourcePolicy(item, key)
            }
            after = page.last().first
        }
        staging.finishPrevious()
        val change = KnowledgeSourceMutation(storage, staging, policy)
        // Validate every incoming identity before any canonical mutation.
        for (item in staging.incoming()) {
            check(!Thread.currentThread().isInterrupted)
            storage.read(db, storage.key("id", item.id))?.let {
                require(it.source == source) { "Knowledge ID belongs to another source" }
            }
        }
        for ((before, incoming) in staging.changes(includeUnchanged = true)) {
            check(!Thread.currentThread().isInterrupted)
            val next = incoming?.let(change::normalize)
            if (before == next) continue
            if (next == null) db.delete("knowledge_items", "item_key=?", arrayOf(storage.key("id", requireNotNull(before).id)))
            else storage.write(db, next)
        }
        change
    }
}

internal class KnowledgeSourcePolicy(item: AgentKnowledgeItem, val key: String) {
    val updated = item.updatedAtMillis
    val cloud = item.cloudAccess
    val agent = item.agentAccess
    val allowed = item.allowedAgentIds
}

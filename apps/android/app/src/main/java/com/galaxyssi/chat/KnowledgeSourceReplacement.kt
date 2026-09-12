package com.galaxyssi.chat

/** Prepare encrypted old bodies without the writer; validate the source again at publication. */
internal class KnowledgeSourceReplacement(private val storage: AgentKnowledgeDatabase,
    private val staging: KnowledgeBackupStaging, private val source: String) {
    fun commit(): KnowledgeSourceMutation = prepare().commit()

    fun prepare(onPage: (Long) -> Unit = {}): KnowledgePreparedSourceReplacement = storage.searchSnapshot().use { read -> read.access { db ->
        val selection = KnowledgeSourceSelection(storage, AgentKnowledgeSourceReference(source))
        val revision = selection.revision(db)
        var policy: KnowledgeSourcePolicy? = null
        var after: Long? = null
        var count = 0L
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
                read.checkActive()
                val item = requireNotNull(storage.read(db, key))
                check(item.source == source) { "Knowledge source membership mismatch" }
                staging.rememberPrevious(item)
                val current = policy
                if (current == null || item.updatedAtMillis < current.updated ||
                    (item.updatedAtMillis == current.updated && key < current.key)) policy = KnowledgeSourcePolicy(item, key)
            }
            after = page.last().first
            count = Math.addExact(count, page.size.toLong())
            onPage(count)
        }
        staging.finishPrevious()
        KnowledgePreparedSourceReplacement(storage, staging, selection, revision, policy)
    } }
}

internal class KnowledgeSourcePolicy(item: AgentKnowledgeItem, val key: String) {
    val updated = item.updatedAtMillis
    val cloud = item.cloudAccess
    val agent = item.agentAccess
    val allowed = item.allowedAgentIds
}

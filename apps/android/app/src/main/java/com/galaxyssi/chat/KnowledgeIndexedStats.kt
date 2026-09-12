package com.galaxyssi.chat

/** Reuse transactional directory counters; never aggregate the corpus on a query path. */
internal object KnowledgeIndexedStats {
    const val LATEST_SQL = "SELECT updated FROM knowledge_items ORDER BY updated DESC,item_key LIMIT 1"

    fun read(db: KnowledgeSqlite): AgentKnowledgeStats {
        val state = KnowledgeSourceDirectory.state(db)
        val latest = db.rawQuery(LATEST_SQL, null).use { if (it.moveToFirst()) it.getLong(0) else 0L }
        return AgentKnowledgeStats(state.items, state.namedGroups, latest, state.complete)
    }
}

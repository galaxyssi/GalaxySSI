package com.galaxyssi.chat

internal data class KnowledgeCorpusStamp(val changes: Long, val externalVersion: Long)

/** Keyset pages of opaque metadata, never an eager list of source text or all vectors. */
internal class KnowledgeVectorCatalog(private val storage: AgentKnowledgeDatabase, private val ledger: KnowledgeVectorLedger) {
    fun stamp(): KnowledgeCorpusStamp = storage.access { db ->
        val changes = db.rawQuery("SELECT total_changes()", null).use { check(it.moveToFirst()); it.getLong(0) }
        val external = db.rawQuery("PRAGMA data_version", null).use { check(it.moveToFirst()); it.getLong(0) }
        KnowledgeCorpusStamp(changes, external)
    }
    fun count(): Int = storage.access { db ->
        db.rawQuery("SELECT COALESCE(sum(chunk_count),0) FROM knowledge_vector_docs WHERE model_key=? AND complete=1",
            arrayOf(ledger.modelKey)).use {
            check(it.moveToFirst())
            val n = it.getLong(0)
            require(n in 0..Int.MAX_VALUE.toLong()) { "Semantic index is too large for one graph" }
            n.toInt()
        }
    }
    fun keys(after: String): List<String> = storage.access { db ->
        db.rawQuery("SELECT item_key FROM knowledge_vector_docs WHERE model_key=? AND complete=1 AND item_key>? " +
            "ORDER BY item_key LIMIT 32", arrayOf(ledger.modelKey, after)).use {
            buildList { while (it.moveToNext()) add(it.getString(0)) }
        }
    }
    fun resolve(matches: List<KnowledgeVectorMatch>, stamp: KnowledgeCorpusStamp): List<Pair<KnowledgeVectorMatch, AgentKnowledgeItem>> =
        storage.access { db ->
            check(stamp() == stamp) { "Knowledge changed during semantic retrieval" }
            matches.distinctBy { it.key }.mapNotNull { match ->
                val revision = db.rawQuery("SELECT header FROM knowledge_items WHERE item_key=?", arrayOf(match.key)).use {
                    if (it.moveToFirst()) AgentNativeJsonCodec.sha256(it.getString(0)) else null
                }
                if (revision != match.revision) null else storage.read(db, match.key)?.let { match to it }
            }
        }
}

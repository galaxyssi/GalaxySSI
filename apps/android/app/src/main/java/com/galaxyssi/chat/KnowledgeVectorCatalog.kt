package com.galaxyssi.chat

internal data class KnowledgeCorpusStamp(val epoch: String, val changes: Long, val completedChunks: Long)

/** Keyset pages of opaque metadata, never an eager list of source text or all vectors. */
internal class KnowledgeVectorCatalog(private val storage: AgentKnowledgeDatabase, private val ledger: KnowledgeVectorLedger) {
    fun stamp(): KnowledgeCorpusStamp = storage.access { db ->
        val state = ledger.changes().state(db)
        KnowledgeCorpusStamp(state?.epoch.orEmpty(), state?.head ?: 0, state?.completedChunks ?: 0)
    }
    fun count(): Int = storage.access { db ->
        ledger.changes().state(db)?.takeIf { it.bootstrapComplete }?.let {
            require(it.completedChunks <= Int.MAX_VALUE) { "Semantic index is too large for one graph" }
            return@access it.completedChunks.toInt()
        }
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

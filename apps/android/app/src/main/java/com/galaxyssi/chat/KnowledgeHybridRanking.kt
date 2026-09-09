package com.galaxyssi.chat

/** Reciprocal-rank fusion avoids comparing unrelated lexical and cosine score scales. */
internal object KnowledgeHybridRanking {
    fun fuse(lexical: List<AgentKnowledgeHit>, dense: List<AgentKnowledgeHit>, limit: Int): List<AgentKnowledgeHit> {
        require(limit >= 0)
        val hits = linkedMapOf<String, AgentKnowledgeHit>()
        val scores = mutableMapOf<String, Double>()
        listOf(lexical, dense).forEach { ranked ->
            ranked.distinctBy { it.item.id }.forEachIndexed { rank, hit ->
                hits.putIfAbsent(hit.item.id, hit)
                scores[hit.item.id] = scores.getOrDefault(hit.item.id, 0.0) + 1.0 / (60.0 + rank + 1.0)
            }
        }
        return hits.values.map { it.copy(score = scores.getValue(it.item.id)) }
            .sortedWith(compareByDescending<AgentKnowledgeHit> { it.score }.thenByDescending { it.item.updatedAtMillis }.thenBy { it.item.id })
            .take(limit)
    }
}

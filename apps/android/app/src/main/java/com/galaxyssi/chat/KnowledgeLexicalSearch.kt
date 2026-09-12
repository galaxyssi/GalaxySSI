package com.galaxyssi.chat

import java.util.Locale
import java.util.PriorityQueue

internal object KnowledgeLexicalSearch {
    fun search(snapshot: KnowledgeSearchSnapshot, query: String, limit: Int): List<AgentKnowledgeHit> {
        if (limit <= 0) return emptyList()
        if (query.isBlank()) return snapshot.recent(limit).map {
            AgentKnowledgeHit(it, 0.0, AgentKnowledgeCodec.excerpt(it.content, emptyList()), emptyList())
        }.toList()
        val clean = AgentKnowledgeTextAnalyzer.normalize(query).trim()
        val tokens = AgentKnowledgeTextAnalyzer.tokens(clean)
        val trigrams = AgentKnowledgeTextAnalyzer.trigrams(clean)
        val order = compareBy<AgentKnowledgeHit> { it.score }.thenBy { it.item.updatedAtMillis }.thenBy { it.item.id }
        val capacity = limit.coerceAtMost(24)
        val best = PriorityQueue(capacity, order)
        snapshot.candidates(clean, 256).forEach { item ->
            val score = AgentKnowledgeCodec.semanticScore(item, clean, tokens, trigrams)
            if (score >= 1.2) {
                val text = "${item.title} ${item.summary} ${item.tags.joinToString(" ")} ${item.content}".lowercase(Locale.US)
                val matched = tokens.filter(text::contains).distinct()
                val hit = AgentKnowledgeHit(item, score, AgentKnowledgeCodec.excerpt(item.content, matched), matched)
                if (best.size < capacity) best.add(hit) else if (order.compare(hit, best.peek()) > 0) {
                    best.poll(); best.add(hit)
                }
            }
        }
        snapshot.checkActive()
        return best.toList().sortedWith(order.reversed())
    }
}

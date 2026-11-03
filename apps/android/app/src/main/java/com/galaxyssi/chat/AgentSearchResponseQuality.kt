package com.galaxyssi.chat

/** A transport-quality signal, not a semantic verdict or a proof that no answer exists. */
internal object AgentSearchResponseQuality {
    fun disjoint(query: String, results: List<AgentWebIntelligenceRawResult>): Boolean {
        val terms = AgentWebIntelligenceText.tokens(query).filter { it.length > 1 }.toSet()
        if (terms.size < 2 || results.isEmpty()) return false
        return results.all {
            val text = AgentWebIntelligenceText.tokens("${it.title} ${it.excerpt} ${it.url}").toSet()
            terms.intersect(text).isEmpty()
        }
    }
}

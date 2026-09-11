package com.galaxyssi.chat

/** Candidate supersets preserve the existing substring semantics; final ranking checks the source. */
internal object AgentMemoryRecallTerms {
    fun document(item: AgentMemoryItem): Set<String> = buildSet {
        if (item.status != AgentMemoryStatus.ACTIVE || item.privateMemory) return@buildSet
        val value = item.value.lowercase()
        add("v:$value")
        value.forEach { add("c:$it") }
        "${item.key} $value".lowercase().windowed(2).forEach { add("g:$it") }
    }

    fun forward(query: String): List<Set<String>> = AgentMemoryRecallRanking.terms(query.lowercase()).map { term ->
        if (term.length == 1) setOf("c:$term") else term.windowed(2).mapTo(linkedSetOf()) { "g:$it" }
    }.filter { it.isNotEmpty() }

    fun reverse(query: String): Set<String> = buildSet {
        val clean = query.lowercase()
        // Long queries use a complete, broader gram union instead of a quadratic substring expansion.
        if (clean.length.toLong() * (clean.length + 1L) / 2 <= 4096L) {
            for (start in clean.indices) for (end in start + 1..clean.length) add("v:${clean.substring(start, end)}")
        } else {
            clean.forEach { add("v:$it") }
            clean.windowed(2).forEach { add("g:$it") }
        }
    }
}

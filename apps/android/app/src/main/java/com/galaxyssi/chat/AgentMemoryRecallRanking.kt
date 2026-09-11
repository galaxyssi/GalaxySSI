package com.galaxyssi.chat

import java.util.PriorityQueue

internal object AgentMemoryRecallRanking {
    private val structured = Regex("[\\p{L}\\p{N}]+(?:[-_.:][\\p{L}\\p{N}]+)+")
    fun queryTokens(value: String): Set<String> = (value.split(Regex("[^\\p{L}\\p{N}]+"))
        .filter { it.length >= 3 } + value.filter { it.code in 0x3400..0x9FFF }.windowed(2)).toSet()

    fun terms(query: String): Set<String> = linkedSetOf(query).apply {
        addAll(queryTokens(query)); addAll(structured.findAll(query).map { it.value })
    }

    fun lexical(item: AgentMemoryItem, query: String): Double {
        val value = item.value.lowercase()
        val searchable = "${item.key} $value".lowercase()
        val clean = query.lowercase()
        if (clean.isBlank()) return 0.0
        var result = if (value == clean) 12.0 else 0.0
        if (value.contains(clean) || clean.contains(value)) result += 8.0
        structured.findAll(clean).map { it.value }.toSet().forEach { if (searchable.contains(it)) result += 6.0 }
        queryTokens(clean).forEach { if (searchable.contains(it)) result += 1.0 }
        return result
    }

    fun score(item: AgentMemoryItem, query: String, now: Long): Double {
        val ageDays = (now - item.timestampMillis).coerceAtLeast(0L) / 86_400_000.0
        return lexical(item, query) * (0.5 + item.confidence.coerceIn(0.0, 1.0)) +
            1.0 / (1.0 + ageDays / 30.0) + kotlin.math.ln(1.0 + item.evidenceCount.coerceAtLeast(1)) +
            if (item.important) 2.0 else 0.0
    }
}

internal class AgentMemoryRecallTopK(private val query: String, private val now: Long, private val limit: Int) {
    private data class Ranked(val item: AgentMemoryItem, val position: Long, val score: Double)
    private val order = compareByDescending<Ranked> { it.score }.thenByDescending { it.item.important }
        .thenByDescending { it.item.timestampMillis }.thenBy { it.position }
    private val heap = PriorityQueue(order.reversed())
    init { require(limit > 0) }
    fun offer(item: AgentMemoryItem, position: Long) {
        if (item.status != AgentMemoryStatus.ACTIVE || item.privateMemory || item.isExpired(now) ||
            AgentMemoryRecallRanking.lexical(item, query) <= 0.0) return
        val ranked = Ranked(item, position, AgentMemoryRecallRanking.score(item, query, now))
        if (!(ranked.score > 0.0)) return
        if (heap.size < limit) heap.add(ranked)
        else if (order.compare(ranked, heap.peek()) < 0) { heap.poll(); heap.add(ranked) }
    }
    fun result(): List<AgentMemoryItem> = heap.sortedWith(order).map { it.item }
}

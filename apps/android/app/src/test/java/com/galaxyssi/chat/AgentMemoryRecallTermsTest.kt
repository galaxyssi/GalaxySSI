package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test
import kotlin.random.Random

class AgentMemoryRecallTermsTest {
    private fun item(value: String, key: String = "") = AgentMemoryItem(AgentMemoryKind.KNOWLEDGE, value, key = key)
    private fun candidate(value: AgentMemoryItem, query: String): Boolean {
        val terms = AgentMemoryRecallTerms.document(value)
        return AgentMemoryRecallTerms.forward(query).any { terms.containsAll(it) } ||
            AgentMemoryRecallTerms.reverse(query).any { it in terms }
    }

    @Test fun multilingualAndStructuredMatchesHaveNoCandidateFalseNegatives() {
        val values = listOf("a", "ab", "ABC", "a-b", "gpt-5.6-sol", "S26U", "\u4e2d\u6587", "\u5317\u4eac\u5929\u6c14", "a b",
            "v1.2.3", "route:51", "\u00c9cole", "\u0130stanbul", "\u03a3\u03af\u03b3\u03bc\u03b1", "\ud83d\ude00", "x_y", "https://example.com/a")
        val queries = values + values.map { "please recall $it now" } + listOf("\u4e2d \u6587", "bc", "5.6", ":", "x", "absent")
        for (value in values) for (key in values) for (query in queries) {
            val memory = item(value, key)
            if (AgentMemoryRecallRanking.lexical(memory, query) > 0) assertTrue("$value / $key / $query", candidate(memory, query))
        }
    }

    @Test fun randomizedSubstringMatchesHaveNoCandidateFalseNegatives() {
        val random = Random(41)
        val alphabet = "abCD012._- \u5317\u4eac\u5929\u6c14\u4e2d\u6587"
        fun text(length: Int) = (0 until length).map { alphabet[random.nextInt(alphabet.length)] }.joinToString("")
        repeat(5_000) {
            val value = text(random.nextInt(1, 35)).ifBlank { "a" }
            val query = when (it % 3) { 0 -> text(8) + value + text(5); 1 -> value.substring(random.nextInt(value.length)); else -> text(12) }.trim()
            val memory = item(value, text(8))
            if (query.isNotBlank() && AgentMemoryRecallRanking.lexical(memory, query) > 0) assertTrue(candidate(memory, query))
        }
    }

    @Test fun longReverseQueriesUseCompleteGramFallback() {
        val query = "prefix ".repeat(200) + "rare-middle-value" + " suffix".repeat(200)
        for (value in listOf("rare-middle-value", "x", "prefix", " suffix")) assertTrue(candidate(item(value), query))
        assertTrue(AgentMemoryRecallTerms.reverse(query).size < query.length)
    }

    @Test fun privateAndInactiveBodiesContributeNoTerms() {
        for (status in AgentMemoryStatus.entries) {
            if (status != AgentMemoryStatus.ACTIVE) assertTrue(AgentMemoryRecallTerms.document(item("private").copy(status = status)).isEmpty())
        }
        assertTrue(AgentMemoryRecallTerms.document(item("private").copy(privateMemory = true)).isEmpty())
    }

    @Test fun boundedTopKMatchesFullStableRankingAcrossManyPages() {
        val now = 1_000_000L
        val values = (0 until 1_000).map { index -> item("shared term", "shared").copy(id = "id-$index",
            confidence = (index % 10) / 10.0, evidenceCount = index % 7 + 1, timestampMillis = (index % 13).toLong(), important = index % 11 == 0) }
        val expected = values.withIndex().sortedWith(compareByDescending<IndexedValue<AgentMemoryItem>> {
            AgentMemoryRecallRanking.score(it.value, "shared", now)
        }.thenByDescending { it.value.important }.thenByDescending { it.value.timestampMillis }.thenBy { it.index }).take(8).map { it.value }
        val best = AgentMemoryRecallTopK("shared", now, 8)
        values.indices.shuffled(Random(17)).forEach { best.offer(values[it], it.toLong()) }
        assertEquals(expected, best.result())
    }

    @Test fun topKFiltersPrivateExpiredHistoricalAndUnmatchedItems() {
        val best = AgentMemoryRecallTopK("needle", 10_000L, 8)
        best.offer(item("needle").copy(privateMemory = true), 1)
        best.offer(item("needle").copy(expiresAtMillis = 999L), 2)
        best.offer(item("needle").copy(status = AgentMemoryStatus.SUPERSEDED), 3)
        best.offer(item("unrelated"), 4)
        assertTrue(best.result().isEmpty())
    }

    @Test fun legacyWeightsAndCaseFoldingArePreserved() {
        assertEquals(28.0, AgentMemoryRecallRanking.lexical(item("GPT-5.6-SOL"), "gpt-5.6-sol"), 0.0)
        assertEquals(20.0, AgentMemoryRecallRanking.lexical(item("A"), "a"), 0.0)
        assertEquals(9.0, AgentMemoryRecallRanking.lexical(item("\u5317\u4eac\u5929\u6c14"), "\u5317\u4eac"), 0.0)
        assertEquals(1.0, AgentMemoryRecallRanking.lexical(item("\u4e2d\u6587"), "\u4e2d \u6587"), 0.0)
        assertEquals(8.0, AgentMemoryRecallRanking.lexical(item("a"), "a longer query"), 0.0)
    }
}

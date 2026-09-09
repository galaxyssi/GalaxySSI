package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class KnowledgeHybridRankingTest {
    private fun hit(id: String, score: Double = 1.0) = AgentKnowledgeHit(
        AgentKnowledgeItem(id, AgentKnowledgeKind.NOTE, id, "content", updatedAtMillis = 1), score, id, emptyList())
    @Test fun twoIndependentRankingsPromoteSharedEvidence() {
        val result = KnowledgeHybridRanking.fuse(listOf(hit("lexical", 1000.0), hit("both")), listOf(hit("both", 0.6), hit("dense")), 3)
        assertEquals(listOf("both", "lexical", "dense"), result.map { it.item.id })
    }
    @Test fun duplicateChunksCannotInflateOneDocumentsRank() {
        val unique = KnowledgeHybridRanking.fuse(emptyList(), listOf(hit("a"), hit("b")), 3)
        val repeated = KnowledgeHybridRanking.fuse(emptyList(), listOf(hit("a"), hit("a"), hit("b")), 3)
        assertEquals(unique, repeated)
    }
    @Test fun emptyLegsAndLimitsRemainDeterministic() {
        assertTrue(KnowledgeHybridRanking.fuse(listOf(hit("a")), emptyList(), 0).isEmpty())
        assertEquals("a", KnowledgeHybridRanking.fuse(emptyList(), listOf(hit("a")), 1).single().item.id)
        assertThrows(IllegalArgumentException::class.java) { KnowledgeHybridRanking.fuse(emptyList(), emptyList(), -1) }
    }
}

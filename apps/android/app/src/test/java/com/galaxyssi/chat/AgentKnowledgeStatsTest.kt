package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class AgentKnowledgeStatsTest {
    @Test fun exactCountsKeepTheExistingSummaryAndSupport64BitValues() {
        assertEquals("3000000000 items; sources=2700000000", AgentKnowledgeStats(3_000_000_000L, 2_700_000_000L).countSummary())
    }
    @Test fun incompleteCountsCannotBeMistakenForExactOrEmptyCounts() {
        val text = AgentKnowledgeStats(countsComplete=false).countSummary()
        assertTrue(text.contains("at least 0")); assertTrue(text.contains("still indexing"))
        assertNotEquals(AgentKnowledgeStats().countSummary(), text)
    }
}

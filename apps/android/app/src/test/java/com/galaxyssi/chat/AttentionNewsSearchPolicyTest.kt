package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class AttentionNewsSearchPolicyTest {
    @Test fun queryTermsPreserveCjkAndLiteralPunctuation() {
        assertEquals(listOf("智能体", "AI", "50%_"), AttentionNewsSearchPolicy.terms("  智能体  AI\n50%_ 智能体 "))
        assertTrue(AttentionNewsSearchPolicy.terms(" \t\n").isEmpty())
    }
    @Test fun wildcardCharactersCannotExpandTheQuery() {
        assertEquals("%50\\%\\_\\\\%", AttentionNewsSearchPolicy.pattern("50%_\\"))
        assertEquals("%x' OR 1=1--%", AttentionNewsSearchPolicy.pattern("x' OR 1=1--"))
    }
    @Test fun highlightRangesMatchCaseAndIncludeMultipleOccurrences() {
        val text = "AI与智能体，ai"
        val parts = AttentionNewsSearchPolicy.ranges(text, "ai 智能体").map { text.substring(it) }
        assertEquals(listOf("AI", "ai", "智能体"), parts)
        assertTrue(AttentionNewsSearchPolicy.ranges(text, "不存在").isEmpty())
    }
    @Test fun allNewsIncludesReadAndSavedButNotUnpublishedMetadata() {
        val state = AttentionNewsSearchState(mapOf("old" to 10L, "new" to 0L), setOf(AttentionNewsSearchState.itemKey("old")))
        assertTrue(state.includes("old", AttentionNewsScope.ALL))
        assertTrue(state.includes("new", AttentionNewsScope.ALL))
        assertFalse(state.includes("draft", AttentionNewsScope.ALL))
        assertFalse(state.includes("old", AttentionNewsScope.UNREAD))
        assertTrue(state.includes("new", AttentionNewsScope.UNREAD))
        assertTrue(state.includes("old", AttentionNewsScope.SAVED))
        assertFalse(state.includes("new", AttentionNewsScope.SAVED))
    }
    @Test fun pageBoundariesNeverReportMoreAfterTheLastPage() {
        assertTrue(AttentionNewsPage(emptyList(), 31, 30).hasMore)
        assertFalse(AttentionNewsPage(emptyList(), 30, 30).hasMore)
        assertFalse(AttentionNewsPage(emptyList(), 0, 0).hasMore)
    }
}

package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class ScreenAssistantContentPolicyTest {
    @Test fun internalDocumentInstructionsDoNotDisqualifyChatProviders() {
        val turn = "content-requirements"
        val question = "Summarize this PDF"
        PhoneAssistantTaskControl.bind(turn, ScreenAssistantAnalysisRequest().apply { displayQuestion = question })
        try {
            val goal = ScreenAssistantContentPolicy.pageGoal(question, "Partial")
            val requirements = PhoneAssistantTaskControl.reasoningRequirements(turn, goal)
            assertFalse(AgentCapability.KNOWLEDGE_SEARCH in requirements.capabilities)
            assertTrue(AgentCapability.CHAT in requirements.capabilities)
            assertFalse(requirements.localOnly)
            assertTrue(requirements.estimatedInputTokens >= goal.length / 3)
        } finally { PhoneAssistantTaskControl.finish(turn) }
    }

    @Test fun explicitPrivacyIsPreservedAndOrdinaryRoutingIsUnchanged() {
        val question = "Summarize this PDF, local only"
        val goal = ScreenAssistantContentPolicy.pageGoal(question, "Partial")
        assertEquals(AgentTaskRequirementAnalyzer.analyze(goal), PhoneAssistantTaskControl.reasoningRequirements("ordinary", goal))
        PhoneAssistantTaskControl.bind("private-content", ScreenAssistantAnalysisRequest().apply { displayQuestion = question })
        try {
            val requirements = PhoneAssistantTaskControl.reasoningRequirements("private-content", goal)
            assertTrue(requirements.localOnly)
            assertEquals(AgentRoutingMode.PRIVATE, requirements.mode)
        } finally { PhoneAssistantTaskControl.finish("private-content") }
    }

    @Test fun visualBoundaryIgnoresTinyNoiseButNotNewContent() {
        val first = IntArray(3840) { 0xffffff }
        val noise = first.copyOf().apply { this[0] = 0 }
        val moved = first.copyOf().apply { repeat(200) { this[it] = 0 } }
        assertTrue(ScreenPageVisualPolicy.same(first, noise))
        assertFalse(ScreenPageVisualPolicy.same(first, moved))
        assertFalse(ScreenPageVisualPolicy.same(intArrayOf(), intArrayOf()))
    }
    @Test fun acceptsOnlyExplicitWebLinks() {
        assertEquals("https://example.org/report?q=1#chapter", ScreenAssistantContentPolicy.link(" https://example.org/report?q=1#chapter "))
        listOf("javascript:alert(1)", "file:///data/private", "content://secret", "hello", "https://", "https://user:secret@example.com").forEach {
            assertNull(it, ScreenAssistantContentPolicy.link(it))
        }
    }

    @Test fun pageInstructionsPreserveTheQuestionAndStateCoverageLimits() {
        val result = ScreenAssistantContentPolicy.pageGoal("Compare the conclusions", "Partial: 3 screens")
        assertTrue(result.startsWith("Compare the conclusions\n"))
        assertTrue(result.contains("Partial: 3 screens"))
        assertTrue(result.contains("untrusted evidence"))
        assertTrue(result.contains("Never invent chapter counts"))
        assertTrue(result.contains("Do not operate the phone"))
    }

    @Test fun linksUseReadingRatherThanUnrelatedSearches() {
        val result = ScreenAssistantContentPolicy.linkGoal("Summarize", "https://example.org/report")
        assertTrue(result.contains("https://example.org/report"))
        assertTrue(result.contains("existing web reading tools"))
        assertTrue(result.contains("search snippet"))
    }
}

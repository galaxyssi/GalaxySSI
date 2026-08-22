package com.signalasi.chat

import org.junit.Assert.assertNotSame
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentConversationTransportCacheTest {
    @Test
    fun `same conversation context reuses its compiled transport`() {
        val context = context("Keep this project constraint")

        val first = AgentConversationTransportCache.render(context, maximumTokens = 2_048)
        val second = AgentConversationTransportCache.render(context, maximumTokens = 2_048)

        assertSame(first, second)
    }

    @Test
    fun `new conversation context compiles a fresh transport`() {
        val original = context("Keep this project constraint")
        val updated = context("Use the newest project constraint")

        val first = AgentConversationTransportCache.render(original, maximumTokens = 2_048)
        val second = AgentConversationTransportCache.render(updated, maximumTokens = 2_048)

        assertNotSame(first, second)
        assertTrue(first.contains("Keep this project constraint"))
        assertTrue(second.contains("Use the newest project constraint"))
    }

    @Test
    fun `different token budgets compile separate transports`() {
        val context = context("Preserve this project context")

        val compact = AgentConversationTransportCache.render(context, maximumTokens = 1_024)
        val standard = AgentConversationTransportCache.render(context, maximumTokens = 2_048)

        assertNotSame(compact, standard)
        assertTrue(compact.contains("Preserve this project context"))
        assertTrue(standard.contains("Preserve this project context"))
    }

    private fun context(text: String): AgentConversationContext = AgentConversationContext(
        conversationId = "transport-cache-test",
        summary = "Project summary",
        turns = listOf(
            AgentTranscriptEntry(
                id = "user-turn",
                role = AgentTranscriptRole.USER,
                text = text,
                timestampMillis = 1L,
                conversationId = "transport-cache-test",
                turnId = "turn-1"
            )
        ),
        privateMode = false
    )
}

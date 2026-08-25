package com.signalasi.chat

import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentPreparedConversationContextCacheTest {
    @Test
    fun processUpdatesKeepPreparedDialogueContext() {
        val cache = AgentPreparedConversationContextCache()
        val context = context("conversation")
        cache.putIfCurrent(context, cache.version("conversation"))

        cache.invalidateTranscriptMutation("conversation", AgentTranscriptRole.PROCESS)

        assertSame(context, cache.get("conversation"))
    }

    @Test
    fun userAndAssistantUpdatesInvalidatePreparedDialogueContext() {
        listOf(AgentTranscriptRole.USER, AgentTranscriptRole.ASSISTANT).forEach { role ->
            val cache = AgentPreparedConversationContextCache()
            cache.putIfCurrent(context("conversation"), cache.version("conversation"))

            cache.invalidateTranscriptMutation("conversation", role)

            assertNull(cache.get("conversation"))
        }
    }

    @Test
    fun multiConversationInvalidationClearsEveryAffectedContext() {
        val cache = AgentPreparedConversationContextCache()
        cache.putIfCurrent(context("source"), cache.version("source"))
        cache.putIfCurrent(context("target"), cache.version("target"))

        cache.invalidate(listOf("source", "target"))

        assertNull(cache.get("source"))
        assertNull(cache.get("target"))
    }

    @Test
    fun staleBackgroundCompilationCannotRestoreInvalidatedContext() {
        val cache = AgentPreparedConversationContextCache()
        val startedAtVersion = cache.version("conversation")

        cache.invalidate("conversation")
        val accepted = cache.putIfCurrent(context("conversation"), startedAtVersion)

        assertNull(cache.get("conversation"))
        org.junit.Assert.assertFalse(accepted)
    }

    @Test
    fun currentPreparedContextCanBeReadWithoutRecompilation() {
        val cache = AgentPreparedConversationContextCache()
        val context = context("conversation")

        assertTrue(cache.putIfCurrent(context, cache.version("conversation")))

        assertSame(context, cache.get("conversation"))
    }

    private fun context(conversationId: String) = AgentConversationContext(
        conversationId = conversationId,
        summary = "summary",
        turns = emptyList(),
        privateMode = false
    )
}

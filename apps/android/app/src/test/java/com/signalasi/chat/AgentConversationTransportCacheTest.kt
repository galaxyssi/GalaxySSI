package com.signalasi.chat

import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotSame
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors

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

    @Test
    fun `current project goal is not duplicated in conversation transport`() {
        val currentGoal = "Update the Android project and submit a pull request"
        val context = context(currentGoal)

        val transport = AgentConversationTransportCache.render(
            context = context,
            maximumTokens = 2_048,
            currentGoal = currentGoal
        )

        assertFalse(transport.contains(currentGoal))
        assertTrue(transport.contains("Project summary"))
    }

    @Test
    fun `current goal only conversation has no redundant transport block`() {
        val currentGoal = "Update the Android project"
        val context = context(currentGoal).copy(summary = "")

        val transport = AgentConversationTransportCache.render(
            context = context,
            maximumTokens = 2_048,
            currentGoal = currentGoal
        )

        assertTrue(transport.isEmpty())
    }

    @Test
    fun `only the latest exact user goal is eligible for transport deduplication`() {
        val previous = AgentTranscriptEntry(
            id = "previous-user-turn",
            role = AgentTranscriptRole.USER,
            text = "Keep the existing project architecture",
            timestampMillis = 1L,
            conversationId = "transport-cache-test",
            turnId = "turn-1"
        )
        val latest = AgentTranscriptEntry(
            id = "latest-user-turn",
            role = AgentTranscriptRole.USER,
            text = "Implement the next change",
            timestampMillis = 2L,
            conversationId = "transport-cache-test",
            turnId = "turn-2"
        )
        val context = AgentConversationContext(
            conversationId = "transport-cache-test",
            summary = "Project summary",
            turns = listOf(previous, latest),
            privateMode = false
        )

        val transport = AgentConversationTransportCache.render(
            context = context,
            maximumTokens = 2_048,
            currentGoal = latest.text
        )

        assertTrue(transport.contains(previous.text))
        assertFalse(transport.contains(latest.text))
    }

    @Test
    fun `concurrent transport compilation converges on one cached value`() {
        val context = context("Concurrent project context " + "detail ".repeat(2_000))
        val start = CountDownLatch(1)
        val executor = Executors.newFixedThreadPool(8)

        val futures = (1..8).map {
            executor.submit<String> {
                start.await()
                AgentConversationTransportCache.render(context, maximumTokens = 2_048)
            }
        }
        start.countDown()
        val results = futures.map { future -> future.get() }
        executor.shutdownNow()

        assertTrue(results.drop(1).all { result -> result === results.first() })
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

package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class AgentConnectorUsageTest {
    private val reply = AgentConnectorResponse(7, "contact", "reply", "conversation", "turn", "task",
        inputTokens = 20, outputTokens = 10, costMicros = 3, executionGeneration = 1)

    @Test fun usageIsBoundToExactExecutionIdentity() {
        val usage = AgentConnectorUsage.from(reply)
        val variants = listOf(reply.copy(sourceMessageId = 8), reply.copy(contactId = "other"),
            reply.copy(conversationId = "other"), reply.copy(turnId = "other"), reply.copy(taskId = "other"),
            reply.copy(executionGeneration = 2))
        variants.forEach { assertNotEquals(usage.key, AgentConnectorUsage.from(it).key) }
        assertEquals(usage.key, AgentConnectorUsage.from(reply.copy(receivedAtMillis = 99)).key)
    }

    @Test fun digestBindsEveryCounterWithoutChangingMessageIdentity() {
        val usage = AgentConnectorUsage.from(reply)
        listOf(reply.copy(inputTokens = 21), reply.copy(outputTokens = 11), reply.copy(costMicros = 4)).forEach {
            val other = AgentConnectorUsage.from(it)
            assertEquals(usage.key, other.key)
            assertNotEquals(usage.digest, other.digest)
        }
        assertTrue(usage.digest.matches(Regex("[a-f0-9]{64}")))
    }

    @Test fun negativeProviderValuesNormalizeBeforeBinding() {
        val usage = AgentConnectorUsage.from(reply.copy(inputTokens = -1, outputTokens = -2, costMicros = -3))
        assertEquals(usage.copy(inputTokens = 0, outputTokens = 0, costMicros = 0), usage)
    }

    @Test fun sumsWithoutChangingConversationOrderingOrSelection() {
        val previous = AgentConversation("conversation", "title", createdAt = 1, updatedAt = 2,
            inputTokens = 3, outputTokens = 4, costMicros = 5, pinned = true)
        assertEquals(previous.copy(inputTokens = 23, outputTokens = 14, costMicros = 8),
            AgentConnectorUsage.from(reply).applyTo(previous))
    }

    @Test fun hostileLargeCountersCannotOverflow() {
        val limit = Long.MAX_VALUE / 2
        val previous = AgentConversation("conversation", "title", createdAt = 1, updatedAt = 2,
            inputTokens = limit - 1, outputTokens = Long.MAX_VALUE, costMicros = -10)
        val updated = AgentConnectorUsage.from(reply.copy(inputTokens = Long.MAX_VALUE,
            outputTokens = Long.MAX_VALUE, costMicros = Long.MAX_VALUE)).applyTo(previous)
        assertEquals(limit, updated.inputTokens)
        assertEquals(limit, updated.outputTokens)
        assertEquals(limit, updated.costMicros)
    }

    @Test fun malformedProjectionIdentityIsRejected() {
        assertTrue(runCatching { AgentConnectorUsage("", 1, 1, 1) }.isFailure)
        assertTrue(runCatching { AgentConnectorUsage("a".repeat(64), -1, 1, 1) }.isFailure)
    }
}

package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentReplyWaitingIndicatorPolicyTest {
    @Test
    fun pendingTurnAddsTransientAssistantIndicator() {
        val user = entry("user", AgentTranscriptRole.USER, "turn-1", 100L)

        val result = AgentReplyWaitingIndicatorPolicy.apply(
            entries = listOf(user),
            pending = listOf(PendingAgentReplyIndicator("conversation", "turn-1", 50L)),
            conversationId = "conversation"
        )

        assertEquals(2, result.entries.size)
        assertTrue(AgentReplyWaitingIndicatorPolicy.isIndicator(result.entries.last()))
        assertTrue(result.resolvedTurnIds.isEmpty())
    }

    @Test
    fun indicatorIsAlwaysAfterTheLatestVisibleOutput() {
        val user = entry("user", AgentTranscriptRole.USER, "turn-1", 100L)
        val process = entry("process", AgentTranscriptRole.PROCESS, "turn-1", 120L)

        val result = AgentReplyWaitingIndicatorPolicy.apply(
            entries = listOf(user, process),
            pending = listOf(PendingAgentReplyIndicator("conversation", "turn-1", 50L)),
            conversationId = "conversation"
        )

        assertEquals("user", result.entries[0].id)
        assertEquals("process", result.entries[1].id)
        assertTrue(AgentReplyWaitingIndicatorPolicy.isIndicator(result.entries[2]))
    }

    @Test
    fun firstAssistantOutputResolvesIndicator() {
        val entries = listOf(
            entry("user", AgentTranscriptRole.USER, "turn-1", 100L),
            entry("assistant", AgentTranscriptRole.ASSISTANT, "turn-1", 120L)
        )

        val result = AgentReplyWaitingIndicatorPolicy.apply(
            entries = entries,
            pending = listOf(PendingAgentReplyIndicator("conversation", "turn-1", 101L)),
            conversationId = "conversation"
        )

        assertEquals(entries, result.entries)
        assertEquals(setOf("turn-1"), result.resolvedTurnIds)
        assertFalse(result.entries.any(AgentReplyWaitingIndicatorPolicy::isIndicator))
    }

    @Test
    fun deliveryFailureReplyResolvesIndicator() {
        val entries = listOf(
            entry("user", AgentTranscriptRole.USER, "turn-1", 100L),
            AgentTranscriptEntry(
                id = "delivery-failure",
                role = AgentTranscriptRole.ASSISTANT,
                text = "Message not delivered. Check the connection, then retry.",
                timestampMillis = 120L,
                dedupeKey = AgentDeliveryFailureRecorder.dedupeKey(42L),
                conversationId = "conversation",
                turnId = "turn-1",
                taskId = "turn-1"
            )
        )

        val result = AgentReplyWaitingIndicatorPolicy.apply(
            entries = entries,
            pending = listOf(PendingAgentReplyIndicator("conversation", "turn-1", 101L)),
            conversationId = "conversation"
        )

        assertEquals(setOf("turn-1"), result.resolvedTurnIds)
        assertFalse(result.entries.any(AgentReplyWaitingIndicatorPolicy::isIndicator))
    }

    @Test
    fun pendingIndicatorsStayInsideTheirConversationAndTurn() {
        val result = AgentReplyWaitingIndicatorPolicy.apply(
            entries = listOf(entry("user", AgentTranscriptRole.USER, "turn-1", 100L)),
            pending = listOf(
                PendingAgentReplyIndicator("conversation", "turn-1", 101L),
                PendingAgentReplyIndicator("other", "turn-2", 102L)
            ),
            conversationId = "conversation"
        )

        assertEquals(1, result.entries.count(AgentReplyWaitingIndicatorPolicy::isIndicator))
        assertEquals("turn-1", result.entries.last().turnId)
    }

    @Test
    fun multiplePendingTurnsRenderOnlyTheLatestIndicatorAtTheBottom() {
        val result = AgentReplyWaitingIndicatorPolicy.apply(
            entries = listOf(
                entry("user-1", AgentTranscriptRole.USER, "turn-1", 100L),
                entry("process", AgentTranscriptRole.PROCESS, "turn-1", 110L),
                entry("user-2", AgentTranscriptRole.USER, "turn-2", 120L)
            ),
            pending = listOf(
                PendingAgentReplyIndicator("conversation", "turn-1", 101L),
                PendingAgentReplyIndicator("conversation", "turn-2", 121L)
            ),
            conversationId = "conversation"
        )

        assertEquals(1, result.entries.count(AgentReplyWaitingIndicatorPolicy::isIndicator))
        assertEquals("turn-2", result.entries.last().turnId)
        assertEquals(setOf("turn-1"), result.resolvedTurnIds)
    }

    @Test
    fun terminalAndUserControlledPhasesStopWaiting() {
        listOf(
            AgentPhase.WAITING_CONFIRMATION,
            AgentPhase.PAUSED,
            AgentPhase.BLOCKED,
            AgentPhase.COMPLETED,
            AgentPhase.FAILED,
            AgentPhase.CANCELLED
        ).forEach { phase ->
            assertTrue("$phase should stop waiting", AgentReplyWaitingIndicatorPolicy.stopsFor(phase))
        }
        assertFalse(AgentReplyWaitingIndicatorPolicy.stopsFor(AgentPhase.EXECUTING))
        assertFalse(AgentReplyWaitingIndicatorPolicy.stopsFor(AgentPhase.WAITING_RESPONSE))
    }

    private fun entry(
        id: String,
        role: AgentTranscriptRole,
        turnId: String,
        timestampMillis: Long
    ) = AgentTranscriptEntry(
        id = id,
        role = role,
        text = id,
        timestampMillis = timestampMillis,
        conversationId = "conversation",
        turnId = turnId,
        taskId = turnId
    )
}

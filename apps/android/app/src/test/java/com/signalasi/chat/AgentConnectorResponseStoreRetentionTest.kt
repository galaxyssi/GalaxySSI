package com.signalasi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentConnectorResponseStoreRetentionTest {
    @Test
    fun liveTurnRemovesOnlyHandledResponse() {
        val handled = response(sourceId = 10L)
        val continuation = response(sourceId = 11L)

        val retained = AgentConnectorResponseStore.retainedAfterHandledResponse(
            responses = listOf(handled, continuation),
            handled = handled,
            terminal = false
        )

        assertEquals(listOf(continuation), retained)
    }

    @Test
    fun terminalTurnRemovesAllResponsesForTurn() {
        val handled = response(sourceId = 10L)
        val continuation = response(sourceId = 11L)
        val otherTurn = response(sourceId = 12L, turnId = "turn-2")

        val retained = AgentConnectorResponseStore.retainedAfterHandledResponse(
            responses = listOf(handled, continuation, otherTurn),
            handled = handled,
            terminal = true
        )

        assertEquals(listOf(otherTurn), retained)
    }

    @Test
    fun durableIdentityUsesSourceAndContact() {
        val response = response(sourceId = 10L)

        assertTrue(AgentConnectorResponseStore.matches(response, response.copy(content = "updated")))
        assertFalse(AgentConnectorResponseStore.matches(response, response.copy(sourceMessageId = 11L)))
        assertFalse(AgentConnectorResponseStore.matches(response, response.copy(contactId = "hermes")))
    }

    private fun response(
        sourceId: Long,
        turnId: String = "turn-1"
    ) = AgentConnectorResponse(
        sourceMessageId = sourceId,
        contactId = "codex",
        content = "{}",
        conversationId = "conversation-1",
        turnId = turnId,
        taskId = turnId
    )
}

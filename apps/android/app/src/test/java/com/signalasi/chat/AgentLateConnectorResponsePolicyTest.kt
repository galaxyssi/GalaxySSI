package com.signalasi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentLateConnectorResponsePolicyTest {
    @Test
    fun `terminal failure never accepts a late result`() {
        val entries = listOf(entry(AgentTranscriptRole.USER, "turn-1"))

        assertFalse(
            AgentLateConnectorResponsePolicy.canAccept(
                sourceIsTerminal = true,
                exactTurnId = "turn-1",
                conversationEntries = entries
            )
        )
    }

    @Test
    fun `orphan response without exact identity never guesses latest turn`() {
        val entries = listOf(entry(AgentTranscriptRole.USER, "turn-1"))

        assertNull(
            AgentLateConnectorResponsePolicy.exactTurnId(
                explicitTurnId = "",
                taskTurnId = "",
                indexedTurnId = "",
                conversationEntries = entries
            )
        )
    }

    @Test
    fun `exact unanswered turn accepts response`() {
        val entries = listOf(entry(AgentTranscriptRole.USER, "turn-1"))
        val turnId = AgentLateConnectorResponsePolicy.exactTurnId(
            explicitTurnId = "turn-1",
            taskTurnId = "",
            indexedTurnId = "",
            conversationEntries = entries
        )

        assertEquals("turn-1", turnId)
        assertTrue(
            AgentLateConnectorResponsePolicy.canAccept(
                sourceIsTerminal = false,
                exactTurnId = turnId,
                conversationEntries = entries
            )
        )
    }

    @Test
    fun `already answered turn rejects duplicate late result`() {
        val entries = listOf(
            entry(AgentTranscriptRole.USER, "turn-1"),
            entry(AgentTranscriptRole.ASSISTANT, "turn-1")
        )

        assertFalse(
            AgentLateConnectorResponsePolicy.canAccept(
                sourceIsTerminal = false,
                exactTurnId = "turn-1",
                conversationEntries = entries
            )
        )
    }

    @Test
    fun `response cannot bind to a user turn from another conversation`() {
        val entries = listOf(entry(AgentTranscriptRole.USER, "turn-2"))

        assertNull(
            AgentLateConnectorResponsePolicy.exactTurnId(
                explicitTurnId = "turn-1",
                taskTurnId = "",
                indexedTurnId = "",
                conversationEntries = entries
            )
        )
    }

    private fun entry(role: AgentTranscriptRole, turnId: String) = AgentTranscriptEntry(
        id = "${role.name}-$turnId",
        role = role,
        text = role.name,
        timestampMillis = 1L,
        dedupeKey = "${role.name}-$turnId",
        conversationId = "conversation-1",
        turnId = turnId,
        taskId = turnId
    )
}

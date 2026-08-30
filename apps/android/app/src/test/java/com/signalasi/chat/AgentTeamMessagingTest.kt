package com.signalasi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentTeamMessagingTest {
    @Test
    fun directAndBroadcastMessagesAreFilteredPerInstance() {
        val mailbox = InMemoryAgentTeamMailbox()
        val direct = mailbox.append(message("direct", to = "codex-reviewer"))
        val broadcast = mailbox.append(message("broadcast"))

        assertEquals(listOf(direct, broadcast), mailbox.messages("run-1", "codex-reviewer"))
        assertEquals(listOf(broadcast), mailbox.messages("run-1", "claude-researcher"))
        assertEquals(listOf(broadcast), mailbox.messages("run-1", afterSequence = direct.sequence))
    }

    @Test
    fun appendIsIdempotentAndDeliveryStateIsMonotonic() {
        val mailbox = InMemoryAgentTeamMailbox()
        val first = mailbox.append(message("verify", id = "message-1"))
        val duplicate = mailbox.append(message("changed", id = "message-1"))

        assertEquals(first, duplicate)
        assertEquals(1, mailbox.messages("run-1").size)
        val delivered = mailbox.markDelivered("message-1", 200L)!!
        val repeatedDelivery = mailbox.markDelivered("message-1", 150L)!!
        val acknowledged = mailbox.acknowledge("message-1", 180L)!!

        assertEquals(AgentTeamMessageState.DELIVERED, delivered.state)
        assertEquals(200L, repeatedDelivery.deliveredAtMillis)
        assertEquals(AgentTeamMessageState.ACKNOWLEDGED, acknowledged.state)
        assertTrue(acknowledged.deliveredAtMillis > 0L)
        assertTrue(acknowledged.acknowledgedAtMillis >= acknowledged.deliveredAtMillis)
    }

    @Test
    fun restoredMailboxKeepsSequenceMonotonicAfterCompaction() {
        val mailbox = InMemoryAgentTeamMailbox(listOf(
            message("older", id = "message-4900").copy(sequence = 4_900L),
            message("latest", id = "message-5000").copy(sequence = 5_000L)
        ))

        val appended = mailbox.append(message("next", id = "message-5001"))

        assertEquals(5_001L, appended.sequence)
        assertEquals(listOf(appended), mailbox.messages("run-1", afterSequence = 5_000L))
    }

    @Test
    fun codecRoundTripPreservesProtocolAndRouting() {
        val source = listOf(
            message("review this", id = "message-1", to = "codex-reviewer").copy(
                sequence = 7L,
                metadata = mapOf("artifact_id" to "patch-1")
            )
        )

        val decoded = AgentTeamMessageCodec.decode(AgentTeamMessageCodec.encode(source).toString())

        assertEquals(source, decoded)
        assertEquals(AgentTeamMessageEnvelope.PROTOCOL, decoded.single().protocol)
        assertFalse(decoded.single().isBroadcast)
    }

    private fun message(text: String, id: String = text, to: String = "") = AgentTeamMessageEnvelope(
        messageId = id,
        teamId = "team-1",
        conversationId = "conversation-1",
        supervisorRunId = "run-1",
        fromInstanceId = "user",
        toInstanceId = to,
        kind = AgentTeamMessageKind.USER_DIRECTIVE,
        text = text,
        createdAtMillis = 100L
    )
}

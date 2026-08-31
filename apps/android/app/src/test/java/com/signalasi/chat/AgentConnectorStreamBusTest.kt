package com.signalasi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentConnectorStreamBusTest {
    @Test
    fun publishesEphemeralUpdatesWithoutUsingTheDurableResponseStore() {
        val received = mutableListOf<AgentConnectorStreamUpdate>()
        val listener = AgentConnectorStreamListener(received::add)
        AgentConnectorStreamBus.addListener(listener)
        try {
            val update = AgentConnectorStreamUpdate(
                sourceMessageId = 42L,
                contactId = "cloud:deepseek",
                content = "first model token",
                conversationId = "conversation",
                turnId = "turn",
                taskId = "turn",
                firstDelta = true
            )

            assertTrue(AgentConnectorStreamBus.publish(update))
            assertEquals(listOf(update), received)
        } finally {
            AgentConnectorStreamBus.removeListener(listener)
        }
    }

    @Test
    fun rejectsUpdatesThatCannotBeCorrelatedToARequest() {
        assertFalse(
            AgentConnectorStreamBus.publish(
                AgentConnectorStreamUpdate(
                    sourceMessageId = 0L,
                    contactId = "cloud:deepseek",
                    content = "ignored"
                )
            )
        )
    }

    @Test
    fun suppressesManagedTeamStreamsUntilTheFinalResponseIsConsumed() {
        AgentManagedConnectorResponseRegistry.clear()
        val received = mutableListOf<AgentConnectorStreamUpdate>()
        val listener = AgentConnectorStreamListener(received::add)
        AgentConnectorStreamBus.addListener(listener)
        var finalResponses = 0
        try {
            AgentManagedConnectorResponseRegistry.register(
                sourceMessageId = 73L,
                contactId = "cloud:deepseek",
                ownerId = "observer-run",
                conversationId = "conversation",
                turnId = "turn",
                taskId = "task"
            ) { finalResponses += 1; true }
            val update = AgentConnectorStreamUpdate(
                sourceMessageId = 73L,
                contactId = "cloud:deepseek",
                content = "internal observer evidence",
                conversationId = "conversation",
                turnId = "turn",
                taskId = "task",
                firstDelta = true
            )

            assertTrue(AgentConnectorStreamBus.publish(update))
            assertTrue(received.isEmpty())
            assertTrue(AgentManagedConnectorResponseRegistry.consume(AgentConnectorResponse(
                sourceMessageId = 73L,
                contactId = "cloud:deepseek",
                content = "internal observer result",
                conversationId = "conversation",
                turnId = "turn",
                taskId = "task"
            )))
            assertEquals(1, finalResponses)
        } finally {
            AgentConnectorStreamBus.removeListener(listener)
            AgentManagedConnectorResponseRegistry.clear()
        }
    }
}

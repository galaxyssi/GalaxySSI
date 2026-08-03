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
}

package com.signalasi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.json.JSONObject
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

    @Test
    fun routesOnlyIdentityMatchedManagedTaskEventsAwayFromTheMainConversation() {
        AgentManagedConnectorResponseRegistry.clear()
        try {
            AgentManagedConnectorResponseRegistry.register(
                sourceMessageId = 91L,
                contactId = "desktop:codex",
                ownerId = "eval-run",
                conversationId = "agent-lab:campaign",
                turnId = "trial-1",
                taskId = "campaign:trial-1"
            ) { true }
            val matching = JSONObject()
                .put("conversation_id", "agent-lab:campaign")
                .put("turn_id", "trial-1")
                .put("task_id", "campaign:trial-1")
            val foreground = JSONObject()
                .put("conversation_id", "foreground")
                .put("turn_id", "turn-1")
                .put("task_id", "task-1")

            assertTrue(AgentTaskEventRoutingPolicy.isManaged(matching, 91L, "desktop:codex"))
            assertFalse(AgentTaskEventRoutingPolicy.isManaged(foreground, 91L, "desktop:codex"))
        } finally {
            AgentManagedConnectorResponseRegistry.clear()
        }
    }
}

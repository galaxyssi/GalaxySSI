package com.signalasi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentTaskIdentityPolicyTest {
    @Test
    fun generatedIdentityIsStableForTheSameOutboundTurn() {
        val conversationId = AgentTaskIdentityPolicy.conversationId("codex", "")
        val turnId = AgentTaskIdentityPolicy.turnId(42L, "")
        val first = AgentTaskIdentityPolicy.taskId(
            "signalasi:phone",
            "codex",
            42L,
            conversationId,
            turnId
        )
        val second = AgentTaskIdentityPolicy.taskId(
            "signalasi:phone",
            "codex",
            42L,
            conversationId,
            turnId
        )

        assertEquals("contact:codex", conversationId)
        assertEquals("message:42", turnId)
        assertEquals(first, second)
    }

    @Test
    fun desktopResponseRequiresAllFourIdentityLevelsToMatch() {
        val expected = mapOf(
            "resource_location" to "desktop",
            "conversation_id" to "conversation-a",
            "remote_task_id" to "task-a",
            "turn_id" to "turn-a"
        )

        assertTrue(
            AgentTaskIdentityPolicy.matchesDesktopResponse(
                expected,
                "conversation-a",
                "task-a",
                "turn-a"
            )
        )
        assertFalse(
            AgentTaskIdentityPolicy.matchesDesktopResponse(
                expected,
                "conversation-b",
                "task-a",
                "turn-a"
            )
        )
        assertFalse(
            AgentTaskIdentityPolicy.matchesDesktopResponse(
                expected,
                "conversation-a",
                "task-a",
                "turn-b"
            )
        )
        assertFalse(
            AgentTaskIdentityPolicy.matchesDesktopResponse(
                expected,
                "conversation-a",
                "",
                "turn-a"
            )
        )
    }

    @Test
    fun nonDesktopResponsesKeepTheirExistingLocalRouting() {
        assertTrue(
            AgentTaskIdentityPolicy.matchesDesktopResponse(
                mapOf("resource_location" to "cloud"),
                "",
                "",
                ""
            )
        )
    }

    @Test
    fun persistedMainAgentConversationRoutesWithoutLiveRuntime() {
        assertTrue(
            AgentTaskIdentityPolicy.routesToMainAgent(
                superseded = false,
                hasRuntime = false,
                resolvedConversationId = "conversation-a"
            )
        )
        assertFalse(
            AgentTaskIdentityPolicy.routesToMainAgent(
                superseded = false,
                hasRuntime = false,
                resolvedConversationId = ""
            )
        )
    }

    @Test
    fun persistedDeliveryRestoresCanonicalIdentityAfterProcessRestart() {
        val identity = AgentTaskIdentityPolicy.canonicalConnectorResponseIdentity(
            pendingDelivery = AgentPendingDelivery(
                sourceMessageId = 3308L,
                conversationId = "conversation-a",
                turnId = "cfca1de7-original-turn",
                taskId = "task-a",
                contactId = "codex"
            ),
            conversationId = "conversation-a",
            taskId = "task-a",
            turnId = "message:3308"
        )

        assertEquals("conversation-a", identity.conversationId)
        assertEquals("task-a", identity.taskId)
        assertEquals("cfca1de7-original-turn", identity.turnId)
    }
}

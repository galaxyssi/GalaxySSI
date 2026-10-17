package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class ConversationScheduledReplyPolicyTest {
    private val entry = AgentTranscriptEntry("reply", AgentTranscriptRole.ASSISTANT, "Result", 1L,
        "scheduled-result:run", "chat", "run", "run")

    private fun project(value: AgentTranscriptEntry = entry, destination: String? = "chat",
        executionOwner: String? = "proactive:task", canonical: (String) -> String? = { it }) =
        ConversationScheduledReplyPolicy.projectLegacy(value, { executionOwner }, { destination }, canonical)

    @Test fun deliveryIdentityIsDistinctFromExecutionAndOtherDestinations() {
        val id = ConversationScheduledReplyPolicy.turnId("chat", "run")
        assertNotEquals("run", id)
        assertNotEquals(ConversationScheduledReplyPolicy.turnId("other", "run"), id)
        assertNotEquals(ConversationScheduledReplyPolicy.turnId("chat", "next"), id)
        assertEquals(id, ConversationScheduledReplyPolicy.turnId("chat", "run"))
    }

    @Test fun verifiedLegacyDeliveryKeepsUnreadAndMessageIdentity() {
        val projected = project()
        assertEquals(ConversationScheduledReplyPolicy.turnId("chat", "run"), projected.turnId)
        assertEquals(entry, projected.copy(turnId = entry.turnId))
        assertEquals(AgentReplyUnreadPolicy.token(entry), AgentReplyUnreadPolicy.token(projected))
        assertEquals(emptySet<String>(), AgentReplyUnreadPolicy.remaining(setOf(entry.dedupeKey), listOf(projected)))
        assertEquals(projected, project(projected))
    }

    @Test fun foreignMissingAndDeletedDestinationsNeverGainOwnership() {
        assertEquals(entry, project(destination = "other"))
        assertEquals(entry, project(destination = null))
        assertEquals(entry, project(canonical = { null }))
        assertEquals(entry, project(executionOwner = "other-chat"))
        assertEquals(entry, project(executionOwner = null))
    }

    @Test fun normalRepliesAndMismatchedExecutionIdentifiersAreNotProjected() {
        for (value in listOf(entry.copy(role = AgentTranscriptRole.USER),
            entry.copy(dedupeKey = "final:run"), entry.copy(dedupeKey = "scheduled-result:other"),
            entry.copy(taskId = "other"), entry.copy(turnId = ""))) {
            assertEquals(value, project(value))
        }
    }

    @Test fun explicitConversationMergeIsSupportedWithoutWeakeningIsolation() {
        val projected = project(destination = "child", canonical = { if (it == "child") "chat" else it })
        assertNotEquals(entry.turnId, projected.turnId)
    }
}

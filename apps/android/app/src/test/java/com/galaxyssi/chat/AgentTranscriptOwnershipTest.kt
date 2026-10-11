package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class AgentTranscriptOwnershipTest {
    @Test fun activeScreenCannotOverrideTheOriginalTurn() {
        assertFalse(AgentTranscriptOwnership.accepts("group", listOf("chat")) { it })
        assertFalse(AgentTranscriptOwnership.accepts("group", listOf("group", "chat")) { it })
        assertTrue(AgentTranscriptOwnership.accepts("group", listOf("group", null, "")) { it })
    }

    @Test fun explicitMergedConversationsRemainSupported() {
        assertTrue(AgentTranscriptOwnership.accepts("parent", listOf("child")) {
            if (it == "child") "parent" else it
        })
    }

    @Test fun deletedDestinationIsNotReplacedByTheSelectedConversation() {
        assertFalse(AgentTranscriptOwnership.accepts("removed", emptyList()) { null })
    }

    @Test fun legacyForeignRowsAreQuarantinedWithoutDeletingTheOriginal() {
        val original = AgentTranscriptEntry("original", AgentTranscriptRole.ASSISTANT, "Other answer", 1,
            conversationId = "chat", turnId = "turn")
        val leaked = original.copy(id = "leaked", conversationId = "group")
        val local = original.copy(id = "local", conversationId = "group", turnId = "group-turn")
        val kept = AgentTranscriptOwnership.filter(listOf(original, leaked, local),
            { if (it == "turn") "chat" else "group" }, { it })
        assertEquals(listOf(original, local), kept)
    }
}

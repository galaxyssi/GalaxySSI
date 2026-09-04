package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentConnectorStreamPresentationPolicyTest {
    @Test
    fun liveReplyRemainsVisibleUntilPersistedReplyReachesWindow() {
        val stream = entry("agent-stream-7", "Partial", 20L)
        val user = entry("user", "Question", 10L, AgentTranscriptRole.USER)

        val merged = AgentConnectorStreamPresentationPolicy.merge(listOf(user), listOf(stream))

        assertEquals(listOf("user", "agent-stream-7"), merged.map(AgentTranscriptEntry::id))
    }

    @Test
    fun persistedFinalAtomicallyReplacesMatchingLiveReply() {
        val stream = entry("agent-stream-7", "Partial", 20L)
        val final = stream.copy(id = "final-7", text = "Complete", timestampMillis = 30L)

        val merged = AgentConnectorStreamPresentationPolicy.merge(listOf(final), listOf(stream))

        assertEquals(listOf("final-7"), merged.map(AgentTranscriptEntry::id))
    }

    @Test
    fun onlyRepresentedPendingStreamsCanRetire() {
        val represented = entry("agent-stream-7", "Complete", 20L)
        val waiting = entry("agent-stream-8", "Still running", 30L).copy(
            dedupeKey = "assistant-final:turn:other"
        )
        val final = represented.copy(id = "final-7", timestampMillis = 40L)

        val retired = AgentConnectorStreamPresentationPolicy.representedSourceIds(
            pendingSourceIds = setOf(7L, 8L, 9L),
            liveBySourceId = mapOf(7L to represented, 8L to waiting),
            persisted = listOf(final),
            conversationId = "conversation"
        )

        assertTrue(7L in retired)
        assertTrue(9L in retired)
        assertFalse(8L in retired)
    }

    private fun entry(
        id: String,
        text: String,
        timestampMillis: Long,
        role: AgentTranscriptRole = AgentTranscriptRole.ASSISTANT
    ) = AgentTranscriptEntry(
        id = id,
        role = role,
        text = text,
        timestampMillis = timestampMillis,
        dedupeKey = if (role == AgentTranscriptRole.ASSISTANT) {
            "assistant-final:turn:turn"
        } else {
            ""
        },
        conversationId = "conversation",
        turnId = "turn",
        taskId = "task"
    )
}

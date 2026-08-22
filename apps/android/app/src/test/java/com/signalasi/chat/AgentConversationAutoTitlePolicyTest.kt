package com.signalasi.chat

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentConversationAutoTitlePolicyTest {
    @Test
    fun firstCompletedUserEntryTitlesNewConversationWithoutHistoryLookup() {
        assertTrue(
            AgentConversationAutoTitlePolicy.shouldTitle(
                conversation(title = "New session"),
                entry(dedupeKey = "", turnId = "turn-1")
            )
        )
    }

    @Test
    fun pendingVoiceEntryDoesNotConsumeAutomaticTitle() {
        assertFalse(
            AgentConversationAutoTitlePolicy.shouldTitle(
                conversation(title = "New session"),
                entry(
                    dedupeKey = AgentVoiceTranscriptPolicy.dedupeKey("recording.wav"),
                    turnId = ""
                )
            )
        )
    }

    @Test
    fun completedVoiceEntryTitlesConversationAfterRecognition() {
        assertTrue(
            AgentConversationAutoTitlePolicy.shouldTitle(
                conversation(title = "New session"),
                entry(
                    dedupeKey = AgentVoiceTranscriptPolicy.dedupeKey("recording.wav"),
                    turnId = "turn-voice"
                )
            )
        )
    }

    @Test
    fun existingTitleIsNeverOverwritten() {
        assertFalse(
            AgentConversationAutoTitlePolicy.shouldTitle(
                conversation(title = "Existing topic"),
                entry(dedupeKey = "", turnId = "turn-2")
            )
        )
    }

    private fun conversation(title: String) = AgentConversation(
        id = "conversation",
        title = title,
        createdAt = 1L,
        updatedAt = 1L
    )

    private fun entry(dedupeKey: String, turnId: String) = AgentTranscriptEntry(
        id = "entry",
        role = AgentTranscriptRole.USER,
        text = "User request",
        timestampMillis = 2L,
        dedupeKey = dedupeKey,
        conversationId = "conversation",
        turnId = turnId
    )
}

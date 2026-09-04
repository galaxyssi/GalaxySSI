package com.galaxyssi.chat

import org.junit.Assert.assertFalse
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentVoiceTranscriptPolicyTest {
    @Test
    fun voiceEntryIsPendingUntilItHasATurn() {
        val pending = entry(turnId = "")
        val completed = entry(turnId = "turn-1")

        assertTrue(AgentVoiceTranscriptPolicy.isVoiceTranscript(pending))
        assertTrue(AgentVoiceTranscriptPolicy.isPending(pending))
        assertTrue(AgentVoiceTranscriptPolicy.isVoiceTranscript(completed))
        assertFalse(AgentVoiceTranscriptPolicy.isPending(completed))
    }

    @Test
    fun ordinaryUserEntryIsNotAVoiceTranscript() {
        val ordinary = entry(turnId = "turn-1", dedupeKey = "")

        assertFalse(AgentVoiceTranscriptPolicy.isVoiceTranscript(ordinary))
        assertFalse(AgentVoiceTranscriptPolicy.isPending(ordinary))
    }

    @Test
    fun existingChineseDraftMergesWithTranscriptUsingComma() {
        assertEquals(
            "\u5e2e\u6211\u67e5\u5929\u6c14\uFF0C\u518d\u770b\u660e\u5929",
            AgentVoiceTranscriptPolicy.mergeDraftWithTranscript(
                "\u5e2e\u6211\u67e5\u5929\u6c14",
                "\u518d\u770b\u660e\u5929"
            )
        )
    }

    @Test
    fun existingEnglishDraftMergesWithTranscriptUsingCommaAndSpace() {
        assertEquals(
            "Check the weather, and tomorrow",
            AgentVoiceTranscriptPolicy.mergeDraftWithTranscript("Check the weather", "and tomorrow")
        )
    }

    @Test
    fun blankDraftDoesNotCreateAppendSnapshot() {
        assertNull(AgentVoiceTranscriptPolicy.draftSnapshot("conversation", "  "))
    }

    private fun entry(
        turnId: String,
        dedupeKey: String = AgentVoiceTranscriptPolicy.dedupeKey("recording.wav")
    ) = AgentTranscriptEntry(
        id = "entry",
        role = AgentTranscriptRole.USER,
        text = "Recognizing",
        timestampMillis = 1L,
        dedupeKey = dedupeKey,
        conversationId = "conversation",
        turnId = turnId
    )
}

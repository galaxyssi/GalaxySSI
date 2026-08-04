package com.signalasi.chat

import org.junit.Assert.assertFalse
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

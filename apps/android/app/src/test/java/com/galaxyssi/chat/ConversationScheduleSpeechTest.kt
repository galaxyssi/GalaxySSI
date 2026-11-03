package com.galaxyssi.chat

import com.galaxyssi.chat.voice.VoiceConversationSession
import org.junit.Assert.*
import org.junit.Test

class ConversationScheduleSpeechTest {
    @Test fun compactCardOverridesHiddenPlainConfirmation() {
        val entry = entry(listOf(card()))
        assertEquals("Open clock\nEvery minute", AgentReplySpeechPresentationPolicy.speakableText(entry))
        assertFalse(AgentReplySpeechPresentationPolicy.target(entry)!!.text.contains("Hidden"))
    }

    @Test fun legacyExplanationAndDiagnosticsAreNotRead() {
        val blocks = listOf(
            AgentRichBlock("explanation", AgentRichBlockType.TEXT, text = "Hidden explanation"),
            card().copy(text = "Every minute\nUnverified\nHidden execution diagnostic")
        )
        val visible = ConversationScheduleCardPresentation.visibleBlocks(blocks)
        assertEquals(listOf(blocks.last()), visible)
        assertEquals("Open clock\nEvery minute", AgentReplySpeechPresentationPolicy.speakableText(entry(blocks)))
    }

    @Test fun pausedCardKeepsItsVisiblePauseState() {
        assertEquals("Open clock\nEvery minute - Paused", AgentReplySpeechPresentationPolicy.speakableText(
            entry(listOf(card().copy(text = "Every minute - Paused")))))
    }

    @Test fun multipleCardsAreReadInDisplayOrder() {
        assertEquals("Open clock\nEvery minute\n\nCheck news\nEvery hour",
            AgentReplySpeechPresentationPolicy.speakableText(entry(listOf(
                card(), card().copy(id = "second", title = "Check news", text = "Every hour")))))
    }

    @Test fun ordinaryRepliesAndOtherActionCardsKeepExistingSpeech() {
        val other = card().copy(actions = listOf(AgentRichAction("open", "Open", "open_url", "https://example.com")))
        assertEquals("Visible reply", AgentReplySpeechPresentationPolicy.speakableText(
            entry(listOf(other)).copy(text = "Visible reply")))
        assertEquals(listOf(other), ConversationScheduleCardPresentation.visibleBlocks(listOf(other)))
        assertEquals("Plain reply", AgentReplySpeechPresentationPolicy.speakableText(entry(emptyList()).copy(text = "Plain reply")))
    }

    @Test fun continuousVoiceReadsTheSameCompactCardOnlyOnce() {
        val session = VoiceConversationSession().apply {
            begin("conversation")
            registerTrace("voice")
            registerTurn("voice", "turn")
        }
        val speech = AgentVoiceReplySpeech(session)
        val entry = entry(listOf(card()))
        val first = speech.observe(listOf(entry))
        assertTrue(first.beginSessionId.isNotBlank())
        val spoken = first.chunks.joinToString(" ") { it.speechText }
        assertTrue(spoken.contains("Open clock"))
        assertTrue(spoken.contains("Every minute"))
        assertFalse(spoken.contains("Hidden"))
        assertTrue(speech.observe(listOf(entry)).chunks.isEmpty())
    }

    private fun card() = AgentRichBlock("schedule:task", AgentRichBlockType.ACTIONS,
        title = "Open clock", text = "Every minute",
        actions = listOf(AgentRichAction("edit", "Edit", "edit_scheduled_task", "task")))

    private fun entry(blocks: List<AgentRichBlock>) = AgentTranscriptEntry(
        id = "reply", role = AgentTranscriptRole.ASSISTANT, text = "Hidden old confirmation",
        timestampMillis = 1L, conversationId = "conversation", turnId = "turn",
        richOutputJson = AgentRichContentCodec.encode(blocks))
}

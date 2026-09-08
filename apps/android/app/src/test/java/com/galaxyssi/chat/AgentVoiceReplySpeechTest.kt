package com.galaxyssi.chat

import com.galaxyssi.chat.voice.VoiceConversationSession
import org.junit.Assert.*
import org.junit.Test

class AgentVoiceReplySpeechTest {
    private val session = VoiceConversationSession().apply {
        begin("conversation")
        registerTrace("voice")
        registerTurn("voice", "turn")
    }
    private val speech = AgentVoiceReplySpeech(session)

    @Test fun startsWithTheFirstSentenceWithoutWaitingForTheFinalAnswer() {
        val first = speech.observe(listOf(entry("第一句已经生成。")))
        assertTrue(first.beginSessionId.isNotBlank())
        assertEquals(listOf("第一句已经生成。"), first.chunks.map { it.speechText })
        assertEquals("", first.finishSessionId)
        val second = speech.observe(listOf(entry("第一句已经生成。第二句随后到达。")))
        assertEquals(listOf("第二句随后到达。"), second.chunks.map { it.speechText })
        assertEquals("", second.beginSessionId)
        val final = speech.observe(listOf(entry("第一句已经生成。第二句随后到达。", complete = true)))
        assertEquals(first.beginSessionId, final.finishSessionId)
        speech.controller.disable(first.beginSessionId)
        repeat(20) { assertTrue(speech.observe(listOf(entry("第一句已经生成。第二句随后到达。", complete = true))).chunks.isEmpty()) }
    }

    @Test fun newerInputCancelsOldPlaybackEvenBeforeItHasATurn() {
        val started = speech.observe(listOf(entry("旧回答。")))
        session.registerTrace("new-input")
        val interrupted = speech.observe(listOf(entry("旧回答。还有新的文字。")))
        assertEquals(started.beginSessionId, interrupted.cancelSessionId)
        assertTrue(interrupted.chunks.isEmpty())
        session.registerTurn("new-input", "new-turn")
        val next = speech.observe(listOf(entry("新回答。", turn = "new-turn")))
        assertTrue(next.beginSessionId.isNotBlank())
        assertEquals(listOf("新回答。"), next.chunks.map { it.speechText })
    }

    @Test fun ignoresOtherConversationsUnrelatedTasksAndProcessMessages() {
        val command = speech.observe(listOf(
            entry("其他会话。", conversation = "elsewhere"),
            entry("其他任务。", turn = "elsewhere"),
            entry("正在使用工具。", role = AgentTranscriptRole.PROCESS)
        ))
        assertEquals("", command.beginSessionId)
        assertTrue(command.chunks.isEmpty())
    }

    @Test fun finalOnlyProvidersStillSpeakOnceAndCloseInput() {
        val final = entry("已经完成。", complete = true)
        val command = speech.observe(listOf(final))
        assertEquals(command.beginSessionId, command.finishSessionId)
        assertTrue(command.chunks.isNotEmpty())
        assertTrue(speech.observe(listOf(final)).chunks.isEmpty())
    }

    @Test fun uiWaitingIndicatorDoesNotConsumeTheActualReplyOrCompleteTheTurn() {
        val waiting = AgentReplyWaitingIndicatorPolicy.apply(emptyList(),
            listOf(PendingAgentReplyIndicator("conversation", "turn", 1L)), "conversation").entries.single()
        assertEquals(AgentTranscriptRole.ASSISTANT, waiting.role)
        assertNull(AgentReplySpeechPresentationPolicy.target(waiting, allowEmptyFinal = true))
        assertNull(AgentReplySpeechPresentationPolicy.latestTarget(listOf(waiting)))
        repeat(20) {
            val pending = speech.observe(listOf(waiting))
            assertTrue(pending.beginSessionId.isBlank())
            assertTrue(pending.chunks.isEmpty())
            assertFalse(pending.completedWithoutPlayback)
        }
        val actual = speech.observe(listOf(entry("2", complete = true)))
        assertTrue(actual.beginSessionId.startsWith("voice-call"))
        assertEquals(listOf("2"), actual.chunks.map { it.speechText })
        assertEquals(actual.beginSessionId, actual.finishSessionId)
    }

    @Test fun transientWaitingIndicatorCannotCloseAnActualStream() {
        val first = speech.observe(listOf(entry("第一句。")))
        val waiting = AgentReplyWaitingIndicatorPolicy.apply(emptyList(),
            listOf(PendingAgentReplyIndicator("conversation", "turn", 1L)), "conversation").entries.single()
        val pending = speech.observe(listOf(waiting))
        assertTrue(pending.cancelSessionId.isBlank())
        assertTrue(pending.finishSessionId.isBlank())
        assertTrue(speech.controller.isPlaying())
        val final = speech.observe(listOf(entry("第一句。第二句。", complete = true)))
        assertEquals(first.beginSessionId, final.finishSessionId)
        assertEquals(listOf("第二句。"), final.chunks.map { it.speechText })
    }

    @Test fun muteStopsSpeechWithoutResurrectingItOnTheNextRender() {
        val first = speech.observe(listOf(entry("第一句。")))
        session.mute(true)
        assertEquals(first.beginSessionId, speech.observe(listOf(entry("第一句。第二句。"))).cancelSessionId)
        session.mute(false)
        assertTrue(speech.observe(listOf(entry("第一句。第二句。", complete = true))).chunks.isEmpty())
    }

    @Test fun emptyTransientSnapshotDoesNotInterruptAnActiveAnswer() {
        speech.observe(listOf(entry("回答继续生成。")))
        assertEquals("", speech.observe(emptyList()).cancelSessionId)
        assertTrue(speech.controller.isPlaying())
    }

    @Test fun hangupRejectsPendingChunksAndOldCallFinals() {
        val first = speech.observe(listOf(entry("回答的一部分。")))
        session.end()
        assertEquals(first.beginSessionId, speech.observe(listOf(entry("回答的一部分。结束。", complete = true))).cancelSessionId)
        session.begin("conversation")
        assertTrue(speech.observe(listOf(entry("旧调用的最终结果。", complete = true))).chunks.isEmpty())
        assertTrue(speech.controller.commitDue(first.beginSessionId).chunks.isEmpty())
    }

    @Test fun manualAndAutomaticSpeechUseDifferentPlaybackIdentities() {
        val response = entry("同一个回答。")
        val automatic = speech.observe(listOf(response))
        val manual = AgentReplySpeechController().toggle(AgentReplySpeechPresentationPolicy.target(response)!!)
        assertNotEquals(automatic.beginSessionId, manual.beginSessionId)
        assertTrue(speech.controller.disable(manual.beginSessionId).isEmpty())
        assertTrue(speech.controller.isPlaying())
    }

    @Test fun visualOnlyFinalCompletesOnceWithoutInventingNarration() {
        val final = visualFinal()
        val command = speech.observe(listOf(final))
        assertTrue(command.completedWithoutPlayback)
        assertTrue(command.chunks.isEmpty())
        assertEquals("", command.beginSessionId)
        assertNull(AgentReplySpeechPresentationPolicy.target(final))
        repeat(20) { assertFalse(speech.observe(listOf(final)).completedWithoutPlayback) }
    }

    @Test fun visualFinalClosesEarlierStreamAndFlushesItsUnspokenTail() {
        val first = speech.observe(listOf(entry("图片已经生成。还有一句补充")))
        val command = speech.observe(listOf(entry("图片已经生成。还有一句补充"), visualFinal()))
        assertEquals(first.beginSessionId, command.finishSessionId)
        assertFalse(command.completedWithoutPlayback)
        assertEquals(listOf("还有一句补充"), command.chunks.map { it.speechText })
        assertEquals("", speech.observe(listOf(visualFinal())).finishSessionId)
    }

    @Test fun anEmptyIntermediateEntryIsNotASilentCompletion() {
        assertFalse(speech.observe(listOf(entry("", complete = true))).completedWithoutPlayback)
        assertFalse(speech.observe(listOf(visualFinal().copy(id = "agent-stream-turn"))).completedWithoutPlayback)
    }

    @Test fun unrelatedOrMutedVisualFinalCannotResumeListening() {
        assertFalse(speech.observe(listOf(visualFinal().copy(turnId = "other"))).completedWithoutPlayback)
        session.mute(true)
        assertFalse(speech.observe(listOf(visualFinal())).completedWithoutPlayback)
        session.end()
        assertFalse(speech.observe(listOf(visualFinal())).completedWithoutPlayback)
    }

    private fun visualFinal() = entry("", complete = true).copy(
        dedupeKey = AgentFinalResponseIdentity.dedupeKey("turn"),
        richOutputJson = AgentRichContentCodec.encode(listOf(AgentRichBlock(
            id = "image", type = AgentRichBlockType.IMAGE, uri = "content://test/image", mimeType = "image/png"
        )))
    )

    private fun entry(
        text: String,
        complete: Boolean = false,
        conversation: String = "conversation",
        turn: String = "turn",
        role: AgentTranscriptRole = AgentTranscriptRole.ASSISTANT
    ) = AgentTranscriptEntry(
        id = if (complete) "final-$turn" else "agent-stream-$turn",
        role = role,
        text = text,
        timestampMillis = 1L,
        conversationId = conversation,
        turnId = turn
    )
}

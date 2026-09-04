package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentReplySpeechControllerTest {
    @Test
    fun replyStartsMutedAndEnablingReadsTheAvailableFirstSegment() {
        val controller = AgentReplySpeechController()
        val target = target("turn-1", "stream-1", "第一段已经完成。", complete = false)

        assertTrue(controller.observe(target).chunks.isEmpty())
        assertFalse(controller.isEnabled(target))

        val command = controller.toggle(target)

        assertTrue(command.beginSessionId.isNotBlank())
        assertEquals(listOf("第一段已经完成。"), command.chunks.map { it.speechText })
        assertTrue(command.scheduleCommitSessionId.isNotBlank())
        assertTrue(controller.isEnabled(target))
    }

    @Test
    fun enabledReplyReadsOnlyNewSegmentsAndClosesOnTheFinalEntry() {
        val controller = AgentReplySpeechController()
        val first = target("turn-1", "stream-1", "第一段。", complete = false)
        controller.observe(first)
        controller.toggle(first)

        val second = first.copy(text = "第一段。第二段也完成。")
        val update = controller.observe(second)
        assertEquals(listOf("第二段也完成。"), update.chunks.map { it.speechText })

        val duplicate = controller.observe(second)
        assertTrue(duplicate.chunks.isEmpty())

        val final = second.copy(entryId = "final-1", complete = true)
        val completion = controller.observe(final)
        assertTrue(completion.finishSessionId.isNotBlank())
        assertEquals(setOf("stream-1", "final-1"), completion.changedEntryIds)
    }

    @Test
    fun aNewReplyCancelsPlaybackAndReturnsToMuted() {
        val controller = AgentReplySpeechController()
        val first = target("turn-1", "stream-1", "第一条回复。", complete = false)
        controller.observe(first)
        val started = controller.toggle(first)

        val second = target("turn-2", "stream-2", "新的回复。", complete = false)
        val changed = controller.observe(second)

        assertEquals(started.beginSessionId, changed.cancelSessionId)
        assertFalse(controller.isEnabled(second))
        assertEquals(setOf("stream-1", "stream-2"), changed.changedEntryIds)
    }

    @Test
    fun doubleTappedParagraphReadsThatParagraphAndEverythingAfterIt() {
        val controller = AgentReplySpeechController()
        val target = target(
            "turn-1",
            "final-1",
            "第一段不会重复。\n\n第二段从这里朗读。\n\n第三段也要朗读。",
            complete = true
        )
        controller.observe(target)

        val command = controller.readFromParagraph(
            target = target,
            paragraph = "第二段从这里朗读。",
            startOffset = target.text.indexOf("第二段从这里朗读。")
        )

        assertTrue(command.beginSessionId.isNotBlank())
        assertTrue(command.finishSessionId.isNotBlank())
        assertEquals(
            listOf("第二段从这里朗读。", "第三段也要朗读。"),
            command.chunks.map { it.speechText }
        )
        assertTrue(controller.isEnabled(target))
    }

    @Test
    fun paragraphOffsetDisambiguatesRepeatedParagraphText() {
        val controller = AgentReplySpeechController()
        val text = "重复段。\n\n中间段。\n\n重复段。\n\n结尾段。"
        val target = target("turn-1", "final-1", text, complete = true)
        controller.observe(target)
        val secondOccurrence = text.lastIndexOf("重复段。")

        val command = controller.readFromParagraph(
            target = target,
            paragraph = "重复段。",
            sourceText = text,
            startOffset = secondOccurrence
        )

        assertEquals(
            listOf("重复段。", "结尾段。"),
            command.chunks.map { it.speechText }
        )
    }

    @Test
    fun stoppingPlaybackCancelsTheActiveSessionAndReturnsToIdle() {
        val controller = AgentReplySpeechController()
        val target = target("turn-1", "final-1", "第一段。第二段。", complete = true)
        controller.observe(target)
        val started = controller.toggle(target)

        val stopped = controller.stop()

        assertEquals(started.beginSessionId, stopped.cancelSessionId)
        assertEquals(setOf(target.entryId), stopped.changedEntryIds)
        assertFalse(controller.isPlaying())
        assertFalse(controller.isEnabled(target))
    }

    @Test
    fun playbackCompletionReturnsTheReplyToItsIdleState() {
        val controller = AgentReplySpeechController()
        val target = target("turn-1", "final-1", "朗读完成后复位。", complete = true)
        controller.observe(target)
        val command = controller.readFromParagraph(target, target.text)

        val changed = controller.disable(command.beginSessionId)

        assertEquals(setOf(target.entryId), changed)
        assertFalse(controller.isEnabled(target))
    }

    @Test
    fun restartedPlaybackIgnoresThePreviousAttemptsCancellationCallback() {
        val controller = AgentReplySpeechController()
        val target = target("turn-1", "final-1", "选择其中一段。", complete = true)
        controller.observe(target)
        val first = controller.readFromParagraph(target, target.text)

        val second = controller.readFromParagraph(target, "重新朗读这一段。")

        assertEquals(first.beginSessionId, second.cancelSessionId)
        assertTrue(second.beginSessionId.isNotBlank())
        assertTrue(second.beginSessionId != first.beginSessionId)
        assertTrue(controller.disable(first.beginSessionId).isEmpty())
        assertTrue(controller.isEnabled(target))
        assertEquals(setOf(target.entryId), controller.disable(second.beginSessionId))
        assertFalse(controller.isEnabled(target))
    }

    @Test
    fun presentationChoosesTheLatestSpeakableAssistantReply() {
        val entries = listOf(
            entry("assistant-1", "turn-1", "较早回复"),
            entry("user-2", "turn-2", "新问题", AgentTranscriptRole.USER),
            entry("assistant-2", "turn-2", "最新回复")
        )

        val target = AgentReplySpeechPresentationPolicy.latestTarget(entries)

        assertEquals("assistant-2", target?.entryId)
        assertEquals("turn-2", target?.responseId)
    }

    private fun target(
        responseId: String,
        entryId: String,
        text: String,
        complete: Boolean
    ) = AgentReplySpeechTarget(responseId, entryId, text, complete)

    private fun entry(
        id: String,
        turnId: String,
        text: String,
        role: AgentTranscriptRole = AgentTranscriptRole.ASSISTANT
    ) = AgentTranscriptEntry(
        id = id,
        role = role,
        text = text,
        timestampMillis = 1L,
        conversationId = "conversation",
        turnId = turnId
    )
}

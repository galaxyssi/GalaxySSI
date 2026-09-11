package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class AgentProcessClockPolicyTest {
    private val process = AgentTranscriptEntry("p", AgentTranscriptRole.PROCESS, "Working", 1000,
        conversationId = "c", turnId = "turn", taskId = "task")
    private val final = process.copy(id = "final", role = AgentTranscriptRole.ASSISTANT, text = "Done", timestampMillis = 3000)

    @Test fun completionFreezesEvenWhenAProjectionTemporarilyLosesTheEvent() {
        val clock = AgentProcessClock(1000)
        assertEquals(1000L, clock.elapsed(2000))
        clock.observe(3000)
        clock.observe(null)
        clock.observe(9000)
        assertEquals(2000L, clock.elapsed(10000))
    }

    @Test fun streamsAndCitationPreviewsAreNotFinalReplies() {
        for (id in listOf("agent-stream-1", "agent-stream-preview-1")) {
            assertNull(AgentProcessClockPolicy.finalReplyTimestamp(process, listOf(final.copy(id = id))))
        }
        assertEquals(3000L, AgentProcessClockPolicy.finalReplyTimestamp(process, listOf(final)))
    }

    @Test fun otherConversationsTurnsAndUnidentifiedRowsCannotStopAClock() {
        assertNull(AgentProcessClockPolicy.finalReplyTimestamp(process, listOf(final.copy(conversationId = "other"))))
        assertNull(AgentProcessClockPolicy.finalReplyTimestamp(process, listOf(final.copy(turnId = "other"))))
        assertNull(AgentProcessClockPolicy.finalReplyTimestamp(process.copy(turnId = "", taskId = ""), listOf(final)))
    }

    @Test fun identicalFinalContentInvalidatesOnlyItsProcessGroup() {
        val other = process.copy(id = "other", turnId = "other")
        val stream = final.copy(id = "agent-stream-1", dedupeKey = "same")
        val before = AgentTranscriptRenderPolicy.processGroupSignatures(listOf(process, other, stream))
        val after = AgentTranscriptRenderPolicy.processGroupSignatures(listOf(process, other, stream.copy(id = "persisted")))
        assertNotEquals(before[AgentTranscriptPresentationPolicy.processGroupKey(process)], after[AgentTranscriptPresentationPolicy.processGroupKey(process)])
        assertEquals(before[AgentTranscriptPresentationPolicy.processGroupKey(other)], after[AgentTranscriptPresentationPolicy.processGroupKey(other)])
        assertTrue(AgentTranscriptRenderPolicy.sameContent(stream, stream.copy(id = "persisted")))
    }

    @Test fun tenClocksAndTurnsRemainIndependent() {
        val clocks = (0 until 10).map { AgentProcessClock(1000) }
        val entries = (0 until 10).map { final.copy(turnId = "turn-$it", timestampMillis = 2000L + it) }
        repeat(10) { index -> clocks[index].observe(AgentProcessClockPolicy.finalReplyTimestamp(
            process.copy(turnId = "turn-$index"), entries
        )) }
        assertEquals((0 until 10).map { 1000L + it }, clocks.map { it.elapsed(99999) })
    }

    @Test fun replaceablePreviewCannotBecomeSpeech() {
        assertNull(AgentReplySpeechPresentationPolicy.target(final.copy(id = "agent-stream-preview-1")))
        assertNotNull(AgentReplySpeechPresentationPolicy.target(final))
    }
}

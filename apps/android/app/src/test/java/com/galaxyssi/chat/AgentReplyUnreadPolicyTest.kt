package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class AgentReplyUnreadPolicyTest {
    private fun reply(id: String = "reply", key: String = "final:turn") = AgentTranscriptEntry(
        id, AgentTranscriptRole.ASSISTANT, "Answer", 1L, key, "conversation", "turn")

    @Test fun finalReplyIsUnreadButProgressAndUserInputAreNot() {
        assertTrue(AgentReplyUnreadPolicy.isNewReply(reply(), null))
        assertNull(AgentReplyUnreadPolicy.token(reply().copy(role = AgentTranscriptRole.PROCESS)))
        assertNull(AgentReplyUnreadPolicy.token(reply().copy(role = AgentTranscriptRole.USER)))
    }

    @Test fun streamingReplyDoesNotNotifyUntilFinal() {
        val stream = reply(id = "agent-stream-turn")
        assertNull(AgentReplyUnreadPolicy.token(stream))
        assertTrue(AgentReplyUnreadPolicy.isNewReply(reply(), stream))
    }

    @Test fun CitationAndAttachmentUpdatesDoNotNotifyAgain() {
        assertFalse(AgentReplyUnreadPolicy.isNewReply(reply(id = "updated"), reply()))
    }

    @Test fun readingOldReplyDoesNotClearNewReply() {
        assertEquals(setOf("new"), AgentReplyUnreadPolicy.remaining(
            setOf("old", "new"), listOf(reply(key = "old"))))
    }

    @Test fun readingOnlyProgressDoesNotClearReply() {
        assertEquals(setOf("final:turn"), AgentReplyUnreadPolicy.remaining(
            setOf("final:turn"), listOf(reply().copy(role = AgentTranscriptRole.PROCESS))))
    }
}

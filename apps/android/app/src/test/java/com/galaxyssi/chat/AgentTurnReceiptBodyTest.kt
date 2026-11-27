package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class AgentTurnReceiptBodyTest {
    @Test fun onlyReplyTextStartsFirstVisibleTiming() {
        val body = AgentTranscriptEntry("agent-stream-1", AgentTranscriptRole.ASSISTANT, "First sentence", 1)
        assertTrue(AgentTurnReceipt.isReplyText(body))
        assertFalse(AgentTurnReceipt.isReplyText(body.copy(text = "...", dedupeKey = "ui-reply-waiting:turn")))
        assertFalse(AgentTurnReceipt.isReplyText(body.copy(id = "agent-stream-preview-1")))
        assertFalse(AgentTurnReceipt.isReplyText(body.copy(role = AgentTranscriptRole.PROCESS)))
        assertFalse(AgentTurnReceipt.isReplyText(body.copy(dedupeKey = "delivery-failed:1")))
        assertFalse(AgentTurnReceipt.isReplyText(body.copy(text = " ")))
    }
}

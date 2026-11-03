package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class ProactiveAttentionPairedTitlesTest {
    private val request = AttentionTitleRequest("batch-a", 123L, "paired-desktop", "titles:a", 10_000L,
        mapOf("one" to "New model released", "two" to "Chip version 2 ships"))

    @Test fun durableBatchRetainsExactTitlesIdentityAndLease() {
        assertEquals(request, AttentionTitleRequest.parse(request.json()))
        assertEquals(request.copy(completed = true), AttentionTitleRequest.parse(request.copy(completed = true).json()))
    }

    @Test fun responseMustMatchContactSourceConversationAndTurn() {
        val response = AgentConnectorResponse(123L, "paired-desktop", "{}",
            conversationId = request.conversation, turnId = request.id)
        assertTrue(request.matches(response))
        assertFalse(request.matches(response.copy(sourceMessageId = 124L)))
        assertFalse(request.matches(response.copy(contactId = "another-desktop")))
        assertFalse(request.matches(response.copy(conversationId = "")))
        assertFalse(request.matches(response.copy(turnId = "old-batch")))
    }

    @Test fun titleBatchCannotConsumeNormalResearchReplies() {
        assertFalse(request.matches(AgentConnectorResponse(123L, "paired-desktop", "{}",
            conversationId = "public-attention:research", turnId = request.id)))
        assertTrue(request.conversation.startsWith("public-attention:"))
        assertTrue(request.conversation.startsWith(AttentionTitleRequest.PREFIX))
    }

    @Test fun malformedBatchDoesNotRecoverAsAnActiveRequest() {
        assertNull(AttentionTitleRequest.parse("{}"))
        assertNull(AttentionTitleRequest.parse("broken"))
    }
}

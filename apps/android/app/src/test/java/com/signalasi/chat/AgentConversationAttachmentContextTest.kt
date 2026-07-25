package com.signalasi.chat

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentConversationAttachmentContextTest {
    @Test
    fun transportContextKeepsAttachmentReferenceWithoutEmbeddingPrivateUriOrBytes() {
        val richOutput = AgentRichContentCodec.encode(
            listOf(
                AgentRichBlock(
                    id = "image-1",
                    type = AgentRichBlockType.IMAGE,
                    title = "homework.jpg",
                    uri = "content://signalasi/private/homework.jpg",
                    dataB64 = "private-image-bytes",
                    mimeType = "image/jpeg",
                    metadata = mapOf("size_bytes" to "245760")
                )
            )
        )
        val context = AgentConversationContext(
            conversationId = "conversation-1",
            summary = "",
            turns = listOf(
                AgentTranscriptEntry(
                    id = "entry-1",
                    role = AgentTranscriptRole.USER,
                    text = "Please review this",
                    timestampMillis = 1L,
                    conversationId = "conversation-1",
                    turnId = "turn-1",
                    taskId = "turn-1",
                    richOutputJson = richOutput
                )
            ),
            privateMode = false
        )

        val transport = context.asTransportBlock()

        assertTrue(transport.contains("\"name\":\"homework.jpg\""))
        assertTrue(transport.contains("\"mime_type\":\"image/jpeg\""))
        assertTrue(transport.contains("\"size_bytes\":245760"))
        assertTrue(transport.contains("\"attachment_index\""))
        assertTrue(transport.contains("\"turn_id\":\"turn-1\""))
        assertTrue(transport.contains("Attachments: homework.jpg (image/jpeg)"))
        assertFalse(transport.contains("content://signalasi/private"))
        assertFalse(transport.contains("private-image-bytes"))
        assertFalse(transport.contains("data_b64"))
    }
}

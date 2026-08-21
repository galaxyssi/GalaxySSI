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

    @Test
    fun compactTransportHonorsSmallAgentLoopBudgetWithoutLosingLatestTurn() {
        val richOutput = AgentRichContentCodec.encode(
            (1..5).map { index ->
                AgentRichBlock(
                    id = "file-$index",
                    type = AgentRichBlockType.FILE,
                    title = "artifact-$index.txt",
                    uri = "content://signalasi/private/artifact-$index.txt",
                    dataB64 = "private-bytes-$index",
                    mimeType = "text/plain",
                    metadata = mapOf("size_bytes" to (index * 100).toString())
                )
            }
        )
        val turns = (1..6).map { index ->
            AgentTranscriptEntry(
                id = "entry-$index",
                role = if (index % 2 == 0) AgentTranscriptRole.ASSISTANT else AgentTranscriptRole.USER,
                text = "turn-$index " + "context ".repeat(300),
                timestampMillis = index.toLong(),
                conversationId = "compact-context",
                turnId = "turn-$index",
                richOutputJson = if (index == 6) richOutput else ""
            )
        }
        val context = AgentConversationContext(
            conversationId = "compact-context",
            summary = "older summary ".repeat(400),
            turns = turns,
            privateMode = false
        )

        val transport = context.asTransportBlock(maximumTokens = 350)

        val estimatedTokens = ConversationContextCompactor.estimateTokens(transport)
        assertTrue("compact transport used $estimatedTokens tokens", estimatedTokens <= 350)
        assertFalse(transport.contains("turn-4"))
        assertTrue(transport.contains("turn-5"))
        assertTrue(transport.contains("turn-6"))
        assertTrue(transport.contains("artifact-1.txt"))
        assertTrue(transport.contains("artifact-3.txt"))
        assertFalse(transport.contains("artifact-4.txt"))
        assertFalse(transport.contains("attachment_index"))
        assertFalse(transport.contains("content://signalasi/private"))
        assertFalse(transport.contains("private-bytes"))
    }
}

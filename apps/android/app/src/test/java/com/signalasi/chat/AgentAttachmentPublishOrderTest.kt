package com.signalasi.chat

import org.junit.Assert.assertEquals
import org.junit.Test
import java.io.File

class AgentAttachmentPublishOrderTest {
    @Test
    fun manifestAndChunksPrecedeBlockedTaskEncryption() {
        val dataFile = File.createTempFile("signalasi-attachment-order", ".bin").apply {
            writeBytes(byteArrayOf(1))
            deleteOnExit()
        }
        val attachment = AgentPreparedOutboundAttachment(
            transferId = "a".repeat(64),
            attachmentId = "attachment",
            ordinal = 0,
            name = "image.jpg",
            originalName = "image.jpg",
            mimeType = "image/jpeg",
            sizeBytes = 1,
            originalSizeBytes = 1,
            sha256 = "c".repeat(64),
            chunkCount = 1,
            transportProfile = "standard",
            requiresValidatedNetwork = false,
            scope = AgentAttachmentTransferScope(
                contactId = "codex",
                desktopId = "desktop-test",
                clientRouteId = "b".repeat(22),
                conversationId = "conversation",
                taskId = "task",
                turnId = "turn",
                clientMessageId = 7L
            ),
            dataFile = dataFile
        )

        val types = AgentAttachmentPublishOrder.steps(listOf(attachment)).map { it.type }

        assertEquals(
            listOf("input_attachment_manifest", "input_attachment_chunk"),
            types
        )
    }
}

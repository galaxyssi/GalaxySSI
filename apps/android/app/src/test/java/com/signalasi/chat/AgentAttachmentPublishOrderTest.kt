package com.signalasi.chat

import org.junit.Assert.assertEquals
import org.junit.Test
import java.io.File

class AgentAttachmentPublishOrderTest {
    @Test
    fun manifestAndChunksPrecedeBlockedTaskEncryption() {
        val chunkDirectory = kotlin.io.path.createTempDirectory("signalasi-attachment-order").toFile()
            .apply { deleteOnExit() }
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
            chunkDirectory = chunkDirectory
        )

        val types = AgentAttachmentPublishOrder.steps(listOf(attachment)).map { it.type }

        assertEquals(
            listOf("input_attachment_manifest", "input_attachment_chunk"),
            types
        )
        assertEquals(
            listOf("input_attachment_manifest", "input_attachment_chunk"),
            AgentAttachmentPublishOrder.initialSteps(listOf(attachment)).map { it.type }
        )

        val large = attachment.copy(
            sizeBytes = 2L * 1024L * 1024L,
            originalSizeBytes = 2L * 1024L * 1024L,
            chunkCount = 8
        )
        assertEquals(
            listOf("input_attachment_manifest"),
            AgentAttachmentPublishOrder.initialSteps(listOf(large)).map { it.type }
        )
    }
}

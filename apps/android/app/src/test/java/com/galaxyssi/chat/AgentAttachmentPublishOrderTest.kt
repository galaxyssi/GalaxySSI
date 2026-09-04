package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Test
import java.io.File

class AgentAttachmentPublishOrderTest {
    @Test
    fun manifestAndChunksPrecedeBlockedTaskEncryption() {
        val chunkDirectory = kotlin.io.path.createTempDirectory("galaxyssi-attachment-order").toFile()
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
            chunkSizeBytes = AgentOutboundAttachmentTransferStore.CHUNK_BYTES,
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
        assertEquals(
            listOf("input_attachment_manifest"),
            AgentAttachmentPublishOrder.initialSteps(
                listOf(attachment),
                allowEagerChunks = false
            ).map { it.type }
        )

        val file = attachment.copy(
            transferId = "d".repeat(64),
            attachmentId = "file",
            name = "archive.zip",
            originalName = "archive.zip",
            mimeType = "application/zip"
        )
        val peerPlan = AgentAttachmentPublishOrder.peerMessagePlan(
            listOf(attachment, file),
            eagerAttachment = { candidate ->
                PeerAttachmentTransferProgress.shouldAutoReceive(candidate.mimeType)
            }
        )
        assertEquals(
            listOf(
                "input_attachment_manifest",
                "input_attachment_chunk",
                "input_attachment_manifest"
            ),
            peerPlan.transferSteps.map { it.type }
        )
        assertEquals(true, peerPlan.transferSteps[0].eagerChunks)
        assertEquals(false, peerPlan.transferSteps[2].eagerChunks)
        assertEquals(
            listOf(attachment.transferId, file.transferId),
            peerPlan.blockedTransferIds
        )

        val largePeerPlan = AgentAttachmentPublishOrder.peerMessagePlan(
            listOf(large),
            eagerAttachment = { true }
        )
        assertEquals(
            listOf("input_attachment_manifest"),
            largePeerPlan.transferSteps.map { it.type }
        )
        assertEquals(listOf(large.transferId), largePeerPlan.blockedTransferIds)
    }
}

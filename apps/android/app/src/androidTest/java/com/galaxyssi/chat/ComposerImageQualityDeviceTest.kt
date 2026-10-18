package com.galaxyssi.chat

import android.graphics.Bitmap
import android.net.Uri
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.security.MessageDigest
import java.util.UUID

@RunWith(AndroidJUnit4::class)
class ComposerImageQualityDeviceTest {
    private val context = InstrumentationRegistry.getInstrumentation().targetContext
    private val normal = AgentMediaDeliveryProfile(AgentMediaNetworkState.NORMAL, "normal",
        100_000, 44_100, 96_000, false)

    @Test fun compressedAndOriginalSelectionsReachCloudWithoutChangingTheSource() = withImage { item, file ->
        val original = file.readBytes()
        val compressed = CloudImagePayloadFactory.prepare(context, listOf(item)).single()
        assertTrue(compressed.bytes.size <= 100_000)
        assertFalse(compressed.original)
        val full = CloudImagePayloadFactory.prepare(context, listOf(item.copy(sendOriginal = true))).single()
        assertTrue(full.original)
        assertArrayEquals(original, full.bytes)
        assertArrayEquals(original, file.readBytes())
        compressed.bytes.fill(0); full.bytes.fill(0); original.fill(0)
    }

    @Test fun originalDoesNotSilentlyCompressWhenInlinePacketIsTooSmall() = withImage { item, _ ->
        val encoded = GalaxySSIMqttAttachmentEncoder.encodeInline(context,
            listOf(item.copy(sendOriginal = true)), normal, 100_000).getJSONObject(0)
        assertEquals("metadata_only", encoded.getString("inline_status"))
        assertFalse(encoded.has("data_b64"))
        assertTrue(encoded.getBoolean("send_original"))
    }

    @Test fun genericFilePickerMimeStillRecognizesAnImageAndPreservesOriginalBytes() = withImage { item, file ->
        val expected = sha(file)
        val retained = ComposerAttachmentImport.retain(context, item.copy(mimeType = "application/octet-stream"))
        assertTrue(retained.isImage)
        assertEquals("image/jpeg", retained.mimeType)
        assertEquals(expected, sha(file))
        assertFalse(retained.sendOriginal)
    }

    @Test fun contactAndDesktopTransferRespectEachImagesQualityAndKeepFilesUnchanged() = withImage { item, file ->
        val document = File(file.parentFile, "${UUID.randomUUID()}.pdf").apply { writeText("%PDF-1.4\nfixture") }
        var transfers = emptyList<AgentPreparedOutboundAttachment>()
        try {
            val sourceHash = sha(file)
            transfers = AgentOutboundAttachmentTransferStore.prepare(context,
                scope("peer-quality"), listOf(item, item.copy(id = "original", sendOriginal = true),
                    AgentInputAttachment("document", Uri.fromFile(document), document.name, "application/pdf", document.length())),
                normal.copy(imageTargetBytes = AgentImagePipeline.CONTACT_TRANSPORT_BYTES))
            assertEquals(3, transfers.size)
            assertTrue(transfers[0].sizeBytes <= AgentImagePipeline.CONTACT_TRANSPORT_BYTES)
            assertTrue(transfers[0].sizeBytes < file.length())
            assertEquals(file.length(), transfers[1].sizeBytes)
            assertEquals(sourceHash, transfers[1].sha256)
            assertEquals(sha(document), transfers[2].sha256)
            assertEquals(sourceHash, sha(file))
        } finally {
            AgentOutboundAttachmentTransferStore.discard(context, transfers.map { it.transferId })
            document.delete()
        }
    }

    @Test fun draftAndWorkspaceRecoveryPreserveOriginalSelection() = withImage { item, _ ->
        val attachment = item.copy(sendOriginal = true)
        val id = "quality-${UUID.randomUUID()}"
        val turn = UUID.randomUUID().toString()
        val windows = AgentWindowStateStore(context)
        try {
            windows.save(id, id, AgentWindowDraft(attachments = listOf(attachment)))
            assertTrue(windows.load(id, id).attachments.single().sendOriginal)
            AgentAttachmentWorkspaceStager.stage(context, id, turn, listOf(attachment))
            assertTrue(AgentAttachmentWorkspaceStager.restore(context, id, turn, listOf(attachment.richBlock())).single().sendOriginal)
            assertTrue(AgentAttachmentWorkspaceStager.restoreByIds(context, id, listOf(attachment.id)).single().sendOriginal)
        } finally {
            AgentEncryptedDatabase(context, "agent_window_state_v1").remove("draft:$id:$id")
            File(context.filesDir, "agent-native-workspaces/${AgentWorkspaceScope.id(id)}").deleteRecursively()
        }
    }

    private fun scope(id: String) = AgentAttachmentTransferScope(
        contactId = "galaxyssi:quality-test", desktopId = "galaxyssi:quality-test", clientRouteId = "b".repeat(22),
        conversationId = id, taskId = id, turnId = id, clientMessageId = 1L)

    private fun sha(file: File) = MessageDigest.getInstance("SHA-256").digest(file.readBytes())
        .joinToString("") { "%02x".format(it) }

    private fun withImage(test: (AgentInputAttachment, File) -> Unit) {
        val file = File(context.filesDir, "composer-attachments-v1/quality-${UUID.randomUUID()}.jpg")
        file.parentFile!!.mkdirs()
        val pixels = IntArray(1200 * 1000)
        var seed = 17
        for (index in pixels.indices) { seed = seed * 1103515245 + 12345; pixels[index] = 0xff000000.toInt() or (seed and 0xffffff) }
        val bitmap = Bitmap.createBitmap(pixels, 1200, 1000, Bitmap.Config.ARGB_8888)
        file.outputStream().use { bitmap.compress(Bitmap.CompressFormat.JPEG, 98, it) }
        bitmap.recycle(); pixels.fill(0)
        assertTrue(file.length() > AgentImagePipeline.CONTACT_TRANSPORT_BYTES)
        try { test(AgentInputAttachment("quality-photo", LocalAttachmentUris.forFile(context, file, file.name, "image/jpeg"),
            file.name, "image/jpeg", file.length()), file) } finally { file.delete() }
    }
}

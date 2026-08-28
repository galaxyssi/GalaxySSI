package com.signalasi.chat

import android.net.Uri
import android.util.Base64
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test
import org.junit.runner.RunWith
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.UUID

@RunWith(AndroidJUnit4::class)
class PeerOriginalAttachmentInstrumentedTest {
    private val context = InstrumentationRegistry.getInstrumentation().targetContext

    @Test
    fun peerImageTransferPreservesEveryOriginalByte() {
        val bytes = ByteArray(2 * 1024 * 1024 + 17) { index -> (index * 31).toByte() }
        val source = File(context.cacheDir, "peer-original-${UUID.randomUUID()}.jpg")
        source.writeBytes(bytes)
        var transferIds = emptyList<String>()
        try {
            val prepared = AgentOutboundAttachmentTransferStore.prepare(
                context = context,
                scope = AgentAttachmentTransferScope(
                    contactId = "signalasi:peer-test",
                    desktopId = "signalasi:peer-test",
                    clientRouteId = "b".repeat(22),
                    conversationId = "peer-original-test",
                    taskId = "peer-original-task",
                    turnId = "peer-original-turn",
                    clientMessageId = 1L
                ),
                attachments = listOf(
                    AgentInputAttachment(
                        id = UUID.randomUUID().toString(),
                        uri = Uri.fromFile(source),
                        displayName = source.name,
                        mimeType = "image/jpeg",
                        sizeBytes = bytes.size.toLong()
                    )
                ),
                mediaProfile = AgentMediaDeliveryProfile(
                    state = AgentMediaNetworkState.NORMAL,
                    id = "normal",
                    imageTargetBytes = 100_000,
                    audioSampleRateHz = 44_100,
                    audioBitRateBps = 96_000,
                    deferMediaUpload = false
                ),
                preserveOriginalBytes = true
            ).single()
            transferIds = listOf(prepared.transferId)

            assertEquals(bytes.size.toLong(), prepared.sizeBytes)
            assertEquals(bytes.size.toLong(), prepared.originalSizeBytes)
            assertEquals("image/jpeg", prepared.mimeType)
            assertEquals("peer-original", prepared.transportProfile)
            assertFalse(prepared.requiresValidatedNetwork)

            val restored = ByteArrayOutputStream(bytes.size)
            repeat(prepared.chunkCount) { index ->
                val chunk = Base64.decode(
                    prepared.chunkPayload(index).getString("data_b64"),
                    Base64.DEFAULT
                )
                try {
                    restored.write(chunk)
                } finally {
                    chunk.fill(0)
                }
            }
            assertArrayEquals(bytes, restored.toByteArray())
        } finally {
            AgentOutboundAttachmentTransferStore.discard(context, transferIds)
            source.delete()
            bytes.fill(0)
        }
    }
}

package com.signalasi.chat

import android.net.Uri
import android.util.Base64
import android.graphics.Bitmap
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

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

    @Test
    fun receivedImageCreatesBoundedEncryptedThumbnail() {
        val directory = File(context.filesDir, "peer-thumbnail-test-${UUID.randomUUID()}")
        val encryptedSource = File(directory, "data.sasie")
        val sourceBitmap = Bitmap.createBitmap(900, 1_200, Bitmap.Config.ARGB_8888)
        val pixels = IntArray(sourceBitmap.width * sourceBitmap.height) { index ->
            val red = index * 31 and 0xff
            val green = index * 17 and 0xff
            val blue = index * 7 and 0xff
            android.graphics.Color.rgb(red, green, blue)
        }
        sourceBitmap.setPixels(pixels, 0, sourceBitmap.width, 0, 0, sourceBitmap.width, sourceBitmap.height)
        pixels.fill(0)
        val encoded = ByteArrayOutputStream().use { output ->
            assertTrue(sourceBitmap.compress(Bitmap.CompressFormat.JPEG, 96, output))
            output.toByteArray()
        }
        sourceBitmap.recycle()
        try {
            AttachmentAtRestCipher.encryptBytes(encoded, encryptedSource)
        } finally {
            encoded.fill(0)
        }
        val attachment = PeerChatAttachment(
            name = "photo.jpg",
            mimeType = "image/jpeg",
            sizeBytes = AttachmentAtRestCipher.metadata(encryptedSource).plaintextLength,
            uri = EncryptedAttachmentUris.forFile(
                context,
                encryptedSource,
                "photo.jpg",
                "image/jpeg"
            ).toString(),
            transferId = "c".repeat(64),
            transferProgress = 100,
            transferState = PeerAttachmentTransferProgress.STATE_COMPLETE
        )
        val loaded = arrayOfNulls<Bitmap>(1)
        val latch = CountDownLatch(1)
        InstrumentationRegistry.getInstrumentation().runOnMainSync {
            PeerImageThumbnailRepository.load(context, attachment, 504, 504) {
                loaded[0] = it
                latch.countDown()
            }
        }
        try {
            assertTrue(latch.await(20, TimeUnit.SECONDS))
            assertNotNull(loaded[0])
            val thumbnail = directory.listFiles()?.singleOrNull {
                it.name == ".peer-image-thumbnail-v1.sasie"
            }
            assertNotNull(thumbnail)
            assertTrue(AttachmentAtRestCipher.isEncrypted(requireNotNull(thumbnail)))
            assertTrue(AttachmentAtRestCipher.metadata(thumbnail).plaintextLength <= 100_000L)
        } finally {
            PeerImageThumbnailRepository.clearRuntimeCache()
            directory.deleteRecursively()
        }
    }
}

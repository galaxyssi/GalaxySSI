package com.galaxyssi.chat

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import javax.crypto.spec.SecretKeySpec

class PeerMessageAttachmentStoreTest {
    @get:Rule
    val temporaryFolder = TemporaryFolder()

    @Test
    fun `outgoing voice is moved from cache to durable message storage`() {
        val filesDir = temporaryFolder.newFolder("files")
        val cacheDir = temporaryFolder.newFolder("cache")
        val source = cacheDir.resolve("recording.m4a").apply {
            writeBytes(byteArrayOf(1, 2, 3, 4))
        }
        val key = SecretKeySpec(ByteArray(32) { index -> index.toByte() }, "AES")

        val stored = PeerMessageAttachmentStore.persistOutgoingVoice(
            filesDir,
            cacheDir,
            source,
            messageId = 42L,
            extension = "m4a",
            encryptionKey = key
        ).getOrThrow()

        assertFalse(source.exists())
        assertTrue(stored.isFile)
        assertFalse(stored.readBytes().contentEquals(byteArrayOf(1, 2, 3, 4)))
        assertArrayEquals(byteArrayOf(1, 2, 3, 4), AttachmentAtRestCipher.decryptBytes(stored, key))
        assertTrue(stored.path.replace('\\', '/').endsWith("peer-message-attachments-v2/outgoing/voice/msg_42.m4a.sasie"))
        assertNotNull(PeerMessageAttachmentStore.resolveOutgoingVoice(filesDir, "voice-42.m4a"))
    }

    @Test
    fun `completed incoming attachment follows chat lifetime instead of transfer age`() {
        val month = 30L * 24L * 60L * 60L * 1_000L
        val now = month * 3L

        assertFalse(PeerMessageAttachmentStore.shouldPruneIncoming(1L, true, now, month))
        assertTrue(PeerMessageAttachmentStore.shouldPruneIncoming(1L, false, now, month))
    }

    @Test
    fun `encoded opus bytes are encrypted without a plaintext staging file`() {
        val filesDir = temporaryFolder.newFolder("opus-files")
        val encoded = "OggS-OpusHead-encrypted-payload".toByteArray()
        val key = SecretKeySpec(ByteArray(32) { index -> (31 - index).toByte() }, "AES")

        val stored = PeerMessageAttachmentStore.persistOutgoingVoiceBytes(
            filesDir = filesDir,
            encoded = encoded,
            messageId = 84L,
            extension = "opus",
            encryptionKey = key
        ).getOrThrow()

        assertTrue(stored.path.replace('\\', '/').endsWith("peer-message-attachments-v2/outgoing/voice/msg_84.opus.sasie"))
        assertFalse(stored.readBytes().contentEquals(encoded))
        assertArrayEquals(encoded, AttachmentAtRestCipher.decryptBytes(stored, key))
        assertNotNull(PeerMessageAttachmentStore.resolveOutgoingVoice(filesDir, "voice-84.opus"))
    }
}

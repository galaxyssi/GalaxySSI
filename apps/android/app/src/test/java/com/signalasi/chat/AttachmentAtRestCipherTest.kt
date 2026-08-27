package com.signalasi.chat

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import javax.crypto.spec.SecretKeySpec

class AttachmentAtRestCipherTest {
    @get:Rule
    val temporaryFolder = TemporaryFolder()

    private val key = SecretKeySpec(ByteArray(32) { index -> (index * 7 + 3).toByte() }, "AES")

    @Test
    fun `attachment round trip is authenticated and does not persist plaintext`() {
        val plaintext = ByteArray(300_123) { index -> (index * 31).toByte() }
        val encrypted = temporaryFolder.newFile("photo.sasie")

        AttachmentAtRestCipher.encryptBytes(plaintext, encrypted, key)

        assertTrue(AttachmentAtRestCipher.isEncrypted(encrypted))
        assertEquals(plaintext.size.toLong(), AttachmentAtRestCipher.metadata(encrypted).plaintextLength)
        assertFalse(encrypted.readBytes().contentEquals(plaintext))
        assertArrayEquals(plaintext, AttachmentAtRestCipher.decryptBytes(encrypted, key))
    }

    @Test
    fun `tampered attachment fails authentication`() {
        val encrypted = temporaryFolder.newFile("voice.sasie")
        AttachmentAtRestCipher.encryptBytes("authenticated voice".toByteArray(), encrypted, key)
        val corrupted = encrypted.readBytes().also { bytes ->
            bytes[bytes.lastIndex] = (bytes.last().toInt() xor 0x01).toByte()
        }
        encrypted.writeBytes(corrupted)

        assertTrue(runCatching { AttachmentAtRestCipher.decryptBytes(encrypted, key) }.isFailure)
    }

    @Test
    fun `truncated source never commits an encrypted attachment`() {
        val destination = temporaryFolder.root.resolve("truncated.sasie")
        val source = byteArrayOf(1, 2, 3)

        assertTrue(
            runCatching {
                AttachmentAtRestCipher.encryptStream(source.inputStream(), 4L, destination, key)
            }.isFailure
        )
        assertFalse(destination.exists())
    }
}

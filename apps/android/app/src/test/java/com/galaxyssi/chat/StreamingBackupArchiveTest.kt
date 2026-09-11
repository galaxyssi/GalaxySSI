package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.security.MessageDigest
import java.util.Random

class StreamingBackupArchiveTest {
    @get:Rule val temporary = TemporaryFolder()
    private val password = "test-only-passphrase".toCharArray()
    private fun archive(data: ByteArray): ByteArray = ByteArrayOutputStream().also { output ->
        StreamingBackupArchive.write(output, password) { writer -> writer.record("memory", "id") { it.write(data) } }
    }.toByteArray()

    @Test fun portablePasswordRoundTripAndCiphertextsAreRandomized() {
        val text = "\u8fd9\u662f\u4ec5\u7528\u4e8e\u6d4b\u8bd5\u7684\u8bb0\u5fc6".toByteArray()
        val first = archive(text); val second = archive(text)
        assertFalse(first.contentEquals(second))
        assertFalse(String(first, Charsets.ISO_8859_1).contains(String(text, Charsets.ISO_8859_1)))
        assertEquals(1L, StreamingBackupArchive.read(first.inputStream(), password) { type, key, input ->
            assertEquals("memory", type); assertEquals("id", key); assertArrayEquals(text, input.readBytes())
        })
    }

    @Test fun incorrectPasswordTamperingAndTruncationNeverValidate() {
        val content = ByteArray(1_200_001).also(Random(123)::nextBytes)
        val bytes = archive(content)
        assertNotNull(runCatching { StreamingBackupArchive.read(bytes.inputStream(), "wrong password".toCharArray()) { _, _, i -> i.readBytes() } }.exceptionOrNull())
        for (offset in listOf(0, 8, 40, 70, bytes.lastIndex)) {
            val changed = bytes.copyOf().apply { this[offset] = (this[offset].toInt() xor 1).toByte() }
            assertNotNull("offset=$offset", runCatching {
                StreamingBackupArchive.read(changed.inputStream(), password) { _, _, i -> i.readBytes() }
            }.exceptionOrNull())
        }
        for (length in listOf(0, 39, 90, 1024 * 1024 + 40, bytes.size - 1)) {
            assertNotNull("length=$length", runCatching {
                StreamingBackupArchive.read(ByteArrayInputStream(bytes, 0, length), password) { _, _, i -> i.readBytes() }
            }.exceptionOrNull())
        }
        assertNotNull(runCatching { StreamingBackupArchive.read((bytes + byteArrayOf(0)).inputStream(), password) { _, _, i -> i.readBytes() } }.exceptionOrNull())
    }

    @Test fun failedExportDoesNotPublishOrLeaveAPartialFile() {
        val file = File(temporary.root, "failure.hcbak")
        assertNotNull(runCatching { StreamingBackupArchive.write(file, password) { writer ->
            writer.record("memory", "id") { it.write(1); error("synthetic read failure") }
        } }.exceptionOrNull())
        assertFalse(file.exists())
        assertTrue(temporary.root.listFiles()!!.isEmpty())
    }

    @Test fun existingBackupIsNotOverwritten() {
        val file = temporary.newFile("existing.hcbak").apply { writeText("preserve") }
        assertNotNull(runCatching { StreamingBackupArchive.write(file, password) {} }.exceptionOrNull())
        assertEquals("preserve", file.readText())
    }

    @Test fun destinationCreatedDuringExportIsNotOverwritten() {
        val file = File(temporary.root, "racing.hcbak")
        assertNotNull(runCatching { StreamingBackupArchive.write(file, password) { file.writeText("preserve") } }.exceptionOrNull())
        assertEquals("preserve", file.readText())
        assertEquals(listOf(file), temporary.root.listFiles()!!.toList())
    }

    @Test fun callerOwnsOutputAndGetsAFullyAuthenticatedFooter() {
        var closed = false
        val output = object : ByteArrayOutputStream() { override fun close() { closed = true; super.close() } }
        assertEquals(0L, StreamingBackupArchive.write(output, password) {})
        assertFalse(closed)
        assertEquals(0L, StreamingBackupArchive.read(output.toByteArray().inputStream(), password) { _, _, _ -> fail() })
    }

    @Test fun largeRecordIsWrittenAndReadWithFixedWorkingBuffers() {
        val file = File(temporary.root, "large.hcbak")
        val chunk = ByteArray(64 * 1024).also(Random(47)::nextBytes)
        val expected = MessageDigest.getInstance("SHA-256")
        assertEquals(1L, StreamingBackupArchive.write(file, password) { writer ->
            writer.record("memory", "large") { output -> repeat(800) { output.write(chunk); expected.update(chunk) } }
        })
        assertTrue(file.length() > 50_000_000L)
        assertTrue(StreamingBackupArchive.isStreaming(file))
        val actual = MessageDigest.getInstance("SHA-256")
        var bytes = 0L
        StreamingBackupArchive.read(file, password) { _, _, input ->
            val buffer = ByteArray(32 * 1024)
            while (true) {
                val n = input.read(buffer)
                if (n < 0) break
                actual.update(buffer, 0, n); bytes += n
            }
            buffer.fill(0)
        }
        assertEquals(52_428_800L, bytes)
        assertArrayEquals(expected.digest(), actual.digest())
    }
}

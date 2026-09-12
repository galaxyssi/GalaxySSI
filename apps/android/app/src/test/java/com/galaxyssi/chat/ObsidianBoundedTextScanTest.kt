package com.galaxyssi.chat

import java.io.ByteArrayInputStream
import java.io.FilterInputStream
import java.security.MessageDigest
import org.junit.Assert.*
import org.junit.Test

class ObsidianBoundedTextScanTest {
    @Test fun hashesWholeLargeDocumentButRetainsOnlyPrefix() {
        val text = "\u77e5\u8bc6\ud83d\ude00\n".repeat(100000)
        val result = ObsidianBoundedTextScan.read(ByteArrayInputStream(text.toByteArray()), 91)
        assertEquals(text.take(91), result.prefix)
        assertEquals(hash(text.toByteArray()), result.hash)
    }
    @Test fun malformedUtf8AndSplitSurrogatesMatchOldReadTextHash() {
        val bytes = "a".repeat(8191).toByteArray() + "\ud83d\ude00".toByteArray() + byteArrayOf(-64, -1, 65)
        val input = object : FilterInputStream(ByteArrayInputStream(bytes)) {
            override fun read(buffer: ByteArray, offset: Int, length: Int): Int = super.read(buffer, offset, minOf(1, length))
        }
        val old = bytes.inputStream().bufferedReader().use { it.readText() }
        val result = ObsidianBoundedTextScan.read(input, 8192)
        assertEquals(old.take(8192), result.prefix)
        assertEquals(hash(old.toByteArray()), result.hash)
    }
    @Test fun zeroPrefixStillAuthenticatesAllTextAndEmptyTextHasStandardDigest() {
        assertEquals(ObsidianScannedText("", hash("abc".toByteArray())), ObsidianBoundedTextScan.read("abc".byteInputStream(), 0))
        assertEquals(ObsidianScannedText("", hash(byteArrayOf())), ObsidianBoundedTextScan.read("".byteInputStream(), 30))
        assertThrows(IllegalArgumentException::class.java) { ObsidianBoundedTextScan.read("".byteInputStream(), -1) }
    }
    private fun hash(bytes: ByteArray) = ObsidianContentHash.hex(MessageDigest.getInstance("SHA-256").digest(bytes))
}

package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.DataOutputStream
import java.util.Random

class BackupRecordStreamTest {
    private fun frame(write: (BackupRecordStream.Writer) -> Unit): ByteArray = ByteArrayOutputStream().also {
        val writer = BackupRecordStream.Writer(it); write(writer); writer.finish()
    }.toByteArray()

    @Test fun emptyArchiveAndEmptyRecordAreDistinct() {
        assertEquals(0L, BackupRecordStream.read(frame {}.inputStream()) { _, _, _ -> fail() })
        val bytes = frame { it.record("memory", "empty") {} }
        assertEquals(1L, BackupRecordStream.read(bytes.inputStream()) { type, key, input ->
            assertEquals("memory", type); assertEquals("empty", key); assertEquals(-1, input.read())
        })
    }

    @Test fun blockBoundariesAndUnicodeRoundTripWithoutRecordLengthLimit() {
        for (size in listOf(1, 65_535, 65_536, 65_537, 300_019)) {
            val data = ByteArray(size).also(Random(size.toLong())::nextBytes)
            val bytes = frame { it.record("\u8bb0\u5fc6", "\u8303\u56f4-\ud83d\ude80") { out -> out.write(data) } }
            assertEquals(1L, BackupRecordStream.read(bytes.inputStream()) { type, key, input ->
                assertEquals("\u8bb0\u5fc6", type); assertEquals("\u8303\u56f4-\ud83d\ude80", key)
                assertArrayEquals(data, input.readBytes())
            })
        }
    }

    @Test fun repetitivePayloadIsCompressedInBoundedBlocks() {
        val data = ByteArray(2_000_001) { 97 }
        val bytes = frame { it.record("memory", "compressed") { out -> out.write(data) } }
        assertTrue(bytes.size < 25_000)
        BackupRecordStream.read(bytes.inputStream()) { _, _, input -> assertArrayEquals(data, input.readBytes()) }
    }

    @Test fun visitorCannotLeaveARecordPartiallyConsumed() {
        val bytes = frame { it.record("memory", "id") { out -> out.write(byteArrayOf(1, 2)) } }
        assertNotNull(runCatching { BackupRecordStream.read(bytes.inputStream()) { _, _, _ -> } }.exceptionOrNull())
    }

    @Test fun writerFailureCannotBeSwallowedAndFinalized() {
        val writer = BackupRecordStream.Writer(ByteArrayOutputStream())
        assertNotNull(runCatching { writer.record("memory", "bad") { error("source failed") } }.exceptionOrNull())
        assertNotNull(runCatching { writer.finish() }.exceptionOrNull())
        assertNotNull(runCatching { writer.record("memory", "next") {} }.exceptionOrNull())
    }

    @Test fun nestedRecordsAndReusedWritersAreRejected() {
        val writer = BackupRecordStream.Writer(ByteArrayOutputStream())
        assertNotNull(runCatching { writer.record("memory", "outer") { writer.record("memory", "inner") {} } }.exceptionOrNull())
        val finished = BackupRecordStream.Writer(ByteArrayOutputStream())
        finished.finish()
        assertNotNull(runCatching { finished.finish() }.exceptionOrNull())
        assertNotNull(runCatching { finished.record("memory", "late") {} }.exceptionOrNull())
    }

    @Test fun everyTruncatedOffsetInSmallArchiveFails() {
        val bytes = frame { it.record("memory", "id") { out -> out.write(byteArrayOf(1, 2, 3, 4)) } }
        for (length in 0 until bytes.size) {
            assertNotNull("length=$length", runCatching {
                BackupRecordStream.read(ByteArrayInputStream(bytes, 0, length)) { _, _, input -> input.readBytes() }
            }.exceptionOrNull())
        }
    }

    @Test fun footerCountAndTrailingDataAreValidated() {
        val bytes = frame {}
        bytes[bytes.lastIndex] = 1
        assertNotNull(runCatching { BackupRecordStream.read(bytes.inputStream()) { _, _, _ -> } }.exceptionOrNull())
        assertNotNull(runCatching { BackupRecordStream.read((frame {} + byteArrayOf(0)).inputStream()) { _, _, _ -> } }.exceptionOrNull())
    }

    @Test fun malformedSizesAndCompressionCannotAllocateUnboundedBlocks() {
        for (size in listOf(-1, 65_537, Int.MAX_VALUE)) {
            val bytes = ByteArrayOutputStream().also { output -> DataOutputStream(output).apply {
                writeByte(0x52); writeInt(1); writeByte(65); writeInt(1); writeByte(66); writeInt(size)
            } }.toByteArray()
            assertNotNull(runCatching { BackupRecordStream.read(bytes.inputStream()) { _, _, input -> input.read() } }.exceptionOrNull())
        }
        val invalidCompressed = ByteArrayOutputStream().also { output -> DataOutputStream(output).apply {
            writeByte(0x52); writeInt(1); writeByte(65); writeInt(1); writeByte(66)
            writeInt(65_536); writeInt(1); writeByte(0)
        } }.toByteArray()
        assertNotNull(runCatching { BackupRecordStream.read(invalidCompressed.inputStream()) { _, _, input -> input.read() } }.exceptionOrNull())
    }

    @Test fun labelsCannotBeEmptyOversizedOrMalformedUnicode() {
        for (label in listOf("", "x".repeat(4_097), "\ud800")) {
            assertNotNull(runCatching { frame { it.record(label, "id") {} } }.exceptionOrNull())
            assertNotNull(runCatching { frame { it.record("memory", label) {} } }.exceptionOrNull())
        }
    }

    @Test fun manyRecordsAreVisitedIncrementallyWithoutAccumulatingThem() {
        var count = 0
        val bytes = frame { writer -> repeat(20_003) { n -> writer.record("memory", n.toString()) { it.write(n and 255) } } }
        assertEquals(20_003L, BackupRecordStream.read(bytes.inputStream()) { _, key, input ->
            assertEquals(count.toString(), key); assertEquals(count++ and 255, input.read()); assertEquals(-1, input.read())
        })
        assertEquals(20_003, count)
    }
}

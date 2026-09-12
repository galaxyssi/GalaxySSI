package com.galaxyssi.chat

import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.RandomAccessFile
import java.nio.file.Files
import org.junit.Assert.*
import org.junit.Test

class KnowledgeExternalOrderTest {
    @Test fun encryptedMultiLevelMergePreservesChunkAndUtf16IdentityOrderWithinBounds() = isolated { parent ->
        val expected = (0 until 10001).map { KnowledgeOrderKey(it % 13 - 6, "\u8bb0\u5fc6-$it-\ud83d\ude00") }.sorted()
        KnowledgeEncryptedScratch(parent).use { scratch ->
            val order = KnowledgeExternalOrder(scratch, 1024, 4)
            expected.shuffled(kotlin.random.Random(71)).forEach(order::add)
            val file = order.finish()
            assertEquals(expected, read(scratch, file))
            assertTrue(order.peakBufferedBytes <= 1024)
            assertTrue(order.peakMergeHeads <= 4)
            assertTrue(order.peakRunFiles <= 25)
            assertFalse(file.readBytes().toString(Charsets.UTF_8).contains("\u8bb0\u5fc6"))
            assertEquals(2, scratch.directory.listFiles()!!.size)
        }
        assertEquals(listOf(".lock"), parent.list()!!.toList())
    }

    @Test fun emptyAndSingleOversizedIdentityKeepExactOrderingWithoutItemCountLimit() = isolated { parent ->
        KnowledgeEncryptedScratch(parent).use { scratch ->
            assertEquals(emptyList<KnowledgeOrderKey>(), read(scratch, KnowledgeExternalOrder(scratch).finish()))
            val keys = listOf(KnowledgeOrderKey(Int.MAX_VALUE, "z".repeat(10000)),
                KnowledgeOrderKey(Int.MIN_VALUE, "\ud800"), KnowledgeOrderKey(Int.MIN_VALUE, "\ud7ff"))
            val order = KnowledgeExternalOrder(scratch, 128, 2)
            keys.forEach(order::add)
            assertEquals(keys.sorted(), read(scratch, order.finish()))
            assertTrue(order.peakBufferedBytes <= keys.maxOf { it.estimatedBytes })
        }
    }

    @Test fun duplicateIdentityAndTruncatedAuthenticatedRunFailClosed() = isolated { parent ->
        KnowledgeEncryptedScratch(parent).use { scratch ->
            val order = KnowledgeExternalOrder(scratch, 64, 2)
            order.add(KnowledgeOrderKey(1, "same"))
            assertThrows(IllegalStateException::class.java) { order.add(KnowledgeOrderKey(1, "same")) }
            val another = KnowledgeExternalOrder(scratch)
            another.add(KnowledgeOrderKey(3, "test"))
            val file = another.finish()
            RandomAccessFile(file, "rw").use { it.setLength(it.length() - 1) }
            assertThrows(Exception::class.java) { read(scratch, file) }
        }
    }

    @Test fun encryptedFileCannotBeSubstitutedUnderAnotherName() = isolated { parent ->
        KnowledgeEncryptedScratch(parent).use { scratch ->
            val original = scratch.create()
            scratch.output(original).use { it.write("private-fixture".toByteArray()) }
            val swapped = scratch.create()
            original.copyTo(swapped, overwrite = true)
            assertThrows(Exception::class.java) { scratch.input(swapped).use { it.readBytes() } }
        }
    }

    @Test fun cleanupKeepsActiveJobButRemovesOrphanedEncryptedScratch() = isolated { parent ->
        val first = KnowledgeEncryptedScratch(parent)
        try {
            val file = first.create()
            first.output(file).use { it.write(42) }
            val orphan = File(parent, "job-00000000-0000-0000-0000-000000000000").apply { mkdir() }
            File(orphan, "part-old.aead").writeBytes(byteArrayOf(1, 2, 3))
            KnowledgeEncryptedScratch(parent).use {
                assertTrue(first.directory.exists())
                assertFalse(orphan.exists())
                assertEquals(42, first.input(file).use { source -> source.read() })
            }
        } finally { first.close() }
    }

    @Test fun runCodecRejectsTruncationCountMismatchAndTrailingRecords() {
        val bytes = ByteArrayOutputStream().also { output ->
            KnowledgeOrderRun.Writer(output).use { it.add(KnowledgeOrderKey(1, "sample")) }
        }.toByteArray()
        fun consume(value: ByteArray) = KnowledgeOrderRun.Reader(ByteArrayInputStream(value)).use { while (it.next() != null) Unit }
        for (length in bytes.indices) assertThrows(Exception::class.java) { consume(bytes.copyOf(length)) }
        assertThrows(Exception::class.java) { consume(bytes + byteArrayOf(0)) }
        bytes[bytes.lastIndex] = 2
        assertThrows(Exception::class.java) { consume(bytes) }
    }

    @Test fun interruptionStopsWorkAndCloseStillClearsScratch() = isolated { parent ->
        val scratch = KnowledgeEncryptedScratch(parent)
        try {
            Thread.currentThread().interrupt()
            assertThrows(IllegalStateException::class.java) { scratch.create() }
        } finally { Thread.interrupted(); scratch.close() }
        assertEquals(listOf(".lock"), parent.list()!!.toList())
    }

    private fun read(scratch: KnowledgeEncryptedScratch, file: File): List<KnowledgeOrderKey> =
        KnowledgeOrderRun.Reader(scratch.input(file)).use { reader -> buildList { while (true) add(reader.next() ?: break) } }
    private fun isolated(block: (File) -> Unit) {
        val root = Files.createTempDirectory("knowledge-order-test").toFile()
        try { block(root) } finally { check(root.deleteRecursively()) }
    }
}

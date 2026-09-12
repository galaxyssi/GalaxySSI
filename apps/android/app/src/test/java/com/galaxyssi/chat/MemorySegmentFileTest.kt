package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import java.io.RandomAccessFile
import java.util.UUID
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

class MemorySegmentFileTest {
    @get:Rule val temporary = TemporaryFolder()
    private val key = SecretKeySpec(ByteArray(32) { it.toByte() }, "AES")
    private val scope = "synthetic-memory-scope".toByteArray()
    private var largestBlock = 0
    private fun encrypt(bytes: ByteArray, aad: ByteArray): ByteArray {
        largestBlock = maxOf(largestBlock, bytes.size)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key); cipher.updateAAD(aad)
        return byteArrayOf(1) + cipher.iv + cipher.doFinal(bytes)
    }
    private fun decrypt(bytes: ByteArray, aad: ByteArray): ByteArray {
        require(bytes[0] == 1.toByte())
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(128, bytes, 1, 12)); cipher.updateAAD(aad)
        return cipher.doFinal(bytes, 13, bytes.size - 13)
    }
    private fun store(root: File, sync: (File) -> Unit = {}) =
        MemorySegmentFile(root, ::encrypt, ::decrypt, sync, targetBytes = 65_536)
    private fun file(root: File, r: MemorySegmentFile.Reference) = File(File(root, r.segment.toString().take(2)), "${r.segment}.seg")
    private fun bytes(n: Int) = ByteArray(n) { (it * 71).toByte() }
    private fun fails(block: () -> Unit) { assertNotNull(runCatching(block).exceptionOrNull()) }

    @Test fun authenticatedRoundTripAcrossBlockBoundaries() {
        val s = store(temporary.newFolder())
        for (n in listOf(1, 65_535, 65_536, 65_537, 2_000_019)) {
            val data = bytes(n)
            val r = s.append(scope) { it.write(data) }
            assertEquals(n.toLong(), r.plaintextBytes)
            assertEquals((n + 65_535L) / 65_536, r.blocks)
            assertArrayEquals(data, s.read(r, scope) { it.readBytes() })
        }
        assertEquals(65_536, largestBlock)
    }

    @Test fun pinnedReadAllowsConcurrentAppendToTheSameSegment() {
        val s = MemorySegmentFile(temporary.newFolder(), ::encrypt, ::decrypt, {})
        val original = bytes(70_019)
        val r = s.append(scope) { it.write(original) }
        val executor = java.util.concurrent.Executors.newSingleThreadExecutor()
        try {
            val result = s.readPinned(r, scope) { input ->
                val first = input.read()
                val next = executor.submit<MemorySegmentFile.Reference> { s.append(scope) { it.write(bytes(8000)) } }
                    .get(5, java.util.concurrent.TimeUnit.SECONDS)
                assertEquals(r.segment, next.segment)
                assertArrayEquals(bytes(8000), s.readPinned(next, scope) { it.readBytes() })
                byteArrayOf(first.toByte()) + input.readBytes()
            }
            assertArrayEquals(original, result)
        } finally { executor.shutdownNow(); assertTrue(executor.awaitTermination(5, java.util.concurrent.TimeUnit.SECONDS)) }
    }

    @Test fun pinnedReadersHaveIndependentOffsetsAndAuthenticationState() {
        val s = store(temporary.newFolder())
        val original = bytes(150_003)
        val r = s.append(scope) { it.write(original) }
        val entered = java.util.concurrent.CountDownLatch(2)
        val executor = java.util.concurrent.Executors.newFixedThreadPool(2)
        try {
            val futures = (1..2).map {
                executor.submit<ByteArray> { s.readPinned(r, scope) { input ->
                    val first = input.read()
                    entered.countDown()
                    assertTrue(entered.await(5, java.util.concurrent.TimeUnit.SECONDS))
                    byteArrayOf(first.toByte()) + input.readBytes()
                } }
            }
            futures.forEach { assertArrayEquals(original, it.get(5, java.util.concurrent.TimeUnit.SECONDS)) }
        } finally { executor.shutdownNow(); assertTrue(executor.awaitTermination(5, java.util.concurrent.TimeUnit.SECONDS)) }
    }

    @Test fun pinnedReadStillRejectsWrongScopeAndPartialConsumption() {
        val s = store(temporary.newFolder())
        val r = s.append(scope) { it.write(bytes(70_000)) }
        fails { s.readPinned(r, "other scope".toByteArray()) { it.readBytes() } }
        fails { s.readPinned(r, scope) { it.read() } }
        assertArrayEquals(bytes(70_000), s.readPinned(r, scope) { it.readBytes() })
    }

    @Test fun partitionsRotateAndReferencesSurviveReopen() {
        val root = temporary.newFolder()
        val s = store(root)
        val references = (0 until 20).map { i -> s.append(scope) { it.write(bytes(70_000 + i)) } }
        assertEquals(20, references.map { it.segment }.toSet().size)
        val reopened = store(root)
        references.forEachIndexed { i, r -> assertArrayEquals(bytes(70_000 + i), reopened.read(r, scope) { it.readBytes() }) }
        val new = reopened.append(scope) { it.write(7) }
        assertFalse(new.segment in references.map { it.segment })
    }

    @Test fun registrationFailureNeverPublishesAnUnregisteredFile() {
        val root = temporary.newFolder()
        val s = MemorySegmentFile(root, ::encrypt, ::decrypt, {}, register = { error("catalog unavailable") })
        fails { s.append(scope) { it.write(bytes(200)) } }
        assertFalse(root.walkTopDown().any { it.extension == "seg" })
    }

    @Test fun compactionReauthenticatesLocationsAndKeepsTheOriginalUntilReclaimed() {
        val root = temporary.newFolder()
        val s = store(root)
        val data = bytes(200_017)
        val before = s.append(scope) { it.write(data) }
        s.seal()
        val after = s.relocate(before, scope)
        assertNotEquals(before.segment, after.segment)
        assertArrayEquals(data, s.read(before, scope) { it.readBytes() })
        assertArrayEquals(data, s.read(after, scope) { it.readBytes() })
        assertTrue(s.remove(before.segment) > 0)
        assertEquals(0L, s.remove(before.segment))
        fails { s.read(before, scope) { it.readBytes() } }
        assertArrayEquals(data, store(root).read(after, scope) { it.readBytes() })
        assertEquals(65_536, largestBlock)
    }

    @Test fun reclaimedActiveSegmentIsNeverRecreatedUnderItsOldIdentity() {
        val root = temporary.newFolder()
        val s = store(root)
        val first = s.append(scope) { it.write(1) }
        s.remove(first.segment)
        val next = s.append(scope) { it.write(2) }
        assertNotEquals(first.segment, next.segment)
        assertEquals(2, s.read(next, scope) { it.read() })
    }

    @Test fun cancellationBetweenFramesKeepsThePublishedSourceAndAbandonsTheTail() {
        val root = temporary.newFolder()
        val s = store(root)
        val data = bytes(200_017)
        val source = s.append(scope) { it.write(data) }
        var checks = 0
        val cancellation = java.util.concurrent.CancellationException("foreground")
        assertSame(cancellation, runCatching {
            s.relocate(source, scope) { if (++checks == 2) throw cancellation }
        }.exceptionOrNull())
        assertEquals(2, checks)
        assertArrayEquals(data, s.read(source, scope) { it.readBytes() })
        val orphanIds = root.walkTopDown().filter { it.extension == "seg" }.map { it.nameWithoutExtension }.toSet()
        val next = s.append(scope) { it.write(7) }
        assertFalse(next.segment.toString() in orphanIds)
        assertEquals(7, s.read(next, scope) { it.read() })
    }

    @Test fun failedTailNeverReplacesPreviouslyCommittedBytes() {
        val root = temporary.newFolder()
        val s = store(root)
        val before = s.append(scope) { it.write(bytes(100)) }
        fails { s.append(scope) { it.write(bytes(70_000)); error("simulated producer failure") } }
        val after = s.append(scope) { it.write(bytes(110)) }
        assertNotEquals(before.segment, after.segment)
        assertArrayEquals(bytes(100), s.read(before, scope) { it.readBytes() })
        assertArrayEquals(bytes(110), s.read(after, scope) { it.readBytes() })
    }

    @Test fun rawOrphanAppendDoesNotChangeAnyPublishedReference() {
        val root = temporary.newFolder()
        val s = store(root)
        val r = s.append(scope) { it.write(bytes(200)) }
        // SQLite publication may fail after this second durable append.
        s.append(scope) { it.write(bytes(201)) }
        assertArrayEquals(bytes(200), store(root).read(r, scope) { it.readBytes() })
    }

    @Test fun identityScopeAndOffsetSwapsFailAuthentication() {
        val s = store(temporary.newFolder())
        val r = s.append(scope) { it.write(bytes(100)) }
        val another = s.append(scope) { it.write(bytes(100)) }
        fails { s.read(r, "other namespace or item".toByteArray()) { it.readBytes() } }
        fails { s.read(r.copy(record = UUID.randomUUID()), scope) { it.readBytes() } }
        fails { s.read(r.copy(offset = another.offset), scope) { it.readBytes() } }
    }

    @Test fun everyCorruptByteInASmallRecordIsRejected() {
        val root = temporary.newFolder()
        val s = store(root)
        val r = s.append(scope) { it.write(bytes(20)) }
        val path = file(root, r)
        val original = path.readBytes()
        for (i in original.indices) {
            val changed = original.copyOf(); changed[i] = (changed[i].toInt() xor 1).toByte()
            path.writeBytes(changed)
            fails { s.read(r, scope) { it.readBytes() } }
        }
    }

    @Test fun missingAndTruncatedFilesAreNotAnEmptyMemory() {
        val root = temporary.newFolder()
        val s = store(root)
        val r = s.append(scope) { it.write(bytes(200)) }
        val path = file(root, r)
        RandomAccessFile(path, "rw").use { it.setLength(r.length - 1) }
        fails { s.read(r, scope) { it.readBytes() } }
        assertTrue(path.delete())
        fails { s.read(r, scope) { it.readBytes() } }
    }

    @Test fun callerMustConsumeTheCompleteAuthenticatedRecord() {
        val s = store(temporary.newFolder())
        val r = s.append(scope) { it.write(bytes(70_000)) }
        fails { s.read(r, scope) { it.read() } }
        assertArrayEquals(bytes(70_000), s.read(r, scope) { it.readBytes() })
    }

    @Test fun falsifiedLengthsAndBlockCountsFail() {
        val s = store(temporary.newFolder())
        val r = s.append(scope) { it.write(bytes(70_000)) }
        for (bad in listOf(r.copy(length = r.length - 1), r.copy(plaintextBytes = r.plaintextBytes - 1),
            r.copy(blocks = 1), r.copy(blocks = 3))) {
            fails { s.read(bad, scope) { it.readBytes() } }
        }
    }

    @Test fun referenceUsesCheckedLongOffsetsAndExactEncoding() {
        val r = MemorySegmentFile.Reference(UUID.randomUUID(), UUID.randomUUID(), 4_000_000_000, 101, 68, 1)
        assertEquals(r, MemorySegmentFile.Reference.parse(r.bytes()))
        fails { MemorySegmentFile.Reference.parse(r.bytes() + byteArrayOf(0)) }
        fails { MemorySegmentFile.Reference.parse(r.copy(offset = Long.MAX_VALUE).bytes()) }
        fails { MemorySegmentFile.Reference.parse(r.copy(blocks = Long.MAX_VALUE).bytes()) }
        fails { MemorySegmentFile.Reference.parse(r.copy(plaintextBytes = -1).bytes()) }
    }

    @Test fun directorySyncFailureDoesNotPublishAReference() {
        var synced = 0
        val root = File(temporary.newFolder(), "segments")
        val s = store(root) { synced++; error("injected fsync failure") }
        fails { s.append(scope) { it.write(1) } }
        assertEquals(1, synced)
        val reopened = store(root)
        val r = reopened.append(scope) { it.write(2) }
        assertEquals(2, reopened.read(r, scope) { it.read() })
    }

    @Test fun emptyOrMalformedProducerCannotPublish() {
        val s = store(temporary.newFolder())
        fails { s.append(scope) {} }
        fails { s.append(scope) { it.write(bytes(4), 3, 2) } }
    }
}

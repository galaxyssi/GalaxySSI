package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import java.io.RandomAccessFile
import java.util.UUID
import java.util.concurrent.CancellationException
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

class MemorySegmentCopyTest {
    @get:Rule val temporary = TemporaryFolder()
    private val scope = "memory-copy-fixture".toByteArray()
    private val key = SecretKeySpec(ByteArray(32) { it.toByte() }, "AES")
    private var largest = 0
    private fun encrypt(plain: ByteArray, aad: ByteArray): ByteArray {
        largest = maxOf(largest, plain.size)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key); cipher.updateAAD(aad)
        return byteArrayOf(1) + cipher.iv + cipher.doFinal(plain)
    }
    private fun decrypt(encrypted: ByteArray, aad: ByteArray): ByteArray {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(128, encrypted, 1, 12)); cipher.updateAAD(aad)
        return cipher.doFinal(encrypted, 13, encrypted.size - 13)
    }
    private fun store(root: File) = MemorySegmentFile(root, ::encrypt, ::decrypt, {})
    private fun file(root: File, id: UUID) = File(File(root, id.toString().take(2)), "$id.seg")
    private fun data(size: Int = 2_300_017) = ByteArray(size).also { java.util.Random(72).nextBytes(it) }
    private fun finish(root: File, initial: MemorySegmentCopy.State): MemorySegmentCopy.State {
        var state = initial
        var iterations = 0
        while (!state.complete) {
            check(++iterations < 200)
            state = store(root).copyStep(MemorySegmentCopy.State.parse(state.bytes()), scope, 1024 * 1024) {}
        }
        return state
    }

    @Test fun realMultiMegabyteCopyReopensAtEveryCheckpointAndVerifiesBeforeCompletion() {
        val root = temporary.newFolder(); val s = store(root); val data = data()
        val source = s.append(scope) { it.write(data) }
        var state = s.beginCopy(source)
        assertEquals(152, state.bytes().size)
        var steps = 0
        while (!state.complete) {
            val before = state
            state = store(root).copyStep(MemorySegmentCopy.State.parse(state.bytes()), scope, 1024 * 1024) {}
            assertTrue(state.copiedBytes - before.copiedBytes <= 1024 * 1024)
            assertTrue(state.verifiedBytes - before.verifiedBytes <= 1024 * 1024)
            assertTrue(file(root, source.segment).exists())
            steps++
        }
        assertEquals(6, steps)
        assertEquals(65_536, largest)
        assertArrayEquals(data, s.read(state.target, scope) { it.readBytes() })
        assertArrayEquals(data, s.read(source, scope) { it.readBytes() })
    }

    @Test fun fullCopyIsNotCompleteUntilAnIndependentVerificationPass() {
        val root = temporary.newFolder(); val s = store(root)
        val source = s.append(scope) { it.write(data(100)) }
        val copied = s.copyStep(s.beginCopy(source), scope, 1024 * 1024) {}
        assertEquals(source.length, copied.copiedBytes)
        assertFalse(copied.complete)
        assertTrue(s.copyStep(copied, scope, 1024 * 1024) {}.complete)
    }

    @Test fun unpublishedTailIsTruncatedAndReplayedFromTheDurableCheckpoint() {
        val root = temporary.newFolder(); val s = store(root); val data = data()
        val initial = s.beginCopy(s.append(scope) { it.write(data) })
        val first = s.copyStep(initial, scope, 1024 * 1024) {}
        s.copyStep(first, scope, 1024 * 1024) {}
        assertTrue(file(root, first.destination).length() > first.copiedBytes)
        val done = finish(root, first)
        assertArrayEquals(data, s.read(done.target, scope) { it.readBytes() })
    }

    @Test fun cancellationDoesNotAdvanceTheCheckpointOrOverwriteTheOriginal() {
        val root = temporary.newFolder(); val s = store(root); val data = data()
        val initial = s.beginCopy(s.append(scope) { it.write(data) })
        var calls = 0
        val failure = CancellationException("foreground")
        assertSame(failure, runCatching { s.copyStep(initial, scope, 1024 * 1024) { if (++calls == 3) throw failure } }.exceptionOrNull())
        assertEquals(0L, initial.copiedBytes)
        assertArrayEquals(data, s.read(initial.source, scope) { it.readBytes() })
        assertArrayEquals(data, s.read(finish(root, initial).target, scope) { it.readBytes() })
    }

    @Test fun aSlowBatchCheckpointsCompletedFramesBeforeYieldingInsteadOfLivelocking() {
        val root = temporary.newFolder()
        var nanos = 0L
        val s = MemorySegmentFile(root, { plain, aad -> nanos += 100; encrypt(plain, aad) }, ::decrypt, {})
        val source = s.append(scope) { it.write(data()) }
        var state = s.beginCopy(source)
        nanos = 0
        val result = MemorySegmentSweep({ false }, { check ->
            state = s.copyStep(state, scope, 1024 * 1024, check)
            state.complete
        }, { nanos }, 200).run()
        assertEquals(MemorySegmentSweep.Outcome.DEFERRED, result)
        assertTrue(state.copiedBytes > 0 && state.copiedBytes < source.length)
        assertEquals(2L, state.copiedBlocks)
        assertTrue(finish(root, state).complete)
    }

    @Test fun aMissingOrShortCheckpointedDestinationFailsWithoutRecreatingIt() {
        for (missing in listOf(false, true)) {
            val root = temporary.newFolder(); val s = store(root)
            val initial = s.beginCopy(s.append(scope) { it.write(data()) })
            val state = s.copyStep(initial, scope, 1024 * 1024) {}
            val destination = file(root, state.destination)
            if (missing) assertTrue(destination.delete()) else RandomAccessFile(destination, "rw").use { it.setLength(state.copiedBytes - 1) }
            assertTrue(runCatching { s.copyStep(state, scope, 1024 * 1024) {} }.isFailure)
            if (missing) assertFalse(destination.exists())
            assertTrue(file(root, initial.source.segment).exists())
        }
    }

    @Test fun copiedDataCorruptionIsDetectedBeforeSourcePublication() {
        val root = temporary.newFolder(); val s = store(root)
        var state = s.beginCopy(s.append(scope) { it.write(data(100)) })
        state = s.copyStep(state, scope, 1024 * 1024) {}
        RandomAccessFile(file(root, state.destination), "rw").use {
            it.seek(8); val before = it.readUnsignedByte(); it.seek(8); it.writeByte(before xor 1)
        }
        assertTrue(runCatching { s.copyStep(state, scope, 1024 * 1024) {} }.isFailure)
        assertFalse(state.complete)
        assertTrue(file(root, state.source.segment).exists())
    }

    @Test fun completedCheckpointStillRequiresTheDestinationToExistAtPublication() {
        val root = temporary.newFolder(); val s = store(root)
        val done = finish(root, s.beginCopy(s.append(scope) { it.write(data(100)) }))
        assertTrue(file(root, done.destination).delete())
        assertTrue(runCatching { s.copyStep(done, scope, 1024 * 1024) {} }.isFailure)
    }

    @Test fun wrongScopeAndFrameOrdinalFailAuthentication() {
        val root = temporary.newFolder(); val s = store(root)
        val state = s.beginCopy(s.append(scope) { it.write(data()) })
        assertTrue(runCatching { s.copyStep(state, "another-memory".toByteArray(), 1024 * 1024) {} }.isFailure)
        val first = s.copyStep(state, scope, MemorySegmentCopy.MAX_FRAME_BYTES) {}
        val bad = first.copy(copiedBlocks = 2, copiedPlain = first.copiedPlain - 33)
        assertTrue(runCatching { s.copyStep(bad, scope, 1024 * 1024) {} }.isFailure)
    }

    @Test fun invalidCheckpointArithmeticAndSelfOverwriteAreRejected() {
        val root = temporary.newFolder(); val s = store(root)
        val initial = s.beginCopy(s.append(scope) { it.write(data(100)) })
        for (bad in listOf(initial.copy(destination = initial.source.segment), initial.copy(copiedBytes = -1),
            initial.copy(copiedBytes = 1, copiedPlain = 1), initial.copy(copiedBlocks = Long.MAX_VALUE),
            initial.copy(verifiedBytes = 34, verifiedPlain = 1, verifiedBlocks = 1))) {
            assertTrue(runCatching { bad.bytes() }.isFailure)
        }
        assertTrue(runCatching { MemorySegmentCopy.State.parse(initial.bytes() + byteArrayOf(0)) }.isFailure)
    }

    @Test fun longOffsetsArePreservedWithoutIntTruncation() {
        val source = MemorySegmentFile.Reference(UUID.randomUUID(), UUID.randomUUID(), 5_000_000_000L, 133, 100, 1)
        val state = MemorySegmentCopy.State(source, UUID.randomUUID(), UUID.randomUUID())
        assertEquals(state, MemorySegmentCopy.State.parse(state.bytes()))
    }

    @Test fun detachedDestinationIsNotUsedByNormalAppends() {
        val root = temporary.newFolder(); val s = store(root)
        val initial = s.beginCopy(s.append(scope) { it.write(data(100)) })
        val other = s.append(scope) { it.write(data(101)) }
        assertNotEquals(initial.destination, other.segment)
        assertEquals(0L, file(root, initial.destination).length())
    }
}

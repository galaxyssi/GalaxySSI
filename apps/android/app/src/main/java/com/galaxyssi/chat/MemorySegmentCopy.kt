package com.galaxyssi.chat

import java.io.File
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.util.UUID
import com.galaxyssi.chat.MemorySegmentFile.Companion.ENVELOPE_BYTES

/** A pinned, detached destination. Checkpoints are authenticated by the Android adapter. */
internal class MemorySegmentCopy(
    private val path: (UUID) -> File,
    private val encrypt: (ByteArray, ByteArray) -> ByteArray,
    private val decrypt: (ByteArray, ByteArray) -> ByteArray
) {
    data class State(val source: MemorySegmentFile.Reference, val destination: UUID, val record: UUID,
        val copiedBytes: Long = 0, val copiedBlocks: Long = 0, val copiedPlain: Long = 0,
        val verifiedBytes: Long = 0, val verifiedBlocks: Long = 0, val verifiedPlain: Long = 0) {
        val target get() = source.copy(segment = destination, record = record, offset = 0)
        val complete get() = verifiedBytes == source.length

        fun validate(): State = apply {
            MemorySegmentFile.Reference.parse(source.bytes())
            require(source.length == Math.addExact(source.plaintextBytes, Math.multiplyExact(source.blocks, FRAME_OVERHEAD)))
            require(destination != source.segment && record != source.record)
            require(copiedBytes in 0..source.length && copiedBlocks in 0..source.blocks && copiedPlain in 0..source.plaintextBytes)
            require(verifiedBytes in 0..copiedBytes && verifiedBlocks in 0..copiedBlocks && verifiedPlain in 0..copiedPlain)
            require(copiedPlain in copiedBlocks..Math.multiplyExact(copiedBlocks, MemorySegmentFile.BLOCK_BYTES.toLong()))
            require(verifiedPlain in verifiedBlocks..Math.multiplyExact(verifiedBlocks, MemorySegmentFile.BLOCK_BYTES.toLong()))
            require(copiedBytes == Math.addExact(copiedPlain, Math.multiplyExact(copiedBlocks, FRAME_OVERHEAD)))
            require(verifiedBytes == Math.addExact(verifiedPlain, Math.multiplyExact(verifiedBlocks, FRAME_OVERHEAD)))
            require((copiedBytes == source.length) == (copiedBlocks == source.blocks && copiedPlain == source.plaintextBytes))
            require(verifiedBytes == 0L || copiedBytes == source.length)
            require((verifiedBytes == source.length) == (verifiedBlocks == source.blocks && verifiedPlain == source.plaintextBytes))
        }

        fun bytes(): ByteArray {
            validate()
            return ByteBuffer.allocate(152).putInt(1).put(source.bytes())
                .putLong(destination.mostSignificantBits).putLong(destination.leastSignificantBits)
                .putLong(record.mostSignificantBits).putLong(record.leastSignificantBits)
                .putLong(copiedBytes).putLong(copiedBlocks).putLong(copiedPlain)
                .putLong(verifiedBytes).putLong(verifiedBlocks).putLong(verifiedPlain).array()
        }

        companion object {
            fun parse(bytes: ByteArray): State {
                require(bytes.size == 152) { "Invalid memory copy checkpoint size" }
                val input = ByteBuffer.wrap(bytes)
                require(input.int == 1) { "Unsupported memory copy checkpoint" }
                val reference = ByteArray(68)
                input.get(reference)
                return State(MemorySegmentFile.Reference.parse(reference), UUID(input.long, input.long), UUID(input.long, input.long),
                    input.long, input.long, input.long, input.long, input.long, input.long).validate()
            }
        }
    }

    /** Caller holds exclusive segment access and confirms the old source is still current. */
    fun step(state: State, aad: ByteArray, budget: Int, checkActive: () -> Unit): State {
        state.validate()
        require(budget in MAX_FRAME_BYTES..1024 * 1024)
        checkActive()
        val copying = state.copiedBytes < state.source.length
        val reference = if (copying) state.source else state.target
        val offset = if (copying) state.copiedBytes else state.verifiedBytes
        var ordinal = if (copying) state.copiedBlocks else state.verifiedBlocks
        var total = if (copying) state.copiedPlain else state.verifiedPlain
        val inputPath = path(reference.segment)
        val destination = path(state.destination)
        check(inputPath.isFile && destination.isFile) { "Memory copy segment is missing" }
        RandomAccessFile(inputPath, "r").use { input ->
            val end = Math.addExact(reference.offset, reference.length)
            check(input.length() >= end) { "Memory copy source is truncated" }
            if (!copying) check(input.length() == end) { "Memory copy destination length mismatch" }
            if (state.complete) return state
            input.seek(Math.addExact(reference.offset, offset))
            val output = if (copying) RandomAccessFile(destination, "rw") else null
            output.use {
                if (output != null) {
                    check(output.length() >= state.copiedBytes) { "Memory copy checkpoint exceeds destination" }
                    // Bytes beyond the durable checkpoint were never published. Replay that tail.
                    output.setLength(state.copiedBytes)
                    output.seek(state.copiedBytes)
                }
                var spent = 0
                while (input.filePointer < end) {
                    try { checkActive() } catch (yield: MemoryMaintenanceYield) {
                        if (spent == 0) throw yield
                        break
                    }
                    check(end - input.filePointer >= 4) { "Missing memory copy frame" }
                    val size = input.readInt()
                    check(size in ENVELOPE_BYTES + 1..MemorySegmentFile.BLOCK_BYTES + ENVELOPE_BYTES && size.toLong() <= end - input.filePointer) {
                        "Invalid memory copy frame length"
                    }
                    if (size + 4 > budget - spent) break
                    val encrypted = ByteArray(size)
                    val plain = try {
                        input.readFully(encrypted)
                        decrypt(encrypted, MemorySegmentFile.blockAad(aad, reference, ordinal))
                    } finally { encrypted.fill(0) }
                    try {
                        check(plain.size == size - ENVELOPE_BYTES) { "Invalid memory copy cipher contract" }
                        if (output != null) {
                            val next = encrypt(plain, MemorySegmentFile.blockAad(aad, state.target, ordinal))
                            try {
                                check(next.size == size) { "Memory copy cipher length changed" }
                                output.writeInt(next.size); output.write(next)
                            } finally { next.fill(0) }
                        }
                        spent += size + 4
                        ordinal = Math.addExact(ordinal, 1)
                        total = Math.addExact(total, plain.size.toLong())
                    } finally { plain.fill(0) }
                }
                check(spent > 0) { "Memory copy made no progress" }
                // Commit complete frames on cooperative yield. Cancellation and I/O failures still propagate.
                output?.fd?.sync()
                val position = Math.addExact(offset, spent.toLong())
                return (if (copying) state.copy(copiedBytes = position, copiedBlocks = ordinal, copiedPlain = total)
                    else state.copy(verifiedBytes = position, verifiedBlocks = ordinal, verifiedPlain = total)).validate()
            }
        }
    }

    companion object {
        private const val FRAME_OVERHEAD = 4L + ENVELOPE_BYTES
        const val MAX_FRAME_BYTES = MemorySegmentFile.BLOCK_BYTES + 4 + ENVELOPE_BYTES
    }
}

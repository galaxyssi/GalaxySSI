package com.galaxyssi.chat

import java.io.File
import java.io.InputStream
import java.io.OutputStream
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.util.UUID

/** Append-only ciphertext. A reference is published only after all referenced bytes are synced. */
internal class MemorySegmentFile(
    private val root: File,
    private val encrypt: (ByteArray, ByteArray) -> ByteArray,
    private val decrypt: (ByteArray, ByteArray) -> ByteArray,
    private val syncDirectory: (File) -> Unit,
    private val targetBytes: Long = 64L * 1024 * 1024,
    private val register: (UUID) -> Unit = {}
) {
    private var active: UUID? = null

    internal data class Reference(val segment: UUID, val record: UUID, val offset: Long,
        val length: Long, val plaintextBytes: Long, val blocks: Long) {
        fun bytes(): ByteArray = ByteBuffer.allocate(68).putInt(1)
            .putLong(segment.mostSignificantBits).putLong(segment.leastSignificantBits)
            .putLong(record.mostSignificantBits).putLong(record.leastSignificantBits)
            .putLong(offset).putLong(length).putLong(plaintextBytes).putLong(blocks).array()

        companion object {
            fun parse(bytes: ByteArray): Reference {
                require(bytes.size == 68) { "Invalid memory segment reference size" }
                val b = ByteBuffer.wrap(bytes)
                require(b.int == 1) { "Unsupported memory segment reference" }
                return Reference(UUID(b.long, b.long), UUID(b.long, b.long), b.long, b.long, b.long, b.long).also {
                    require(it.offset >= 0 && it.length > 0 && it.plaintextBytes > 0 && it.blocks > 0)
                    require(it.blocks <= it.length / 33 && it.plaintextBytes <= Math.multiplyExact(it.blocks, BLOCK_BYTES.toLong()))
                    Math.addExact(it.offset, it.length)
                }
            }
        }
    }

    init { require(targetBytes >= BLOCK_BYTES) }

    @Synchronized fun append(aad: ByteArray, write: (OutputStream) -> Unit): Reference {
        val segment = active?.takeIf { file(it).isFile && file(it).length() < targetBytes } ?: newSegment()
        val path = file(segment)
        try {
            return RandomAccessFile(path, "rw").use { output ->
                val start = output.length()
                output.seek(start)
                val identity = Reference(segment, UUID.randomUUID(), start, 0, 0, 0)
                val blocks = BlockOutput(output, identity, aad, encrypt)
                try {
                    write(blocks)
                    blocks.finish()
                    require(blocks.count > 0) { "Empty memory segment record" }
                    output.fd.sync()
                    identity.copy(length = output.filePointer - start, plaintextBytes = blocks.total, blocks = blocks.count)
                } finally { blocks.wipe() }
            }
        } catch (failure: Throwable) {
            // Do not reuse a tail whose last append or fsync failed. Earlier references remain valid.
            active = null
            throw failure
        }
    }

    @Synchronized fun <T> read(reference: Reference, aad: ByteArray, consume: (InputStream) -> T): T {
        Reference.parse(reference.bytes())
        return RandomAccessFile(file(reference.segment), "r").use { input ->
            check(Math.addExact(reference.offset, reference.length) <= input.length()) { "Memory segment is truncated" }
            input.seek(reference.offset)
            val blocks = BlockInput(input, reference, aad, decrypt)
            try {
                val result = consume(blocks)
                check(blocks.read() == -1) { "Memory segment was not fully consumed" }
                result
            } finally { blocks.wipe() }
        }
    }

    private fun newSegment(): UUID {
        if (!root.isDirectory) {
            check(root.mkdirs() || root.isDirectory) { "Cannot create memory segment directory" }
        }
        syncDirectory(requireNotNull(root.parentFile))
        val id = UUID.randomUUID()
        register(id)
        val path = file(id)
        val directory = requireNotNull(path.parentFile)
        if (!directory.isDirectory) {
            check(directory.mkdir() || directory.isDirectory) { "Cannot create memory segment partition" }
        }
        syncDirectory(root)
        check(path.createNewFile()) { "Memory segment identity collision" }
        RandomAccessFile(path, "rw").use { it.fd.sync() }
        syncDirectory(directory)
        active = id
        return id
    }

    @Synchronized fun seal() { active = null }

    @Synchronized fun relocate(reference: Reference, aad: ByteArray): Reference = append(aad) { output ->
        read(reference, aad) { input ->
            val buffer = ByteArray(BLOCK_BYTES)
            try {
                while (true) {
                    val n = input.read(buffer)
                    if (n < 0) break
                    output.write(buffer, 0, n)
                }
            } finally { buffer.fill(0) }
        }
    }

    @Synchronized fun size(id: UUID): Long = file(id).length()

    /** Caller holds exclusive maintenance access and has checked committed references. */
    @Synchronized fun remove(id: UUID): Long {
        val path = file(id)
        val size = path.length()
        check(!path.exists() || path.delete()) { "Cannot reclaim memory segment" }
        path.parentFile?.takeIf { it.isDirectory }?.let(syncDirectory)
        if (active == id) active = null
        return size
    }

    private fun file(id: UUID) = File(File(root, id.toString().take(2)), "$id.seg")

    private class BlockOutput(private val file: RandomAccessFile, private val reference: Reference,
        private val aad: ByteArray, private val encrypt: (ByteArray, ByteArray) -> ByteArray) : OutputStream() {
        private val buffer = ByteArray(BLOCK_BYTES)
        private var used = 0
        private var ended = false
        var count = 0L; private set
        var total = 0L; private set
        override fun write(value: Int) {
            check(!ended)
            buffer[used++] = value.toByte()
            if (used == buffer.size) flushBlock()
        }
        override fun write(bytes: ByteArray, offset: Int, length: Int) {
            require(offset >= 0 && length >= 0 && offset <= bytes.size - length)
            check(!ended)
            var source = offset
            var remaining = length
            while (remaining > 0) {
                val n = minOf(remaining, buffer.size - used)
                bytes.copyInto(buffer, used, source, source + n)
                used += n; source += n; remaining -= n
                if (used == buffer.size) flushBlock()
            }
        }
        override fun flush() { check(!ended); flushBlock() }
        override fun close() = Unit
        fun finish() { flush(); ended = true }
        fun wipe() { buffer.fill(0); ended = true }
        private fun flushBlock() {
            if (used == 0) return
            val plain = buffer.copyOf(used)
            val encrypted = try { encrypt(plain, blockAad(aad, reference, count)) } finally { plain.fill(0) }
            try {
                check(encrypted.size == used + ENVELOPE_BYTES) { "Invalid memory segment cipher contract" }
                file.writeInt(encrypted.size); file.write(encrypted)
                total = Math.addExact(total, used.toLong()); count = Math.addExact(count, 1)
            } finally { encrypted.fill(0); buffer.fill(0); used = 0 }
        }
    }

    private class BlockInput(private val file: RandomAccessFile, private val reference: Reference,
        private val aad: ByteArray, private val decrypt: (ByteArray, ByteArray) -> ByteArray) : InputStream() {
        private var buffer = byteArrayOf()
        private var position = 0
        private var count = 0L
        private var total = 0L
        private val end = Math.addExact(reference.offset, reference.length)
        override fun read(): Int = if (ensureBlock()) buffer[position++].toInt() and 255 else -1
        override fun read(bytes: ByteArray, offset: Int, length: Int): Int {
            require(offset >= 0 && length >= 0 && offset <= bytes.size - length)
            if (length == 0) return 0
            if (!ensureBlock()) return -1
            val n = minOf(length, buffer.size - position)
            buffer.copyInto(bytes, offset, position, position + n); position += n
            return n
        }
        override fun close() = Unit
        fun wipe() { buffer.fill(0); buffer = byteArrayOf(); position = 0 }
        private fun ensureBlock(): Boolean {
            if (position < buffer.size) return true
            wipe()
            if (count == reference.blocks) {
                check(file.filePointer == end && total == reference.plaintextBytes) { "Memory segment length mismatch" }
                return false
            }
            check(end - file.filePointer >= 4) { "Missing memory segment block" }
            val size = file.readInt()
            check(size in ENVELOPE_BYTES + 1..ENVELOPE_BYTES + BLOCK_BYTES && size.toLong() <= end - file.filePointer) {
                "Invalid memory segment block length"
            }
            val encrypted = ByteArray(size)
            try {
                file.readFully(encrypted)
                buffer = decrypt(encrypted, blockAad(aad, reference, count))
            } finally { encrypted.fill(0) }
            check(buffer.size == size - ENVELOPE_BYTES) { "Invalid decrypted memory segment block" }
            total = Math.addExact(total, buffer.size.toLong()); count++
            check(total <= reference.plaintextBytes)
            return true
        }
    }

    companion object {
        const val BLOCK_BYTES = 64 * 1024
        private const val ENVELOPE_BYTES = 29
        private fun blockAad(aad: ByteArray, r: Reference, ordinal: Long): ByteArray =
            ByteBuffer.allocate(4 + aad.size + 48).putInt(aad.size).put(aad)
                .putLong(r.segment.mostSignificantBits).putLong(r.segment.leastSignificantBits)
                .putLong(r.record.mostSignificantBits).putLong(r.record.leastSignificantBits)
                .putLong(r.offset).putLong(ordinal).array()
    }
}

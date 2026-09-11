package com.galaxyssi.chat

import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.InputStream
import java.io.OutputStream
import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction
import java.util.zip.Deflater
import java.util.zip.Inflater

/** Bounded record framing inside an authenticated stream, not a whole-document JSON envelope. */
internal object BackupRecordStream {
    const val BLOCK_BYTES = 64 * 1024
    private const val RECORD = 0x52
    private const val END = 0x45
    private const val MAX_LABEL_BYTES = 4 * 1024

    class Writer(output: OutputStream) {
        private val output = DataOutputStream(output)
        private var count = 0L
        private var finished = false
        private var writing = false
        private var failed = false

        fun record(section: String, key: String, write: (OutputStream) -> Unit) {
            check(!finished && !writing && !failed) { "Backup writer is not ready" }
            val sectionBytes = label(section)
            val keyBytes = label(key)
            writing = true
            val blocks = BlockOutput(output)
            try {
                output.writeByte(RECORD)
                output.writeInt(sectionBytes.size); output.write(sectionBytes)
                output.writeInt(keyBytes.size); output.write(keyBytes)
                write(blocks)
                blocks.finish()
                count = Math.addExact(count, 1)
            } catch (failure: Throwable) {
                failed = true
                throw failure
            } finally { blocks.wipe(); writing = false }
        }

        fun finish(): Long {
            check(!finished && !writing && !failed) { "Backup writer cannot be finalized" }
            output.writeByte(END); output.writeLong(count); output.flush()
            finished = true
            return count
        }
    }

    fun read(input: InputStream, visit: (section: String, key: String, payload: InputStream) -> Unit): Long {
        val source = DataInputStream(input)
        var count = 0L
        while (true) {
            when (source.readUnsignedByte()) {
                END -> {
                    check(source.readLong() == count) { "Backup record count mismatch" }
                    check(source.read() == -1) { "Unexpected data after backup footer" }
                    return count
                }
                RECORD -> {
                    val section = readLabel(source)
                    val key = readLabel(source)
                    val blocks = BlockInput(source)
                    try {
                        visit(section, key, blocks)
                        check(blocks.read() == -1) { "Backup record was not fully consumed" }
                    } finally { blocks.wipe() }
                    count = Math.addExact(count, 1)
                }
                else -> error("Invalid backup record marker")
            }
        }
    }

    private fun label(value: String): ByteArray = value.toByteArray(Charsets.UTF_8).also {
        require(value.isNotEmpty() && it.size <= MAX_LABEL_BYTES && decode(it) == value) { "Invalid backup record label" }
    }

    private fun readLabel(input: DataInputStream): String {
        val size = input.readInt()
        require(size in 1..MAX_LABEL_BYTES) { "Invalid backup record label length" }
        return decode(ByteArray(size).also(input::readFully))
    }

    private fun decode(bytes: ByteArray): String = Charsets.UTF_8.newDecoder()
        .onMalformedInput(CodingErrorAction.REPORT).onUnmappableCharacter(CodingErrorAction.REPORT)
        .decode(ByteBuffer.wrap(bytes)).toString()

    private class BlockOutput(private val output: DataOutputStream) : OutputStream() {
        private val buffer = ByteArray(BLOCK_BYTES)
        private val compressed = ByteArray(BLOCK_BYTES)
        private var used = 0
        private var ended = false
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
        override fun flush() { check(!ended); flushBlock(); output.flush() }
        override fun close() { if (!ended) flush() }
        fun finish() { check(!ended); flushBlock(); output.writeInt(0); ended = true }
        fun wipe() { buffer.fill(0); compressed.fill(0); ended = true }
        private fun flushBlock() {
            if (used == 0) return
            val deflater = Deflater(Deflater.BEST_SPEED)
            try {
                deflater.setInput(buffer, 0, used); deflater.finish()
                val size = deflater.deflate(compressed)
                val compress = deflater.finished() && size in 1 until used
                output.writeInt(used)
                output.writeInt(if (compress) size else used)
                output.write(if (compress) compressed else buffer, 0, if (compress) size else used)
            } finally { deflater.end(); buffer.fill(0); compressed.fill(0); used = 0 }
        }
    }

    private class BlockInput(private val input: DataInputStream) : InputStream() {
        private val buffer = ByteArray(BLOCK_BYTES)
        private val compressed = ByteArray(BLOCK_BYTES)
        private var position = 0
        private var size = 0
        private var ended = false
        override fun read(): Int = if (ensureBlock()) buffer[position++].toInt() and 255 else -1
        override fun read(bytes: ByteArray, offset: Int, length: Int): Int {
            require(offset >= 0 && length >= 0 && offset <= bytes.size - length)
            if (length == 0) return 0
            if (!ensureBlock()) return -1
            val count = minOf(length, size - position)
            buffer.copyInto(bytes, offset, position, position + count)
            position += count
            return count
        }
        // The enclosing reader owns the stream and must validate record EOF after the visitor returns.
        override fun close() = Unit
        fun wipe() { buffer.fill(0); compressed.fill(0); ended = true }
        private fun ensureBlock(): Boolean {
            if (position < size) return true
            if (ended) return false
            buffer.fill(0); compressed.fill(0)
            size = input.readInt(); position = 0
            if (size == 0) { ended = true; return false }
            require(size in 1..BLOCK_BYTES) { "Invalid backup block size" }
            val encodedSize = input.readInt()
            require(encodedSize in 1..size) { "Invalid encoded backup block size" }
            if (encodedSize == size) input.readFully(buffer, 0, size)
            else {
                input.readFully(compressed, 0, encodedSize)
                val inflater = Inflater()
                try {
                    inflater.setInput(compressed, 0, encodedSize)
                    val actual = inflater.inflate(buffer, 0, size)
                    check(actual == size && inflater.finished() && inflater.remaining == 0) { "Invalid compressed backup block" }
                } finally { inflater.end() }
            }
            return true
        }
    }
}

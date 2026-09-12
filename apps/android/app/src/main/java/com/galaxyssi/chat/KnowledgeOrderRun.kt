package com.galaxyssi.chat

import java.io.Closeable
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.InputStream
import java.io.OutputStream

internal data class KnowledgeOrderKey(val chunk: Int, val id: String) : Comparable<KnowledgeOrderKey> {
    override fun compareTo(other: KnowledgeOrderKey): Int = chunk.compareTo(other.chunk).takeIf { it != 0 }
        ?: id.compareTo(other.id)
    val estimatedBytes: Long get() = 64L + id.length.toLong() * 2
}

internal object KnowledgeOrderRun {
    private const val MAGIC = 0x4b4f5231
    class Writer(output: OutputStream) : Closeable {
        private val data = DataOutputStream(output.buffered(8192))
        private var count = 0L
        private var previous: KnowledgeOrderKey? = null
        init { data.writeInt(MAGIC) }
        fun add(key: KnowledgeOrderKey) {
            check(previous == null || previous!! < key) { "Duplicate or unordered source identity" }
            data.writeByte(1)
            data.writeInt(key.chunk)
            data.writeInt(key.id.length)
            // Preserve String's UTF-16 ordering, including surrogate code units.
            data.writeChars(key.id)
            previous = key
            count = Math.addExact(count, 1)
        }
        override fun close() { try { data.writeByte(0); data.writeLong(count) } finally { data.close() } }
    }
    class Reader(input: InputStream) : Closeable {
        private val data = DataInputStream(input.buffered(8192))
        private var count = 0L
        private var previous: KnowledgeOrderKey? = null
        private var finished = false
        init { try { check(data.readInt() == MAGIC) } catch (failure: Throwable) { data.close(); throw failure } }
        fun next(): KnowledgeOrderKey? {
            if (finished) return null
            when (data.readUnsignedByte()) {
                0 -> {
                    check(data.readLong() == count) { "Source ordering count mismatch" }
                    check(data.read() == -1) { "Trailing source ordering bytes" }
                    finished = true
                    return null
                }
                1 -> Unit
                else -> error("Invalid source ordering record")
            }
            val chunk = data.readInt()
            val size = data.readInt()
            require(size >= 0) { "Invalid source identity length" }
            // Do not allocate from an untrusted length before reading authenticated segments.
            val id = StringBuilder(minOf(size, 4096))
            repeat(size) { id.append(data.readChar()) }
            val key = KnowledgeOrderKey(chunk, id.toString())
            check(previous == null || previous!! < key) { "Duplicate or unordered source identity" }
            previous = key
            count = Math.addExact(count, 1)
            return key
        }
        override fun close() = data.close()
    }
}

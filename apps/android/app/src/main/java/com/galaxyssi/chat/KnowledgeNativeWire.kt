package com.galaxyssi.chat

import java.nio.ByteBuffer
import java.nio.ByteOrder

internal data class KnowledgeNativeEvent(val sequence: Long, val previous: Long, val key: String,
    val revision: String, val chunks: Long, val removed: Boolean)
internal data class KnowledgeNativePending(val event: KnowledgeNativeEvent, val next: Long)
internal data class KnowledgeNativeCheckpoint(val epoch: String, val last: KnowledgeNativeEvent?, val pending: KnowledgeNativePending?) {
    val sequence: Long get() = last?.sequence ?: 0
}

/** Bounded binary records shared with memory-native/replay/format.rs. No corpus JSON. */
internal object KnowledgeNativeWire {
    fun event(event: KnowledgeNativeEvent): ByteArray = ByteBuffer.allocate(93).order(ByteOrder.LITTLE_ENDIAN).apply {
        check(event.sequence > event.previous && event.previous >= 0 && event.chunks >= 0)
        put("GSE1".toByteArray(Charsets.US_ASCII)); putLong(event.sequence); putLong(event.previous)
        put(hex(event.key, 32)); put(hex(event.revision, 32)); putLong(event.chunks); put(if (event.removed) 1.toByte() else 0)
    }.array()

    fun checkpoint(bytes: ByteArray): KnowledgeNativeCheckpoint = consuming(bytes, 22, 208) { input ->
        input.magic("GSC1")
        val epoch = input.hash(16)
        val last = if (input.flag()) input.event() else null
        val pending = if (input.flag()) KnowledgeNativePending(input.event(), input.nonnegative()) else null
        KnowledgeNativeCheckpoint(epoch, last, pending).also { result ->
            if (pending != null) check(!pending.event.removed && pending.event.previous == result.sequence && pending.next < pending.event.chunks)
        }
    }

    fun matches(bytes: ByteArray): List<KnowledgeVectorMatch> = consuming(bytes, 8, 8 + 256 * 104) { input ->
        input.magic("GSM1")
        val count = input.int
        check(count in 0..256 && input.remaining() == count * 104)
        List(count) {
            input.magic("GSN1")
            val key = input.hash(32); val revision = input.hash(32)
            check(input.nonnegative() > 0)
            input.nonnegative() // Ordinal is verified natively; source offsets are validated again before text release.
            val start = input.nonnegative(); val end = input.nonnegative()
            val similarity = input.float.toDouble()
            check(start < end && end <= Int.MAX_VALUE && similarity.isFinite() && similarity in -1.0..1.0)
            KnowledgeVectorMatch(key, revision, start.toInt(), end.toInt(), similarity)
        }
    }

    fun hex(text: String, size: Int): ByteArray {
        require(text.length == size * 2 && text.all { it in '0'..'9' || it in 'a'..'f' })
        return ByteArray(size) { ((text[it * 2].digitToInt(16) shl 4) or text[it * 2 + 1].digitToInt(16)).toByte() }
    }
    private inline fun <T> consuming(bytes: ByteArray, min: Int, max: Int, body: (ByteBuffer) -> T): T = try {
        check(bytes.size in min..max)
        val input = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)
        body(input).also { check(!input.hasRemaining()) }
    } finally { bytes.fill(0) }
    private fun ByteBuffer.magic(text: String) { check(remaining() >= text.length); text.forEach { check(get().toInt() == it.code) } }
    private fun ByteBuffer.hash(size: Int): String {
        check(remaining() >= size)
        val chars = CharArray(size * 2)
        repeat(size) { val byte = get().toInt() and 255; chars[it * 2] = HEX[byte ushr 4]; chars[it * 2 + 1] = HEX[byte and 15] }
        return String(chars)
    }
    private fun ByteBuffer.flag(): Boolean = when (get().toInt()) { 0 -> false; 1 -> true; else -> error("Invalid native flag") }
    private fun ByteBuffer.nonnegative(): Long = long.also { check(it >= 0) }
    private fun ByteBuffer.event() = KnowledgeNativeEvent(nonnegative(), nonnegative(), hash(32), hash(32), nonnegative(), flag()).also {
        check(it.sequence > it.previous)
    }
    private const val HEX = "0123456789abcdef"
}

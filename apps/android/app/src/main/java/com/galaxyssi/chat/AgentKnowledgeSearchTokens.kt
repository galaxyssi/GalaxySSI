package com.galaxyssi.chat

import java.io.Closeable
import java.text.Normalizer
import java.util.Locale
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

/** FTS sees only domain-separated keyed tokens, never plaintext words. */
internal class AgentKnowledgeSearchTokens(private val secret: ByteArray) : Closeable {
    private val mac = Mac.getInstance("HmacSHA256").apply { init(SecretKeySpec(secret, "HmacSHA256")) }
    fun encode(value: String): String = terms(value).distinct().joinToString(" ", transform = ::hash)
    fun query(value: String): String = terms(value).distinct().take(64).joinToString(" OR ") { "\"${hash(it)}\"" }
    private fun hash(value: String): String {
        val bytes = mac.doFinal(value.toByteArray(Charsets.UTF_8))
        return CharArray(bytes.size * 2) { index ->
            HEX[(bytes[index / 2].toInt() ushr (if (index % 2 == 0) 4 else 0)) and 15]
        }.concatToString().also { bytes.fill(0) }
    }
    override fun close() { secret.fill(0) }
    companion object {
        private const val HEX = "0123456789abcdef"
        private val words = Regex("\\p{IsHan}+|[\\p{L}\\p{N}&&[^\\p{IsHan}]]+")
        internal fun terms(value: String): Sequence<String> = sequence {
            val normalized = Normalizer.normalize(value, Normalizer.Form.NFKC).lowercase(Locale.ROOT)
            words.findAll(normalized).forEach { match ->
                val word = match.value
                if (word.length <= 128) yield("w:$word")
                val points = word.codePoints().toArray()
                if (points.any { Character.UnicodeScript.of(it) == Character.UnicodeScript.HAN }) {
                    points.forEach { yield("c:" + String(Character.toChars(it))) }
                    for (index in 0 until points.size - 1) yield("b:" + codePoints(points, index, 2))
                } else {
                    for (index in 0 until points.size - 2) yield("t:" + codePoints(points, index, 3))
                }
            }
        }
        private fun codePoints(points: IntArray, offset: Int, count: Int): String = buildString {
            for (index in offset until offset + count) appendCodePoint(points[index])
        }
    }
}

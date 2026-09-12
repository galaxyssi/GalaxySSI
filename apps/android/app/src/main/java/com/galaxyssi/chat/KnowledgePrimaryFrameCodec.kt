package com.galaxyssi.chat

import android.util.Base64
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.util.zip.GZIPInputStream
import java.util.zip.GZIPOutputStream

/** Compression and decryption are bounded by one frame, never by corpus size. */
internal object KnowledgePrimaryFrameCodec {
    const val CHARS = 16 * 1024
    private const val MAX_BYTES = CHARS * 4

    fun compress(text: String): String {
        require(text.length in 1..CHARS)
        val plain = text.toByteArray(Charsets.UTF_8)
        val output = object : ByteArrayOutputStream() { fun wipe() { buf.fill(0); reset() } }
        try {
            GZIPOutputStream(output).use { it.write(plain) }
            val bytes = output.toByteArray()
            return try { Base64.encodeToString(bytes, Base64.NO_WRAP) } finally { bytes.fill(0) }
        } finally { plain.fill(0); output.wipe() }
    }

    fun decompress(value: String): String {
        require(value.length <= (MAX_BYTES + 1024) * 2) { "Primary frame is oversized" }
        val compressed = Base64.decode(value, Base64.NO_WRAP)
        val output = ByteArray(MAX_BYTES + 1)
        try {
            var count = 0
            GZIPInputStream(ByteArrayInputStream(compressed)).use { input ->
                while (count < output.size) {
                    val read = input.read(output, count, output.size - count)
                    if (read < 0) break
                    check(read > 0)
                    count += read
                }
            }
            require(count in 1..MAX_BYTES) { "Primary frame expansion is oversized" }
            return Charsets.UTF_8.newDecoder().onMalformedInput(java.nio.charset.CodingErrorAction.REPORT)
                .decode(java.nio.ByteBuffer.wrap(output, 0, count)).toString().also { require(it.length <= CHARS) }
        } finally { compressed.fill(0); output.fill(0) }
    }
}

package com.galaxyssi.chat

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.nio.ByteBuffer
import java.nio.ByteOrder

class LocalWhisperAsrAudioBytesTest {
    @Test
    fun inMemoryWaveDecodeWipesEncodedInput() {
        val expected = shortArrayOf(-12_000, 0, 12_000, 4_000)
        val encoded = pcm16Wave(expected)

        val decoded = LocalWhisperAsr.decodeAudioBytesToPcm16(encoded, "wav")

        assertArrayEquals(expected, decoded)
        assertTrue(encoded.all { it == 0.toByte() })
    }

    private fun pcm16Wave(samples: ShortArray): ByteArray {
        val dataBytes = samples.size * 2
        return ByteBuffer.allocate(44 + dataBytes).order(ByteOrder.LITTLE_ENDIAN).apply {
            put("RIFF".toByteArray(Charsets.US_ASCII))
            putInt(36 + dataBytes)
            put("WAVE".toByteArray(Charsets.US_ASCII))
            put("fmt ".toByteArray(Charsets.US_ASCII))
            putInt(16)
            putShort(1.toShort())
            putShort(1.toShort())
            putInt(16_000)
            putInt(32_000)
            putShort(2.toShort())
            putShort(16.toShort())
            put("data".toByteArray(Charsets.US_ASCII))
            putInt(dataBytes)
            samples.forEach { putShort(it) }
        }.array()
    }
}

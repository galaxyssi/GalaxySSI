package com.galaxyssi.glasses

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test
import java.nio.ByteBuffer
import java.nio.ByteOrder

class CloudSpeechClientTest {
    @Test fun encodesPcmAsCanonicalMono16kWav() {
        val bytes = CloudSpeechClient.wav(shortArrayOf(1, -2, 32767) + ShortArray(1597))
        val view = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)
        assertEquals("RIFF", String(bytes, 0, 4))
        assertEquals("WAVE", String(bytes, 8, 4))
        assertEquals(1, view.getShort(22).toInt())
        assertEquals(16000, view.getInt(24))
        assertEquals(16, view.getShort(34).toInt())
        assertEquals(3200, view.getInt(40))
        assertEquals(1, view.getShort(44).toInt())
        assertEquals(-2, view.getShort(46).toInt())
    }

    @Test fun rejectsInsecureOrMismatchedProxyConfiguration() {
        val token = "0123456789abcdef0123456789abcdef"
        AsrProxyConfig("https://speech.example/transcribe", token).validated()
        assertThrows(IllegalArgumentException::class.java) {
            AsrProxyConfig("http://speech.example/transcribe", token).validated()
        }
        assertThrows(IllegalArgumentException::class.java) {
            AsrProxyConfig("https://speech.example/chat/completions", token).validated()
        }
        assertThrows(IllegalArgumentException::class.java) {
            AsrProxyConfig("https://speech.example/transcribe", "short").validated()
        }
    }
}

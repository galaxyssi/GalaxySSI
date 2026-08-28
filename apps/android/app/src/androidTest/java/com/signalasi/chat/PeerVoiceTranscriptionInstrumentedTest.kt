package com.signalasi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import com.signalasi.chat.voice.audio.PeerVoiceMessageAudio
import com.signalasi.chat.voice.audio.PeerVoiceOpusEncoder
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import kotlin.math.PI
import kotlin.math.sin

@RunWith(AndroidJUnit4::class)
class PeerVoiceTranscriptionInstrumentedTest {
    @Test
    fun encodedContactVoiceDecodesFromMemoryAndWipesSource() {
        val samples = ShortArray(PeerVoiceMessageAudio.SAMPLE_RATE_HZ / 2) { index ->
            (sin(2.0 * PI * 440.0 * index / PeerVoiceMessageAudio.SAMPLE_RATE_HZ) * 8_000.0).toInt().toShort()
        }
        val encoded = PeerVoiceOpusEncoder.encode(samples, samples.size)

        val decoded = LocalWhisperAsr.decodeAudioBytesToPcm16(encoded, "opus")

        assertTrue(decoded.isNotEmpty())
        assertTrue(decoded.size in 7_000..9_000)
        assertTrue(encoded.all { it == 0.toByte() })
        samples.wipeSensitive()
        decoded.wipeSensitive()
    }
}

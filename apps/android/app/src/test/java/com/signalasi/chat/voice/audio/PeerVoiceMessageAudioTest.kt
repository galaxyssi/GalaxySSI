package com.signalasi.chat.voice.audio

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.PI
import kotlin.math.sin
import kotlin.math.sqrt

class PeerVoiceMessageAudioTest {
    @Test
    fun peerCaptureUsesFixedFullbandOpusProfile() {
        assertEquals(48_000, PeerVoiceMessageAudio.SAMPLE_RATE_HZ)
        assertEquals(1, PeerVoiceMessageAudio.CHANNEL_COUNT)
        assertEquals(48_000, PeerVoiceMessageAudio.OPUS_BIT_RATE_BPS)
        assertEquals(75, PeerVoiceMessageAudio.HIGH_PASS_HZ)
        assertEquals(-18.0, PeerVoiceMessageAudio.TARGET_LUFS, 0.0)
        assertEquals(-1.0, PeerVoiceMessageAudio.PEAK_DBFS, 0.0)
    }

    @Test
    fun onlyPersonContactVoiceMessagesUseDedicatedCapture() {
        assertTrue(PeerVoiceMessageAudio.shouldUseDedicatedCapture("chat_message", true))
        assertFalse(PeerVoiceMessageAudio.shouldUseDedicatedCapture("chat_message", false))
        assertFalse(PeerVoiceMessageAudio.shouldUseDedicatedCapture("agent_input", true))
        assertFalse(PeerVoiceMessageAudio.shouldUseDedicatedCapture("voice_wakeup", true))
    }

    @Test
    fun asrCaptureRetainsWhisperSampleRate() {
        assertEquals(16_000, PcmCaptureConfig().sampleRateHz)
    }

    @Test
    fun highPassAttenuatesSubSpeechRumble() {
        val low = tone(30.0, 0.5, 0.5)
        val speech = tone(1_000.0, 0.5, 0.5)

        PeerVoiceDsp.applyHighPass(low, low.size, PeerVoiceMessageAudio.HIGH_PASS_HZ.toDouble())
        PeerVoiceDsp.applyHighPass(speech, speech.size, PeerVoiceMessageAudio.HIGH_PASS_HZ.toDouble())

        assertTrue(rms(low) < rms(speech) * 0.55)
    }

    @Test
    fun loudnessNormalizationRespectsTargetAndPeakLimit() {
        val samples = tone(1_000.0, 1.0, 0.03)

        val result = PeerVoiceDsp.processInPlace(samples, samples.size)
        val normalizedLufs = PeerVoiceDsp.integratedLufs(samples, samples.size)

        assertTrue(result.appliedGainDb > 0.0)
        assertTrue(normalizedLufs != null && normalizedLufs in -19.0..-17.0)
        assertTrue(result.outputPeakDbfs <= PeerVoiceMessageAudio.PEAK_DBFS + 0.05)
    }

    @Test
    fun oggWriterBuildsOpusContainer() {
        val encoded = OggOpusWriter.write(
            packets = listOf(OpusPacket(byteArrayOf(1, 2, 3)), OpusPacket(byteArrayOf(4, 5))),
            inputSampleCount = 1_920,
            codecHead = null
        )

        assertTrue(encoded.startsWithAscii("OggS"))
        assertTrue(encoded.containsAscii("OpusHead"))
        assertTrue(encoded.containsAscii("OpusTags"))
    }

    private fun tone(frequencyHz: Double, seconds: Double, amplitude: Double): ShortArray =
        ShortArray((PeerVoiceMessageAudio.SAMPLE_RATE_HZ * seconds).toInt()) { index ->
            (sin(2.0 * PI * frequencyHz * index / PeerVoiceMessageAudio.SAMPLE_RATE_HZ) *
                Short.MAX_VALUE * amplitude).toInt().toShort()
        }

    private fun rms(samples: ShortArray): Double = sqrt(
        samples.fold(0.0) { sum, sample ->
            val normalized = sample / Short.MAX_VALUE.toDouble()
            sum + normalized * normalized
        } / samples.size
    )

    private fun ByteArray.startsWithAscii(value: String): Boolean =
        value.toByteArray(Charsets.US_ASCII).indices.all { index -> this[index] == value[index].code.toByte() }

    private fun ByteArray.containsAscii(value: String): Boolean {
        val target = value.toByteArray(Charsets.US_ASCII)
        return indices.any { start ->
            start + target.size <= size && target.indices.all { offset -> this[start + offset] == target[offset] }
        }
    }
}

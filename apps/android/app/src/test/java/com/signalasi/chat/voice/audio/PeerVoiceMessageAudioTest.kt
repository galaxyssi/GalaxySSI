package com.signalasi.chat.voice.audio

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PeerVoiceMessageAudioTest {
    @Test
    fun peerCaptureUsesFixedHighQualityStereoProfile() {
        assertEquals(48_000, PeerVoiceMessageAudio.SAMPLE_RATE_HZ)
        assertEquals(2, PeerVoiceMessageAudio.CHANNEL_COUNT)
        assertEquals(128_000, PeerVoiceMessageAudio.AAC_BIT_RATE_BPS)
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
    fun gentleToneKeepsSpeechBodyAndSoftensTreble() {
        assertTrue(PeerVoiceMessageAudio.gentleGainMillibels(400) > 0)
        assertTrue(PeerVoiceMessageAudio.gentleGainMillibels(10_000) < 0)
        assertTrue(
            PeerVoiceMessageAudio.gentleGainMillibels(400) >
                PeerVoiceMessageAudio.gentleGainMillibels(10_000)
        )
    }
}

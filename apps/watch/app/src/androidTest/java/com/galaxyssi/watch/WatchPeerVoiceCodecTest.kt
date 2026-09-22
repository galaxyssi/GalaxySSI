package com.galaxyssi.watch

import com.galaxyssi.chat.voice.audio.PeerVoiceOpusEncoder
import org.junit.Assert.*
import org.junit.Test

class WatchPeerVoiceCodecTest {
    /** Synthetic PCM: verifies watch codec support without opening the microphone. */
    @Test fun encodesAndroidCompatibleOggOpus() {
        assertTrue("Watch must provide Opus encoding", PeerVoiceOpusEncoder.isAvailable())
        val pcm = ShortArray(48_000) { (kotlin.math.sin(it * 2.0 * Math.PI * 440 / 48_000) * 4000).toInt().toShort() }
        val bytes = PeerVoiceOpusEncoder.encode(pcm, pcm.size)
        assertEquals("OggS", bytes.copyOfRange(0, 4).toString(Charsets.US_ASCII))
        assertTrue(bytes.size in 100..30_000)
        pcm.fill(0); bytes.fill(0)
    }
}

package com.galaxyssi.chat.voice.asr.online

import com.galaxyssi.chat.voice.asr.AsrAudioFrame
import com.galaxyssi.chat.voice.asr.AsrEvent
import com.galaxyssi.chat.voice.asr.AsrNetworkType
import com.galaxyssi.chat.voice.asr.AsrPrivacyPolicy
import com.galaxyssi.chat.voice.asr.AsrSessionConfig
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class RealtimeAsrProtocolTest {
    @Test
    fun twentyMillisecondFramesBecomeBoundedSixtyMillisecondBatches() {
        val batcher = RealtimePcmBatcher(targetBatchMs = 60)

        assertTrue(batcher.offer(frame(1)).isEmpty())
        assertTrue(batcher.offer(frame(2)).isEmpty())
        val batch = batcher.offer(frame(3)).single()

        assertEquals(1L, batch.firstSequence)
        assertEquals(3L, batch.lastSequence)
        assertEquals(960, batch.samples.size)
        assertEquals(60L, batch.durationMs)
        val decoded = SignalAsrRealtimeProtocol.decodeAudio(SignalAsrRealtimeProtocol.encodeAudio(batch))
        assertEquals(batch.firstSequence, decoded.firstSequence)
        assertEquals(batch.lastSequence, decoded.lastSequence)
        assertEquals(batch.firstCaptureTimeNanos, decoded.firstCaptureTimeNanos)
        assertEquals(batch.lastCaptureTimeNanos, decoded.lastCaptureTimeNanos)
        assertEquals(batch.sampleRateHz, decoded.sampleRateHz)
        assertTrue(batch.samples.contentEquals(decoded.samples))
    }

    @Test
    fun sequenceGapFlushesExistingAudioBeforeStartingNewBatch() {
        val batcher = RealtimePcmBatcher(targetBatchMs = 60)
        batcher.offer(frame(1))
        val flushed = batcher.offer(frame(4)).single()

        assertEquals(1L, flushed.firstSequence)
        assertEquals(1L, flushed.lastSequence)
        assertEquals(4L, batcher.flush()?.firstSequence)
    }

    @Test
    fun providerEventsNormalizeWithoutLoggingOrEmbeddingCredentials() {
        val credential = credential()
        val final = SignalAsrRealtimeProtocol.parseServerEvent(
            """{"event_type":"transcript.final","revision":7,"text":"hello","language":"en"}""",
            config(),
            credential
        ) as AsrEvent.Final

        assertEquals("transcript-1", final.hypothesis.transcriptId)
        assertEquals(7, final.hypothesis.revision)
        assertEquals("hello", final.hypothesis.text)
        assertTrue(final.hypothesis.isFinal)
        assertFalse(credential.toString().contains("temporary-secret"))
        credential.close()
    }

    private fun frame(sequence: Long) = AsrAudioFrame(
        sequence = sequence,
        captureTimeNanos = sequence * 20_000_000L,
        samples = ShortArray(320) { sequence.toShort() }
    )

    private fun config() = AsrSessionConfig(
        voiceSessionId = "voice-1",
        transcriptId = "transcript-1",
        networkType = AsrNetworkType.WIFI,
        privacy = AsrPrivacyPolicy(allowOnlineVoice = true, allowRawAudioUpload = true)
    )

    private fun credential() = EphemeralAsrCredential(
        providerId = "provider",
        providerSessionId = "provider-session",
        websocketUrl = "ws://127.0.0.1/realtime",
        authorizationToken = "temporary-secret",
        expiresAtEpochMs = System.currentTimeMillis() + 60_000L
    )
}

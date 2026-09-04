package com.galaxyssi.chat.voice.asr.local

import com.galaxyssi.chat.voice.audio.PcmSnapshot
import com.galaxyssi.chat.voice.model.WhisperModelCatalog
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.concurrent.atomic.AtomicLong

class LiveWhisperTranscriptionSessionTest {
    @Test
    fun partialsRemainProvisionalAndFinalCanOnlyBeRequestedOnce() = runBlocking {
        val clock = AtomicLong(1_000L)
        val updates = mutableListOf<LiveWhisperTranscriptUpdate>()
        var finalRuns = 0
        val updateSignal = CompletableDeferred<Unit>()
        val scheduler = object : WhisperDecodeScheduler {
            override suspend fun submit(request: ScheduledWhisperDecode): ScheduledWhisperResult {
                if (request.isFinal) finalRuns += 1
                return ScheduledWhisperResult.Completed(
                    request,
                    nativeResult(if (request.isFinal) "hello world" else "hello")
                )
            }

            override fun cancelSession(sessionId: String) = Unit
            override fun queueSnapshot() = DecodeQueueSnapshot()
            override fun close() = Unit
        }
        val session = LiveWhisperTranscriptionSession(
            voiceSessionId = "voice-1",
            profile = WhisperModelCatalog.require("tiny"),
            language = "en",
            scheduler = scheduler,
            scope = this,
            elapsedRealtime = clock::get,
            onUpdate = {
                updates += it
                updateSignal.complete(Unit)
            }
        )
        try {
            assertEquals(WhisperModelCatalog.require("tiny").maxWindowMs, session.nextPartialWindowMs(1_000L))
            session.offerPartial(snapshot(16_000))
            updateSignal.await()
            clock.set(2_000L)
            assertTrue(session.nextPartialWindowMs(2_000L) != null)
            session.offerPartial(snapshot(32_000))
            kotlinx.coroutines.yield()

            val final = session.finish(snapshot(32_000))

            assertEquals("hello world", final.text)
            assertEquals(1, finalRuns)
            assertTrue(updates.any { !it.transcript.final })
            assertTrue(updates.last().transcript.final)
            assertFalse(updates.last().transcript.unstableText.isNotBlank())
            val duplicate = runCatching { session.finish(snapshot(32_000)) }
            assertTrue(duplicate.exceptionOrNull() is IllegalStateException)
            assertEquals(1, finalRuns)
        } finally {
            session.close()
        }
    }

    private fun snapshot(sampleCount: Int) = PcmSnapshot(
        samples = ShortArray(sampleCount) { 10 },
        sampleRateHz = 16_000,
        speechDetected = true,
        speechStartSample = 0L,
        speechEndSampleExclusive = sampleCount.toLong(),
        captureStartSample = 0L,
        captureEndSampleExclusive = sampleCount.toLong()
    )

    private fun nativeResult(text: String) = NativeWhisperResult(
        codeValue = NativeWhisperCode.OK.wireValue,
        segments = arrayOf(NativeWhisperSegment(0L, 700L, text, -0.1f, 0.0f)),
        detectedLanguage = "en",
        timings = NativeWhisperTimings(1.0, 2.0, 3.0, 50.0, 1_000L, 0.05),
        aborted = false,
        message = null
    )
}

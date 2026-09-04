package com.galaxyssi.chat.voice.asr.local

import com.galaxyssi.chat.voice.model.WhisperExecutionMode
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class WhisperFinalAudioChunkerTest {
    @Test
    fun shortFinalAudioUsesOneDecodeWithoutAddedLatency() {
        val chunks = WhisperFinalAudioChunker.plan(
            sampleCount = 10 * SAMPLE_RATE,
            sampleRateHz = SAMPLE_RATE,
            mode = WhisperExecutionMode.FINAL_ONLY
        )

        assertEquals(listOf(WhisperPcmChunk(0, 10 * SAMPLE_RATE)), chunks)
    }

    @Test
    fun longFinalAudioIsFullyCoveredWithOverlap() {
        val total = 60 * SAMPLE_RATE
        val chunks = WhisperFinalAudioChunker.plan(
            sampleCount = total,
            sampleRateHz = SAMPLE_RATE,
            mode = WhisperExecutionMode.FINAL_ONLY
        )

        assertTrue(chunks.size >= 3)
        assertEquals(0, chunks.first().offset)
        assertEquals(total, chunks.last().endExclusive)
        chunks.zipWithNext().forEach { (left, right) ->
            assertTrue(right.offset < left.endExclusive)
            assertTrue(right.offset <= left.endExclusive)
        }
    }

    @Test
    fun partialAudioNeverFansOutIntoMultipleDecodes() {
        val chunks = WhisperFinalAudioChunker.plan(
            sampleCount = 60 * SAMPLE_RATE,
            sampleRateHz = SAMPLE_RATE,
            mode = WhisperExecutionMode.REALTIME_PARTIAL
        )

        assertEquals(1, chunks.size)
        assertEquals(60 * SAMPLE_RATE, chunks.single().length)
    }

    @Test
    fun chunkResultsMergeOverlapAndPreserveTotalTiming() {
        val first = WhisperPcmChunk(0, 26 * SAMPLE_RATE)
        val second = WhisperPcmChunk(24 * SAMPLE_RATE, 6 * SAMPLE_RATE)
        val result = WhisperFinalResultAssembler.assemble(
            chunks = listOf(
                first to result("hello shared", 26_000L, 300.0),
                second to result("shared world", 6_000L, 100.0)
            ),
            totalSamples = 30 * SAMPLE_RATE,
            sampleRateHz = SAMPLE_RATE
        )

        assertEquals("hello shared world", result.text)
        assertEquals(30_000L, result.timings.audioMs)
        assertEquals(400.0, result.timings.totalMs, 0.001)
        assertEquals(30_000L, result.segments.single().endMs)
    }

    private fun result(text: String, audioMs: Long, totalMs: Double) = NativeWhisperResult(
        codeValue = NativeWhisperCode.OK.wireValue,
        segments = arrayOf(NativeWhisperSegment(0L, audioMs, text, -0.1f, 0.01f)),
        detectedLanguage = "en",
        timings = NativeWhisperTimings(0.0, totalMs / 2, totalMs / 2, totalMs, audioMs, totalMs / audioMs),
        aborted = false,
        message = null
    )

    private companion object {
        const val SAMPLE_RATE = 16_000
    }
}

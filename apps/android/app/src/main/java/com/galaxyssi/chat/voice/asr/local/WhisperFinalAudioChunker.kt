package com.galaxyssi.chat.voice.asr.local

import com.galaxyssi.chat.voice.model.WhisperExecutionMode

internal data class WhisperPcmChunk(
    val offset: Int,
    val length: Int
) {
    val endExclusive: Int
        get() = offset + length
}

internal object WhisperFinalAudioChunker {
    fun plan(
        sampleCount: Int,
        sampleRateHz: Int,
        mode: WhisperExecutionMode,
        maximumChunkMs: Long = MAXIMUM_CHUNK_MS,
        overlapMs: Long = OVERLAP_MS
    ): List<WhisperPcmChunk> {
        require(sampleCount > 0)
        require(sampleRateHz > 0)
        require(maximumChunkMs > 0L)
        require(overlapMs >= 0L && overlapMs < maximumChunkMs)
        if (mode != WhisperExecutionMode.FINAL_ONLY) {
            return listOf(WhisperPcmChunk(0, sampleCount))
        }

        val maximumSamples = millisecondsToSamples(maximumChunkMs, sampleRateHz)
        if (sampleCount <= maximumSamples) {
            return listOf(WhisperPcmChunk(0, sampleCount))
        }
        val overlapSamples = millisecondsToSamples(overlapMs, sampleRateHz)
        val advanceSamples = (maximumSamples - overlapSamples).coerceAtLeast(1)
        return buildList {
            var offset = 0
            while (offset < sampleCount) {
                val length = minOf(maximumSamples, sampleCount - offset)
                add(WhisperPcmChunk(offset, length))
                if (offset + length >= sampleCount) break
                offset += advanceSamples
            }
        }
    }

    private fun millisecondsToSamples(milliseconds: Long, sampleRateHz: Int): Int =
        (milliseconds * sampleRateHz / 1_000L).coerceIn(1L, Int.MAX_VALUE.toLong()).toInt()

    private const val MAXIMUM_CHUNK_MS = 26_000L
    private const val OVERLAP_MS = 1_500L
}

internal object WhisperFinalResultAssembler {
    fun assemble(
        chunks: List<Pair<WhisperPcmChunk, NativeWhisperResult>>,
        totalSamples: Int,
        sampleRateHz: Int
    ): NativeWhisperResult {
        require(chunks.isNotEmpty())
        require(totalSamples > 0 && sampleRateHz > 0)
        chunks.firstOrNull { !it.second.successful }?.second?.let { return it }

        val transcript = WhisperTranscriptAssembler()
        chunks.forEach { (_, result) -> transcript.append(result.text) }
        val text = transcript.value()
        val totalAudioMs = totalSamples.toLong() * 1_000L / sampleRateHz
        val timings = NativeWhisperTimings(
            sampleMs = chunks.sumOf { it.second.timings.sampleMs },
            encodeMs = chunks.sumOf { it.second.timings.encodeMs },
            decodeMs = chunks.sumOf { it.second.timings.decodeMs },
            totalMs = chunks.sumOf { it.second.timings.totalMs },
            audioMs = totalAudioMs,
            realTimeFactor = chunks.sumOf { it.second.timings.totalMs } / totalAudioMs.coerceAtLeast(1L)
        )
        val sourceSegments = chunks.flatMap { it.second.segments.asList() }
        val averageLogProbability = sourceSegments.map(NativeWhisperSegment::averageLogProb)
            .filterNot(Float::isNaN)
            .takeIf(List<Float>::isNotEmpty)
            ?.average()
            ?.toFloat()
            ?: Float.NaN
        val noSpeechProbability = sourceSegments.map(NativeWhisperSegment::noSpeechProbability)
            .filterNot(Float::isNaN)
            .takeIf(List<Float>::isNotEmpty)
            ?.average()
            ?.toFloat()
            ?: Float.NaN
        val segments = if (text.isBlank()) {
            emptyArray()
        } else {
            arrayOf(
                NativeWhisperSegment(
                    startMs = 0L,
                    endMs = totalAudioMs,
                    text = text,
                    averageLogProb = averageLogProbability,
                    noSpeechProbability = noSpeechProbability
                )
            )
        }
        return NativeWhisperResult(
            codeValue = NativeWhisperCode.OK.wireValue,
            segments = segments,
            detectedLanguage = chunks.firstNotNullOfOrNull { it.second.detectedLanguage },
            timings = timings,
            aborted = false,
            message = null
        )
    }
}

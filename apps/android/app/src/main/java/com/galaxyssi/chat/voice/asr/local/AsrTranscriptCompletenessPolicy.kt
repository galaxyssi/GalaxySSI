package com.galaxyssi.chat.voice.asr.local

internal data class AsrTranscriptCompletenessDecision(
    val accepted: Boolean,
    val reasonCode: String,
    val missingCoverageMs: Long = 0L
)

internal object AsrTranscriptCompletenessPolicy {
    fun evaluate(
        text: String,
        decoderComplete: Boolean,
        decodedAudioMs: Long,
        capturedSpeechMs: Long?
    ): AsrTranscriptCompletenessDecision {
        if (text.isBlank()) return rejected("empty_transcript")
        if (!decoderComplete) return rejected("decoder_output_limit")
        val speechMs = capturedSpeechMs?.takeIf { it > 0L }
            ?: return accepted()
        val missingMs = (speechMs - decodedAudioMs.coerceAtLeast(0L)).coerceAtLeast(0L)
        val toleranceMs = (speechMs / 5L).coerceIn(MIN_COVERAGE_TOLERANCE_MS, MAX_COVERAGE_TOLERANCE_MS)
        return if (missingMs <= toleranceMs) {
            accepted()
        } else {
            rejected("incomplete_audio_coverage", missingMs)
        }
    }

    private fun accepted() = AsrTranscriptCompletenessDecision(true, "complete")

    private fun rejected(reasonCode: String, missingCoverageMs: Long = 0L) =
        AsrTranscriptCompletenessDecision(false, reasonCode, missingCoverageMs)

    private const val MIN_COVERAGE_TOLERANCE_MS = 500L
    private const val MAX_COVERAGE_TOLERANCE_MS = 1_500L
}

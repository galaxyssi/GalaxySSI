package com.galaxyssi.chat.voice.audio

data class AdaptiveEndpointConfig(
    val noSpeechTimeoutMs: Long = 2_500L,
    val minimumSpeechMs: Long = 240L,
    val shortUtteranceSilenceMs: Long = 850L,
    val normalUtteranceSilenceMs: Long = 650L,
    val longUtteranceSilenceMs: Long = 500L,
    val minTrailingSilenceMs: Long = 350L,
    val maxTrailingSilenceMs: Long = 1_200L,
    val maxDurationMs: Long = 60_000L,
    val preRollMs: Int = 300,
    val postRollMs: Int = 400
) {
    init {
        require(noSpeechTimeoutMs in 1_500L..3_000L)
        require(minTrailingSilenceMs in 250L..maxTrailingSilenceMs)
        require(maxTrailingSilenceMs <= 1_500L)
        require(maxDurationMs > noSpeechTimeoutMs)
        require(preRollMs in 0..1_000)
        require(postRollMs in 0..1_000)
    }
}

enum class EndpointReason {
    TRAILING_SILENCE,
    NO_SPEECH_TIMEOUT,
    MAX_DURATION
}

data class EndpointUpdate(
    val elapsedMs: Long,
    val speechStarted: Boolean = false,
    val speechEndedCandidate: Boolean = false,
    val trailingSilenceMs: Long = 0L,
    val endpointReason: EndpointReason? = null
)

class AdaptiveEndpointDetector(
    private val sampleRateHz: Int,
    private val config: AdaptiveEndpointConfig = AdaptiveEndpointConfig(),
    private val autoEndpoint: Boolean = true
) {
    private var consumedSamples = 0L
    private var firstSpeechSample: Long? = null
    private var lastSpeechSampleExclusive: Long? = null
    private var terminalReason: EndpointReason? = null

    fun reset() {
        consumedSamples = 0L
        firstSpeechSample = null
        lastSpeechSampleExclusive = null
        terminalReason = null
    }

    fun accept(frame: AudioFrame, vad: VadDecision): EndpointUpdate {
        val frameStart = consumedSamples
        consumedSamples += frame.validSamples
        if (vad.isSpeech) {
            if (firstSpeechSample == null) firstSpeechSample = frameStart
            lastSpeechSampleExclusive = consumedSamples
        }
        val elapsedMs = samplesToMs(consumedSamples)
        val speechStartMs = firstSpeechSample?.let(::samplesToMs)
        val speechDurationMs = speechStartMs?.let { (elapsedMs - it).coerceAtLeast(0L) } ?: 0L
        val trailingSilenceMs = lastSpeechSampleExclusive?.let {
            samplesToMs((consumedSamples - it).coerceAtLeast(0L))
        } ?: elapsedMs

        if (terminalReason == null && autoEndpoint) {
            terminalReason = when {
                firstSpeechSample == null && elapsedMs >= config.noSpeechTimeoutMs ->
                    EndpointReason.NO_SPEECH_TIMEOUT
                elapsedMs >= config.maxDurationMs -> EndpointReason.MAX_DURATION
                firstSpeechSample != null &&
                    speechDurationMs >= config.minimumSpeechMs &&
                    trailingSilenceMs >= targetTrailingSilence(speechDurationMs) ->
                    EndpointReason.TRAILING_SILENCE
                else -> null
            }
        }
        return EndpointUpdate(
            elapsedMs = elapsedMs,
            speechStarted = vad.speechStarted,
            speechEndedCandidate = vad.speechEndedCandidate,
            trailingSilenceMs = trailingSilenceMs,
            endpointReason = terminalReason
        )
    }

    private fun targetTrailingSilence(speechDurationMs: Long): Long {
        val target = when {
            speechDurationMs < 1_200L -> config.shortUtteranceSilenceMs
            speechDurationMs < 5_000L -> config.normalUtteranceSilenceMs
            else -> config.longUtteranceSilenceMs
        }
        return target.coerceIn(config.minTrailingSilenceMs, config.maxTrailingSilenceMs)
    }

    private fun samplesToMs(samples: Long): Long = samples * 1_000L / sampleRateHz
}

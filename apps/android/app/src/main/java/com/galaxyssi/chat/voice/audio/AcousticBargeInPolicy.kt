package com.galaxyssi.chat.voice.audio

import kotlin.math.pow

internal data class AcousticBargeInUpdate(
    val started: Boolean = false,
    val endpoint: Boolean = false,
    val renewMonitor: Boolean = false
)

internal data class AcousticBargeInStatistics(
    val monitoredMs: Long,
    val maxRms: Float,
    val maxProbability: Float,
    val maxCandidateMs: Long,
    val maxEchoCorrelation: Float = 0f,
    val echoRejectedFrames: Long = 0L
)

/** AEC precedes this gate. The gate alone cannot distinguish speech from speaker echo. */
internal class AcousticBargeInPolicy(
    private val sampleRateHz: Int = 16_000,
    private val settlingMs: Long = 200L,
    private val confirmationMs: Long = 180L,
    private val minimumRms: Float = 0.006f,
    private val minimumProbability: Float = 0.68f,
    private val endpoint: AdaptiveEndpointConfig = AdaptiveEndpointConfig.forVoiceConversation()
) {
    private var samples = 0L
    private var candidateSample: Long? = null
    private var candidateSamples = 0L
    private var candidateGapSamples = 0L
    private var outputWasPlaying = false
    private var lastSpeechSample = 0L
    private var terminal = false
    private var maxRms = 0f
    private var maxProbability = 0f
    private var maxCandidateSamples = 0L
    var utteranceStartSample: Long? = null
        private set

    init {
        require(sampleRateHz > 0 && settlingMs >= 0 && confirmationMs > 0)
    }

    @Synchronized
    fun accept(vad: VadDecision, sampleCount: Int, outputPlaying: Boolean = false, playbackEcho: Boolean = false): AcousticBargeInUpdate {
        if (terminal || sampleCount <= 0) return AcousticBargeInUpdate()
        val frameStart = samples
        samples += sampleCount
        if (outputPlaying != outputWasPlaying && utteranceStartSample == null) {
            candidateSample = null
            candidateSamples = 0L
            candidateGapSamples = 0L
        }
        outputWasPlaying = outputPlaying
        if (vad.rms.isFinite()) maxRms = maxOf(maxRms, vad.rms.coerceIn(0f, 1f))
        if (vad.probability.isFinite()) maxProbability = maxOf(maxProbability, vad.probability.coerceIn(0f, 1f))
        // Quiet speech can pass the neural gate without reaching a fixed amplitude. During
        // playback keep the original amplitude floor as an additional residual-echo guard.
        val rmsFloor = if (outputPlaying || !vad.noiseFloorDb.isFinite()) minimumRms else
            (10.0.pow(vad.noiseFloorDb.coerceIn(-90f, -20f) / 20.0) * 1.5).toFloat()
                .coerceIn(minOf(0.001f, minimumRms), minimumRms)
        val voice = !playbackEcho && vad.isSpeech && vad.probability >= minimumProbability && vad.rms >= rmsFloor
        val startedAt = utteranceStartSample
        if (startedAt == null) {
            if (playbackEcho) {
                candidateSample = null
                candidateSamples = 0L
                candidateGapSamples = 0L
            }
            if (milliseconds(samples) < settlingMs) return AcousticBargeInUpdate()
            if (voice) {
                if (candidateSample == null) candidateSample = frameStart
                candidateSamples += sampleCount
                candidateGapSamples = 0L
                maxCandidateSamples = maxOf(maxCandidateSamples, candidateSamples)
                val span = samples - requireNotNull(candidateSample)
                if (milliseconds(candidateSamples) >= confirmationMs && candidateSamples * 4 >= span * 3) {
                    utteranceStartSample = candidateSample
                    lastSpeechSample = samples
                    return AcousticBargeInUpdate(started = true)
                }
            } else {
                candidateGapSamples += sampleCount
            }
            // Bridge a brief unvoiced consonant, but never accumulate isolated noise bursts.
            if (milliseconds(candidateGapSamples) > 60L ||
                candidateSample?.let { milliseconds(samples - it) >= confirmationMs * 2 } == true) {
                candidateSample = null
                candidateSamples = 0L
                candidateGapSamples = 0L
            }
            if (candidateSample == null && milliseconds(samples) >= 50_000L) {
                terminal = true
                return AcousticBargeInUpdate(renewMonitor = true)
            }
        } else {
            if (vad.isSpeech && vad.rms >= rmsFloor / 2) lastSpeechSample = samples
            val duration = milliseconds(samples - startedAt)
            val silence = milliseconds(samples - lastSpeechSample)
            val trailingMs = endpoint.trailingSilenceMs(milliseconds(lastSpeechSample - startedAt))
            if (silence >= trailingMs || duration >= 60_000L) {
                terminal = true
                return AcousticBargeInUpdate(endpoint = true)
            }
        }
        return AcousticBargeInUpdate()
    }

    @Synchronized
    fun statistics() = AcousticBargeInStatistics(milliseconds(samples), maxRms, maxProbability,
        milliseconds(maxCandidateSamples))

    @Synchronized
    fun streamStartSample(preRollMs: Long = 320L): Long? =
        utteranceStartSample?.let { (it - preRollMs * sampleRateHz / 1_000L).coerceAtLeast(0L) }

    @Synchronized
    fun utterance(snapshot: PcmSnapshot, preRollMs: Long = 320L): PcmSnapshot? {
        val speechStart = utteranceStartSample ?: return null
        val start = (speechStart - preRollMs * sampleRateHz / 1_000L)
            .coerceAtLeast(snapshot.captureStartSample).coerceAtMost(snapshot.captureEndSampleExclusive)
        val offset = (start - snapshot.captureStartSample).toInt().coerceIn(0, snapshot.samples.size)
        val audio = snapshot.samples.copyOfRange(offset, snapshot.samples.size)
        if (audio.isEmpty()) return null
        return snapshot.copy(
            samples = audio,
            speechDetected = true,
            speechStartSample = speechStart,
            speechEndSampleExclusive = lastSpeechSample.coerceAtMost(snapshot.captureEndSampleExclusive),
            captureStartSample = start
        )
    }

    private fun milliseconds(count: Long) = count * 1_000L / sampleRateHz

    companion object {
        fun hasEchoProtection(state: PcmRecorderState): Boolean = state.acousticEchoCancelerEnabled ||
            state.inputRoute in setOf("wired_headset", "bluetooth_sco", "bluetooth_le", "usb_headset")
    }
}

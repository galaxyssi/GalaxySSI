package com.galaxyssi.chat.voice.audio

internal data class AcousticBargeInUpdate(
    val started: Boolean = false,
    val endpoint: Boolean = false,
    val renewMonitor: Boolean = false
)

internal data class AcousticBargeInStatistics(
    val monitoredMs: Long,
    val maxRms: Float,
    val maxProbability: Float,
    val maxCandidateMs: Long
)

/** AEC precedes this gate. The gate alone cannot distinguish speech from speaker echo. */
internal class AcousticBargeInPolicy(
    private val sampleRateHz: Int = 16_000,
    private val settlingMs: Long = 200L,
    private val confirmationMs: Long = 180L,
    private val minimumRms: Float = 0.006f,
    private val minimumProbability: Float = 0.68f
) {
    private var samples = 0L
    private var candidateSample: Long? = null
    private var candidateSamples = 0L
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
    fun accept(vad: VadDecision, sampleCount: Int): AcousticBargeInUpdate {
        if (terminal || sampleCount <= 0) return AcousticBargeInUpdate()
        val frameStart = samples
        samples += sampleCount
        if (vad.rms.isFinite()) maxRms = maxOf(maxRms, vad.rms.coerceIn(0f, 1f))
        if (vad.probability.isFinite()) maxProbability = maxOf(maxProbability, vad.probability.coerceIn(0f, 1f))
        val voice = vad.isSpeech && vad.probability >= minimumProbability && vad.rms >= minimumRms
        val startedAt = utteranceStartSample
        if (startedAt == null) {
            if (milliseconds(samples) < settlingMs) return AcousticBargeInUpdate()
            if (voice) {
                if (candidateSample == null) candidateSample = frameStart
                candidateSamples += sampleCount
                maxCandidateSamples = maxOf(maxCandidateSamples, candidateSamples)
                if (milliseconds(candidateSamples) >= confirmationMs) {
                    utteranceStartSample = candidateSample
                    lastSpeechSample = samples
                    return AcousticBargeInUpdate(started = true)
                }
            } else {
                candidateSample = null
                candidateSamples = 0L
            }
            if (candidateSample == null && milliseconds(samples) >= 50_000L) {
                terminal = true
                return AcousticBargeInUpdate(renewMonitor = true)
            }
        } else {
            if (vad.isSpeech && vad.rms >= minimumRms / 2) lastSpeechSample = samples
            val duration = milliseconds(samples - startedAt)
            val silence = milliseconds(samples - lastSpeechSample)
            val trailingMs = when {
                duration < 1_200L -> 850L
                duration < 5_000L -> 650L
                else -> 500L
            }
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

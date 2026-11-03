package com.galaxyssi.chat.voice.audio

import kotlin.math.abs
import kotlin.math.log10
import kotlin.math.sqrt

internal interface SpeechProbabilityModel : AutoCloseable {
    fun prepare()
    fun probability(samples: FloatArray): Float
    fun reset()
}

/** Adapts capture frames to 32 ms model windows without retaining an utterance. */
internal class NeuralSpeechVad(
    private val model: SpeechProbabilityModel,
    private val attackWindows: Int = 2,
    private val releaseWindows: Int = 4
) : VoiceActivityDetector {
    private val window = FloatArray(WINDOW_SAMPLES)
    private var filled = 0
    private var probability = 0f
    private var active = false
    private var positive = 0
    private var negative = 0
    private var noiseFloorDb = -58f
    private var lastSequence: Long? = null

    init {
        require(attackWindows > 0 && releaseWindows > 0)
    }

    override fun prepare(sampleRateHz: Int) {
        require(sampleRateHz == SAMPLE_RATE_HZ) { "Neural VAD requires 16 kHz PCM" }
        model.prepare()
        reset()
    }

    override fun reset() {
        window.fill(0f)
        filled = 0
        probability = 0f
        active = false
        positive = 0
        negative = 0
        noiseFloorDb = -58f
        lastSequence = null
        model.reset()
    }

    override fun accept(frame: AudioFrame): VadDecision {
        require(frame.validSamples in 0..frame.samples.size)
        if (lastSequence?.let { frame.sequence != it + 1 } == true) reset()
        lastSequence = frame.sequence
        var started = false
        var ended = false
        var energy = 0.0
        var peak = 0
        repeat(frame.validSamples) { index ->
            val sample = frame.samples[index].toInt()
            energy += sample.toDouble() * sample
            peak = maxOf(peak, abs(sample))
            window[filled++] = sample / 32768f
            if (filled == WINDOW_SAMPLES) {
                probability = model.probability(window)
                check(probability.isFinite() && probability in 0f..1f) { "Invalid neural VAD probability" }
                window.fill(0f)
                filled = 0
                if (probability >= if (active) RELEASE_THRESHOLD else START_THRESHOLD) {
                    positive++
                    negative = 0
                    if (!active && positive >= attackWindows) {
                        active = true
                        started = true
                    }
                } else {
                    positive = 0
                    if (active && ++negative >= releaseWindows) {
                        active = false
                        negative = 0
                        ended = true
                    }
                }
            }
        }
        val rms = if (frame.validSamples == 0) 0f else
            (sqrt(energy / frame.validSamples) / 32768.0).toFloat()
        if (!active && probability < 0.2f) {
            val db = 20f * log10(rms.coerceAtLeast(0.00001f))
            noiseFloorDb = (noiseFloorDb * 0.95f + db * 0.05f).coerceIn(-72f, -30f)
        }
        return VadDecision(probability, active || started, started, ended, rms, peak, noiseFloorDb)
    }

    override fun close() {
        try { reset() } finally { model.close() }
    }

    companion object {
        const val SAMPLE_RATE_HZ = 16_000
        const val WINDOW_SAMPLES = 512
        private const val START_THRESHOLD = 0.6f
        private const val RELEASE_THRESHOLD = 0.35f
    }
}

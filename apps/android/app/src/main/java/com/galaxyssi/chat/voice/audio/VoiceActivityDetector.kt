package com.galaxyssi.chat.voice.audio

import kotlin.math.log10
import kotlin.math.sqrt

data class VadDecision(
    val probability: Float,
    val isSpeech: Boolean,
    val speechStarted: Boolean,
    val speechEndedCandidate: Boolean,
    val rms: Float,
    val peak: Int,
    val noiseFloorDb: Float
)

interface VoiceActivityDetector {
    fun reset()
    fun accept(frame: AudioFrame): VadDecision
}

class AdaptiveSpeechVad(
    private val attackFrames: Int = 2,
    private val releaseFrames: Int = 5,
    private val minimumSpeechDb: Float = -48f,
    private val minimumSnrDb: Float = 8f
) : VoiceActivityDetector {
    private var noiseFloorDb = INITIAL_NOISE_FLOOR_DB
    private var speechActive = false
    private var positiveFrames = 0
    private var negativeFrames = 0

    override fun reset() {
        noiseFloorDb = INITIAL_NOISE_FLOOR_DB
        speechActive = false
        positiveFrames = 0
        negativeFrames = 0
    }

    override fun accept(frame: AudioFrame): VadDecision {
        if (frame.validSamples <= 0) {
            return VadDecision(0f, false, false, false, 0f, 0, noiseFloorDb)
        }
        var energy = 0.0
        var peak = 0
        var crossings = 0
        var previous = frame.samples[0].toInt()
        repeat(frame.validSamples) { index ->
            val value = frame.samples[index].toInt()
            energy += value.toDouble() * value.toDouble()
            peak = maxOf(peak, kotlin.math.abs(value))
            if (index > 0 && (value >= 0) != (previous >= 0)) crossings += 1
            previous = value
        }
        val rmsRaw = sqrt(energy / frame.validSamples)
        val rms = (rmsRaw / Short.MAX_VALUE.toDouble()).toFloat().coerceIn(0f, 1f)
        val db = (20.0 * log10(rms.coerceAtLeast(MIN_RMS).toDouble())).toFloat()
        val snr = db - noiseFloorDb
        val zeroCrossingRate = crossings.toFloat() / frame.validSamples
        val absoluteScore = ((db - minimumSpeechDb) / 18f).coerceIn(0f, 1f)
        val snrScore = ((snr - minimumSnrDb) / 14f).coerceIn(0f, 1f)
        val structureScore = when {
            zeroCrossingRate in 0.015f..0.42f -> 1f
            zeroCrossingRate < 0.01f -> 0.35f
            else -> 0.55f
        }
        val probability = (absoluteScore * 0.40f + snrScore * 0.45f + structureScore * 0.15f)
            .coerceIn(0f, 1f)
        val positive = db >= minimumSpeechDb && snr >= minimumSnrDb && probability >= 0.52f

        if (!speechActive && !positive) {
            val alpha = if (db < noiseFloorDb + 6f) 0.08f else 0.015f
            noiseFloorDb = (noiseFloorDb * (1f - alpha) + db * alpha)
                .coerceIn(MIN_NOISE_FLOOR_DB, MAX_NOISE_FLOOR_DB)
        }

        var started = false
        var ended = false
        if (positive) {
            positiveFrames += 1
            negativeFrames = 0
            if (!speechActive && positiveFrames >= attackFrames) {
                speechActive = true
                started = true
            }
        } else {
            positiveFrames = 0
            if (speechActive) {
                negativeFrames += 1
                if (negativeFrames >= releaseFrames) {
                    speechActive = false
                    negativeFrames = 0
                    ended = true
                }
            }
        }
        return VadDecision(
            probability = probability,
            isSpeech = speechActive || positive,
            speechStarted = started,
            speechEndedCandidate = ended,
            rms = rms,
            peak = peak,
            noiseFloorDb = noiseFloorDb
        )
    }

    private companion object {
        const val INITIAL_NOISE_FLOOR_DB = -58f
        const val MIN_NOISE_FLOOR_DB = -72f
        const val MAX_NOISE_FLOOR_DB = -30f
        const val MIN_RMS = 0.00001f
    }
}

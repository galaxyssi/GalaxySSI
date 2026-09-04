package com.galaxyssi.chat.voice.audio

import android.media.MediaRecorder
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.atomic.AtomicBoolean

data class PcmCaptureConfig(
    val sampleRateHz: Int = 16_000,
    val frameDurationMs: Int = 20,
    val maxDurationMs: Long = 60_000L,
    val preferredAudioSources: List<Int> = listOf(
        MediaRecorder.AudioSource.VOICE_RECOGNITION,
        MediaRecorder.AudioSource.MIC
    ),
    val enableAcousticEchoCanceler: Boolean = true,
    val enableNoiseSuppressor: Boolean = true,
    val enableAutomaticGainControl: Boolean = false,
    val audioRecordBufferMs: Int = 500,
    val framePoolSize: Int = 16,
    val outputQueueCapacity: Int = 8
) {
    val samplesPerFrame: Int
        get() = (sampleRateHz * frameDurationMs / 1_000).coerceAtLeast(1)

    fun captureSampleRateCandidates(): List<Int> = if (sampleRateHz == WHISPER_SAMPLE_RATE_HZ) {
        listOf(WHISPER_SAMPLE_RATE_HZ, ANDROID_HIGH_RATE_HZ)
    } else {
        listOf(sampleRateHz)
    }

    fun captureSamplesPerFrame(captureSampleRateHz: Int): Int =
        (captureSampleRateHz * frameDurationMs / 1_000).coerceAtLeast(1)

    init {
        require(sampleRateHz > 0)
        require(frameDurationMs in 10..100)
        require(maxDurationMs > 0L)
        require(preferredAudioSources.isNotEmpty())
        require(audioRecordBufferMs in 500..2_000)
        require(framePoolSize >= 4)
        require(outputQueueCapacity >= 1)
    }

    private companion object {
        const val WHISPER_SAMPLE_RATE_HZ = 16_000
        const val ANDROID_HIGH_RATE_HZ = 48_000
    }
}

enum class PcmRecorderPhase {
    IDLE,
    STARTING,
    RECORDING,
    STOPPING,
    STOPPED,
    FAILED
}

enum class PcmStopReason {
    USER_SEND,
    USER_CANCEL,
    ADAPTIVE_ENDPOINT,
    NO_SPEECH_TIMEOUT,
    MAX_DURATION,
    APP_BACKGROUND,
    AUDIO_INTERRUPTED,
    CAPTURE_FAILURE
}

data class PcmRecorderDiagnostics(
    val shortReadCount: Long = 0L,
    val zeroReadCount: Long = 0L,
    val droppedFrameCount: Long = 0L,
    val suspectedOverrunCount: Long = 0L,
    val inputRouteChangeCount: Long = 0L
)

data class PcmRecorderState(
    val phase: PcmRecorderPhase = PcmRecorderPhase.IDLE,
    val audioSource: Int? = null,
    val audioSessionId: Int? = null,
    val inputRoute: String = "",
    val captureSampleRateHz: Int? = null,
    val outputSampleRateHz: Int? = null,
    val currentAmplitude: Int = 0,
    val capturedSamples: Long = 0L,
    val stopReason: PcmStopReason? = null,
    val errorCode: String? = null,
    val diagnostics: PcmRecorderDiagnostics = PcmRecorderDiagnostics()
)

class AudioFrame internal constructor(
    val sequence: Long,
    val captureTimeNanos: Long,
    val samples: ShortArray,
    val validSamples: Int,
    private val releaseAction: (ShortArray) -> Unit,
    private val directPcm16: ByteBuffer? = null
) : AutoCloseable {
    private val released = AtomicBoolean(false)

    fun directPcm16Buffer(): ByteBuffer? {
        val source = directPcm16 ?: return null
        return source.asReadOnlyBuffer()
            .order(ByteOrder.LITTLE_ENDIAN)
            .apply {
                position(0)
                limit((validSamples * PCM16_BYTES_PER_SAMPLE).coerceAtMost(capacity()))
            }
    }

    override fun close() {
        if (released.compareAndSet(false, true)) releaseAction(samples)
    }
}

class DirectPcmFramePacket(
    val sequence: Long,
    val captureTimeNanos: Long,
    val pcm16: ByteBuffer,
    val sampleCount: Int,
    val sampleRateHz: Int
) {
    init {
        require(sequence >= 0L)
        require(captureTimeNanos >= 0L)
        require(pcm16.isDirect)
        require(sampleCount > 0 && sampleCount * PCM16_BYTES_PER_SAMPLE <= pcm16.remaining())
        require(sampleRateHz > 0)
    }
}

data class PcmFramePacket(
    val sequence: Long,
    val captureTimeNanos: Long,
    val samples: ShortArray,
    val sampleRateHz: Int
) {
    init {
        require(sequence >= 0L)
        require(captureTimeNanos >= 0L)
        require(samples.isNotEmpty())
        require(sampleRateHz > 0)
    }
}

data class PcmSnapshot(
    val samples: ShortArray,
    val sampleRateHz: Int,
    val speechDetected: Boolean,
    val speechStartSample: Long?,
    val speechEndSampleExclusive: Long?,
    val captureStartSample: Long,
    val captureEndSampleExclusive: Long
) {
    val durationMs: Long
        get() = samples.size.toLong() * 1_000L / sampleRateHz

    val speechDurationMs: Long?
        get() = speechStartSample?.let { start ->
            speechEndSampleExclusive
                ?.minus(start)
                ?.coerceAtLeast(0L)
                ?.times(1_000L)
                ?.div(sampleRateHz)
        }
}

data class VoiceAudioCaptureResult(
    val sessionId: String,
    val stopReason: PcmStopReason,
    val snapshot: PcmSnapshot,
    val diagnostics: PcmRecorderDiagnostics,
    val audioSource: Int?,
    val inputRoute: String
)

class PcmCaptureException(
    val code: String,
    message: String,
    cause: Throwable? = null
) : IllegalStateException(message, cause)

private const val PCM16_BYTES_PER_SAMPLE = 2

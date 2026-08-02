package com.signalasi.chat.voice.asr.local

import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.StateFlow
import java.nio.ByteBuffer

enum class AsrPerformanceMode {
    FAST,
    BALANCED,
    POWER_SAVER
}

data class AsrConfig(
    val language: String = "zh",
    val inputSampleRateHz: Int = 16_000,
    val updateIntervalMs: Long = 900L,
    val firstPartialDelayMs: Long = 900L,
    val endSilenceMs: Long = 450L,
    val maxSegmentMs: Long = 28_000L,
    val minSegmentMs: Long = 300L,
    val activeWindowMs: Long = 10_000L,
    val overlapMs: Long = 2_000L,
    val preRollMs: Long = 200L,
    val postRollMs: Long = 150L,
    val maxTokens: Int = 160,
    val enableTimestamps: Boolean = false,
    val performanceMode: AsrPerformanceMode = AsrPerformanceMode.BALANCED,
    val finalizationTimeoutMs: Long = 3_000L
) {
    init {
        require(language in SUPPORTED_LANGUAGES) { "Large-v3-Turbo supports zh or auto in this product mode" }
        require(inputSampleRateHz == 16_000 || inputSampleRateHz == 48_000)
        require(updateIntervalMs in 500L..2_000L)
        require(firstPartialDelayMs in 800L..2_000L)
        require(endSilenceMs in 350L..500L)
        require(maxSegmentMs in 25_000L..28_000L)
        require(minSegmentMs in 300L..1_000L)
        require(activeWindowMs in 6_000L..12_000L)
        require(overlapMs in 1_000L..3_000L && overlapMs < activeWindowMs)
        require(preRollMs in 0L..500L)
        require(postRollMs in 0L..500L)
        require(maxTokens in 100..160)
        require(!enableTimestamps) { "Timestamp decoding is disabled for the first Large-v3-Turbo release" }
        require(finalizationTimeoutMs in 1_000L..10_000L)
    }

    val emitsIntermediateResults: Boolean
        get() = performanceMode != AsrPerformanceMode.POWER_SAVER

    companion object {
        private val SUPPORTED_LANGUAGES = setOf("zh", "auto")
    }
}

enum class LocalAsrPauseReason {
    APP_BACKGROUND,
    PHONE_CALL,
    AUDIO_FOCUS_LOST,
    MICROPHONE_PERMISSION_REVOKED,
    THERMAL_LIMIT,
    USER_REQUEST
}

sealed interface LocalAsrState {
    data object Unprepared : LocalAsrState
    data class Preparing(val modelDirectory: String) : LocalAsrState
    data class Ready(val modelDirectory: String, val preparedAtMillis: Long) : LocalAsrState
    data class Starting(val sessionToken: Long, val config: AsrConfig) : LocalAsrState
    data class Listening(val sessionToken: Long, val config: AsrConfig) : LocalAsrState
    data class Paused(
        val sessionToken: Long,
        val config: AsrConfig,
        val reasons: Set<LocalAsrPauseReason>
    ) : LocalAsrState
    data class Stopping(val sessionToken: Long, val config: AsrConfig) : LocalAsrState
    data class Failed(val code: String, val message: String, val recoverable: Boolean) : LocalAsrState
    data object Closed : LocalAsrState
}

sealed interface AsrEvent {
    data class StateChanged(val state: LocalAsrState) : AsrEvent

    data class Partial(
        val stableText: String,
        val unstableText: String,
        val revision: Long = 0L,
        val audioDurationMs: Long = 0L,
        val inferenceMs: Long = 0L
    ) : AsrEvent

    data class Final(
        val text: String,
        val durationMs: Long,
        val inferenceMs: Long
    ) : AsrEvent

    data class Error(
        val code: String,
        val message: String,
        val recoverable: Boolean = true
    ) : AsrEvent

    data class Diagnostics(
        val encoderMs: Double,
        val decoderMsPerToken: Double,
        val encoderNpuLayers: Int,
        val encoderTotalLayers: Int,
        val decoderNpuLayers: Int,
        val decoderTotalLayers: Int,
        val thermalStatus: Int,
        val residentBytes: Long
    ) : AsrEvent
}

interface LocalAsrEngine : AutoCloseable {
    val state: StateFlow<LocalAsrState>
    val events: Flow<AsrEvent>

    suspend fun prepare(modelDirectory: String)
    fun start(config: AsrConfig = AsrConfig())
    fun pushPcm(pcm: ByteBuffer, sampleCount: Int): Boolean
    fun stop()
    fun cancel()
    fun pause(reason: LocalAsrPauseReason)
    fun resume(reason: LocalAsrPauseReason)
    override fun close()
}

interface QnnAsrNativeCallback {
    fun onPartial(
        sessionToken: Long,
        stableText: String,
        unstableText: String,
        audioDurationMs: Long,
        inferenceMs: Long
    )

    fun onFinal(sessionToken: Long, text: String, durationMs: Long, inferenceMs: Long)
    fun onError(sessionToken: Long, code: String, message: String, recoverable: Boolean)
    fun onDiagnostics(sessionToken: Long, diagnostics: AsrEvent.Diagnostics)
}

interface QnnAsrNativeApi {
    fun create(modelDirectory: String, runtimeDirectory: String, callback: QnnAsrNativeCallback): Long
    fun start(handle: Long, sessionToken: Long, config: AsrConfig): Boolean
    fun pushPcm(handle: Long, sessionToken: Long, pcm: ByteBuffer, sampleCount: Int): Boolean
    fun stop(handle: Long, sessionToken: Long)
    fun cancel(handle: Long, sessionToken: Long)
    fun pause(handle: Long, sessionToken: Long)
    fun resume(handle: Long, sessionToken: Long): Boolean
    fun destroy(handle: Long)
}

fun interface QnnAsrModelDirectoryValidator {
    fun validate(modelDirectory: String): String

    companion object {
        val REQUIRED_FILES = setOf(
            "encoder.bin",
            "decoder.bin",
            "whisper_metadata.json",
            "tokenizer.tiktoken",
            "mel_filters.bin",
            "generation_config.json",
            "manifest.json",
            "model.sha256"
        )
    }
}

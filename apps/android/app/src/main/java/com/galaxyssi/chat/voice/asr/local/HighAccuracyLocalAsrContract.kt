package com.galaxyssi.chat.voice.asr.local

import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.StateFlow
import java.nio.ByteBuffer

enum class AsrPerformanceMode {
    FAST,
    BALANCED,
    POWER_SAVER
}

enum class AsrRuntimePolicyReason {
    PERFORMANCE_MODE,
    CONTINUOUS_USE,
    THERMAL_MODERATE,
    THERMAL_SEVERE,
    SYSTEM_POWER_SAVER
}

data class AsrRuntimePolicy(
    val partialIntervalMs: Long,
    val emitIntermediateResults: Boolean,
    val thermalStatus: Int = THERMAL_STATUS_NONE,
    val continuousUseMs: Long = 0L,
    val reasons: Set<AsrRuntimePolicyReason> = setOf(AsrRuntimePolicyReason.PERFORMANCE_MODE)
) {
    init {
        require(partialIntervalMs in MIN_PARTIAL_INTERVAL_MS..MAX_PARTIAL_INTERVAL_MS)
        require(thermalStatus in THERMAL_STATUS_NONE..THERMAL_STATUS_SHUTDOWN)
        require(continuousUseMs >= 0L)
    }

    companion object {
        const val MIN_PARTIAL_INTERVAL_MS = 500L
        const val MAX_PARTIAL_INTERVAL_MS = 2_000L
        const val THERMAL_STATUS_NONE = 0
        const val THERMAL_STATUS_MODERATE = 2
        const val THERMAL_STATUS_SEVERE = 3
        const val THERMAL_STATUS_CRITICAL = 4
        const val THERMAL_STATUS_SHUTDOWN = 6

        fun from(config: AsrConfig): AsrRuntimePolicy = AsrRuntimePolicy(
            partialIntervalMs = config.updateIntervalMs,
            emitIntermediateResults = config.emitsIntermediateResults
        )
    }
}

class AdaptiveAsrRuntimePolicyPlanner(
    private val continuousUseThresholdMs: Long = 5L * 60L * 1_000L
) {
    init {
        require(continuousUseThresholdMs > 0L)
    }

    fun resolve(
        config: AsrConfig,
        continuousUseMs: Long,
        thermalStatus: Int,
        systemPowerSaveMode: Boolean
    ): AsrRuntimePolicy {
        val elapsed = continuousUseMs.coerceAtLeast(0L)
        val thermal = thermalStatus.coerceIn(
            AsrRuntimePolicy.THERMAL_STATUS_NONE,
            AsrRuntimePolicy.THERMAL_STATUS_SHUTDOWN
        )
        val reasons = linkedSetOf(AsrRuntimePolicyReason.PERFORMANCE_MODE)
        var interval = config.updateIntervalMs
        var emitPartials = config.emitsIntermediateResults

        if (elapsed >= continuousUseThresholdMs) {
            interval = maxOf(interval, LONG_SESSION_INTERVAL_MS)
            reasons += AsrRuntimePolicyReason.CONTINUOUS_USE
        }
        if (thermal >= AsrRuntimePolicy.THERMAL_STATUS_MODERATE) {
            interval = maxOf(interval, WARM_INTERVAL_MS)
            reasons += AsrRuntimePolicyReason.THERMAL_MODERATE
        }
        if (thermal >= AsrRuntimePolicy.THERMAL_STATUS_SEVERE) {
            emitPartials = false
            reasons += AsrRuntimePolicyReason.THERMAL_SEVERE
        }
        if (systemPowerSaveMode) {
            interval = maxOf(interval, LONG_SESSION_INTERVAL_MS)
            emitPartials = false
            reasons += AsrRuntimePolicyReason.SYSTEM_POWER_SAVER
        }
        return AsrRuntimePolicy(
            partialIntervalMs = interval.coerceIn(
                AsrRuntimePolicy.MIN_PARTIAL_INTERVAL_MS,
                AsrRuntimePolicy.MAX_PARTIAL_INTERVAL_MS
            ),
            emitIntermediateResults = emitPartials,
            thermalStatus = thermal,
            continuousUseMs = elapsed,
            reasons = reasons
        )
    }

    private companion object {
        const val WARM_INTERVAL_MS = 1_000L
        const val LONG_SESSION_INTERVAL_MS = 1_200L
    }
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
    val postRollMs: Long = 400L,
    val maxTokens: Int = MAX_FINAL_TOKENS,
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
        require(maxTokens in 100..MAX_FINAL_TOKENS)
        require(!enableTimestamps) { "Timestamp decoding is disabled for the first Large-v3-Turbo release" }
        require(finalizationTimeoutMs in 1_000L..10_000L)
    }

    val emitsIntermediateResults: Boolean
        get() = performanceMode != AsrPerformanceMode.POWER_SAVER

    companion object {
        // The exported decoder has 200 positions. Four prompt positions and one EOT look-ahead
        // position leave 195 positions for visible text without silently clipping dense speech.
        const val MAX_FINAL_TOKENS = 195
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
        val inferenceMs: Long,
        val termination: AsrTranscriptTermination = AsrTranscriptTermination.UNKNOWN
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
        val residentBytes: Long,
        val qnnExecution: QnnExecutionAttestation? = null
    ) : AsrEvent
}

enum class AsrTranscriptTermination {
    END_OF_TEXT,
    TOKEN_LIMIT,
    CONTEXT_LIMIT,
    REPETITION_LIMIT,
    NO_SPEECH,
    UNKNOWN;

    val isComplete: Boolean
        get() = this != TOKEN_LIMIT && this != CONTEXT_LIMIT && this != REPETITION_LIMIT
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
    fun updateRuntimePolicy(policy: AsrRuntimePolicy) = Unit
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

    fun onFinal(
        sessionToken: Long,
        text: String,
        durationMs: Long,
        inferenceMs: Long,
        termination: AsrTranscriptTermination
    )
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
    fun updateRuntimePolicy(handle: Long, policy: AsrRuntimePolicy) = Unit
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

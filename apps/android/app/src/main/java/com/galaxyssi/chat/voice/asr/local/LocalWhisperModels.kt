package com.galaxyssi.chat.voice.asr.local

import com.galaxyssi.chat.voice.model.WhisperExecutionMode
import com.galaxyssi.chat.voice.model.WhisperModelProfile
import kotlinx.coroutines.flow.StateFlow

enum class WhisperAccelerationBackend {
    QNN_HTP,
    QMX_SME,
    CPU
}

enum class NativeWhisperCode(val wireValue: Int) {
    OK(0),
    ABORTED(1),
    INVALID_HANDLE(2),
    MODEL_NOT_LOADED(3),
    MODEL_CORRUPTED(4),
    UNSUPPORTED_MODEL(5),
    INVALID_PCM(6),
    DECODE_FAILED(7),
    OUT_OF_MEMORY(8),
    NATIVE_INTERNAL_ERROR(9),
    TIMEOUT(10);

    companion object {
        fun fromWire(value: Int): NativeWhisperCode = entries.firstOrNull { it.wireValue == value }
            ?: NATIVE_INTERNAL_ERROR
    }
}

data class NativeWhisperSegment(
    val startMs: Long,
    val endMs: Long,
    val text: String,
    val averageLogProb: Float,
    val noSpeechProbability: Float
)

data class NativeWhisperTimings(
    val sampleMs: Double,
    val encodeMs: Double,
    val decodeMs: Double,
    val totalMs: Double,
    val audioMs: Long,
    val realTimeFactor: Double
) {
    companion object {
        val EMPTY = NativeWhisperTimings(0.0, 0.0, 0.0, 0.0, 0L, 0.0)
    }
}

data class NativeWhisperResult(
    val codeValue: Int,
    val segments: Array<NativeWhisperSegment>,
    val detectedLanguage: String?,
    val timings: NativeWhisperTimings,
    val aborted: Boolean,
    val message: String?
) {
    val code: NativeWhisperCode
        get() = NativeWhisperCode.fromWire(codeValue)

    val text: String
        get() = segments.joinToString(separator = "") { it.text }.trim()

    val successful: Boolean
        get() = code == NativeWhisperCode.OK

    companion object {
        fun failure(code: NativeWhisperCode, message: String): NativeWhisperResult = NativeWhisperResult(
            codeValue = code.wireValue,
            segments = emptyArray(),
            detectedLanguage = null,
            timings = NativeWhisperTimings.EMPTY,
            aborted = code == NativeWhisperCode.ABORTED,
            message = message
        )
    }
}

data class WhisperLoadOptions(
    val threadCount: Int = Runtime.getRuntime().availableProcessors().coerceIn(1, 4),
    val useGpu: Boolean = false,
    val warmUp: Boolean = true,
    val warmUpSamples: Int = 16_000
) {
    init {
        require(threadCount in 1..16)
        require(warmUpSamples in 1_600..32_000)
    }
}

data class LocalWhisperSessionConfig(
    val language: String = "zh",
    val translate: Boolean = false,
    val noContext: Boolean = true,
    val singleSegment: Boolean = false,
    val maxTokens: Int = 0,
    val prompt: String = "",
    val mode: WhisperExecutionMode = WhisperExecutionMode.FINAL_ONLY
) {
    init {
        require(language.length <= 16)
        require(maxTokens in 0..4_096)
        require(prompt.length <= 1_024)
    }
}

data class WhisperDecodeRequest(
    val pcm16: ShortArray,
    val sampleRateHz: Int = 16_000,
    val offset: Int = 0,
    val length: Int = pcm16.size - offset,
    val mode: WhisperExecutionMode = WhisperExecutionMode.FINAL_ONLY
) {
    init {
        require(sampleRateHz == 16_000) { "Whisper PCM must be 16 kHz" }
        require(offset >= 0 && length > 0 && offset <= pcm16.size - length) { "Invalid PCM range" }
    }
}

data class WhisperLoadedModel(
    val profile: WhisperModelProfile,
    val threadCount: Int,
    val loadedAtMillis: Long,
    val loadDurationMs: Long,
    val warmUpTimings: NativeWhisperTimings?,
    val accelerationBackend: WhisperAccelerationBackend = WhisperAccelerationBackend.CPU,
    val accelerationDetail: String = "GGML CPU"
)

enum class AbortReason {
    USER_STOP,
    NEW_UTTERANCE,
    SESSION_CLOSED,
    MODEL_SWITCH,
    THERMAL_CRITICAL,
    TIMEOUT,
    UPSTREAM_FINAL_SELECTED,
    MEMORY_PRESSURE,
    RUNTIME_UNLOAD
}

enum class UnloadReason {
    USER_REQUEST,
    MODEL_SWITCH,
    MEMORY_PRESSURE,
    THERMAL_CRITICAL,
    APP_SHUTDOWN,
    LOAD_FAILED
}

data class WhisperRuntimeError(
    val code: NativeWhisperCode,
    val message: String
)

sealed interface WhisperRuntimeState {
    data object Unloaded : WhisperRuntimeState
    data class Loading(val profileId: String) : WhisperRuntimeState
    data class Ready(val model: WhisperLoadedModel) : WhisperRuntimeState
    data class Decoding(val sessionId: String, val mode: WhisperExecutionMode) : WhisperRuntimeState
    data class Unloading(val reason: UnloadReason) : WhisperRuntimeState
    data class Failed(val error: WhisperRuntimeError) : WhisperRuntimeState
}

data class BenchmarkRequest(
    val pcm16: ShortArray,
    val language: String = "zh",
    val iterations: Int = 1
) {
    init {
        require(pcm16.isNotEmpty())
        require(iterations in 1..30)
    }
}

data class BenchmarkResult(
    val profileId: String,
    val iterations: Int,
    val timings: List<NativeWhisperTimings>,
    val medianRealTimeFactor: Double
)

interface LocalWhisperSession : AutoCloseable {
    val id: String
    val config: LocalWhisperSessionConfig
    suspend fun decode(request: WhisperDecodeRequest): NativeWhisperResult
    fun requestAbort(reason: AbortReason)
    override fun close()
}

interface LocalWhisperRuntime : AutoCloseable {
    val state: StateFlow<WhisperRuntimeState>
    suspend fun load(profile: WhisperModelProfile, options: WhisperLoadOptions = WhisperLoadOptions()): WhisperLoadedModel
    suspend fun createSession(config: LocalWhisperSessionConfig = LocalWhisperSessionConfig()): LocalWhisperSession
    suspend fun unload(reason: UnloadReason = UnloadReason.USER_REQUEST)
    suspend fun runBenchmark(request: BenchmarkRequest): BenchmarkResult
    fun requestAbortAll(reason: AbortReason)
    override fun close()
}

package com.galaxyssi.chat.voice.asr

import com.galaxyssi.chat.voice.TranscriptHypothesis
import kotlinx.coroutines.flow.Flow

enum class VoiceRecognitionPreference {
    AUTO,
    ONLINE_FAST,
    LOCAL_PRIVATE,
    LOCAL_HIGH_ACCURACY,
    REMOTE_NODE
}

enum class AsrTransport {
    WEBRTC,
    WEBSOCKET,
    HTTP_UPLOAD_FALLBACK
}

enum class AsrNetworkType {
    OFFLINE,
    WIFI,
    MOBILE,
    OTHER_VALIDATED
}

data class AsrPrivacyPolicy(
    val allowOnlineVoice: Boolean = false,
    val wifiOnly: Boolean = true,
    val allowMobileNetwork: Boolean = false,
    val allowRawAudioUpload: Boolean = false,
    val requestServerDataDeletion: Boolean = true,
    val localAlwaysPreferred: Boolean = false
)

data class AsrSessionConfig(
    val voiceSessionId: String,
    val transcriptId: String,
    val language: String = "auto",
    val sampleRateHz: Int = 16_000,
    val channelCount: Int = 1,
    val preference: VoiceRecognitionPreference = VoiceRecognitionPreference.AUTO,
    val networkType: AsrNetworkType = AsrNetworkType.OFFLINE,
    val privacy: AsrPrivacyPolicy = AsrPrivacyPolicy(),
    val preferredTransports: List<AsrTransport> = listOf(AsrTransport.WEBRTC, AsrTransport.WEBSOCKET),
    val connectTimeoutMs: Long = 3_000L,
    val finalTimeoutMs: Long = 1_200L
) {
    init {
        require(voiceSessionId.isNotBlank())
        require(transcriptId.isNotBlank())
        require(sampleRateHz == 16_000) { "Realtime ASR requires PCM16 at 16 kHz" }
        require(channelCount == 1) { "Realtime ASR requires mono PCM" }
        require(preferredTransports.isNotEmpty())
        require(connectTimeoutMs in 250L..30_000L)
        require(finalTimeoutMs in 100L..30_000L)
    }
}

data class AsrAvailability(
    val available: Boolean,
    val reasonCode: String = "",
    val retryable: Boolean = false,
    val transport: AsrTransport? = null
) {
    companion object {
        fun ready(transport: AsrTransport) = AsrAvailability(true, transport = transport)
        fun unavailable(reasonCode: String, retryable: Boolean = false) =
            AsrAvailability(false, reasonCode, retryable)
    }
}

data class AsrAudioFrame(
    val sequence: Long,
    val captureTimeNanos: Long,
    val samples: ShortArray,
    val sampleRateHz: Int = 16_000
) {
    init {
        require(sequence >= 0L)
        require(captureTimeNanos >= 0L)
        require(samples.isNotEmpty())
        require(sampleRateHz == 16_000)
    }

    val durationMs: Long
        get() = samples.size.toLong() * 1_000L / sampleRateHz
}

data class AsrMetrics(
    val providerId: String,
    val providerSessionId: String,
    val audioSentMs: Long = 0L,
    val firstPartialLatencyMs: Long? = null,
    val finalLatencyMs: Long? = null,
    val reconnectCount: Int = 0,
    val droppedAudioBatches: Int = 0,
    val serverTimestampMs: Long? = null
)

data class AsrUsage(
    val providerId: String,
    val providerSessionId: String,
    val audioDurationMs: Long,
    val billableDurationMs: Long? = null,
    val serverTimestampMs: Long? = null
)

data class AsrError(
    val code: String,
    val message: String = "",
    val retryable: Boolean,
    val providerId: String,
    val providerSessionId: String = "",
    val serverTimestampMs: Long? = null
)

enum class AsrAbortReason {
    USER_CANCELLED,
    SESSION_REPLACED,
    UPSTREAM_FINAL_SELECTED,
    PRIVACY_POLICY_CHANGED,
    NETWORK_CHANGED,
    APP_BACKGROUND,
    SESSION_CLOSED
}

sealed interface AsrEvent {
    data class Ready(
        val providerId: String,
        val providerSessionId: String,
        val transport: AsrTransport
    ) : AsrEvent

    data class SpeechStarted(
        val providerId: String,
        val providerSessionId: String,
        val sequence: Long?,
        val serverTimestampMs: Long? = null
    ) : AsrEvent

    data class Partial(val hypothesis: TranscriptHypothesis) : AsrEvent
    data class Stable(val hypothesis: TranscriptHypothesis) : AsrEvent
    data class Final(val hypothesis: TranscriptHypothesis) : AsrEvent
    data class Usage(val usage: AsrUsage) : AsrEvent
    data class Metrics(val metrics: AsrMetrics) : AsrEvent
    data class RecoverableError(val error: AsrError) : AsrEvent
    data class FatalError(val error: AsrError) : AsrEvent
    data class Closed(
        val providerId: String,
        val providerSessionId: String,
        val reasonCode: String = ""
    ) : AsrEvent
}

interface AsrProvider {
    val id: String
    suspend fun isAvailable(config: AsrSessionConfig): AsrAvailability
    suspend fun createSession(config: AsrSessionConfig): AsrSession
}

interface AsrSession : AutoCloseable {
    val events: Flow<AsrEvent>
    suspend fun start()
    suspend fun pushPcm(frame: AsrAudioFrame)
    suspend fun finishInput()
    fun requestAbort(reason: AsrAbortReason)
    override fun close()
}

package com.galaxyssi.chat.voice.tts

import com.galaxyssi.chat.voice.modelstream.CommittedSpeechChunk
import kotlinx.coroutines.flow.Flow

data class TtsSessionConfig(
    val sessionId: String,
    val traceId: String,
    val languageTag: String,
    val voiceId: String,
    val maximumQueuedChunks: Int = 12
)

data class AudioFormatDescriptor(
    val mimeType: String,
    val sampleRateHz: Int? = null,
    val channelCount: Int? = null,
    val pcmEncodingBits: Int? = null
)

data class AudioChunk(
    val utteranceId: String,
    val sequence: Long,
    val format: AudioFormatDescriptor,
    val bytes: ByteArray,
    val isFinal: Boolean
)

enum class TtsCancelReason {
    USER_STOP,
    VOICE_BARGE_IN,
    NEW_RESPONSE,
    SESSION_CHANGED,
    APP_DESTROYED,
    PLAYBACK_FAILED,
    STALE_SESSION
}

sealed interface TtsEvent {
    val sessionId: String

    data class Connected(override val sessionId: String) : TtsEvent
    data class AudioReady(override val sessionId: String, val chunk: AudioChunk) : TtsEvent
    data class PlaybackStarted(
        override val sessionId: String,
        val utteranceId: String,
        val sequence: Long
    ) : TtsEvent
    data class Completed(override val sessionId: String) : TtsEvent
    data class Cancelled(override val sessionId: String, val reason: TtsCancelReason) : TtsEvent
    data class Failed(override val sessionId: String, val code: String, val detail: String = "") : TtsEvent
}

interface StreamingTtsEngine {
    suspend fun open(config: TtsSessionConfig): TtsSession
}

interface TtsSession : AutoCloseable {
    val events: Flow<TtsEvent>
    suspend fun enqueue(chunk: CommittedSpeechChunk)
    suspend fun finish()
    fun cancel(reason: TtsCancelReason)
}

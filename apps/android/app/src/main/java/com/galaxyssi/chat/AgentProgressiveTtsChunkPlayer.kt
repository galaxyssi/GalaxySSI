package com.galaxyssi.chat

import com.galaxyssi.chat.voice.modelstream.CommittedSpeechChunk
import com.galaxyssi.chat.voice.tts.TtsChunkPlayback
import com.galaxyssi.chat.voice.tts.TtsChunkPlaybackCallbacks
import com.galaxyssi.chat.voice.tts.TtsChunkPlayer

internal class AgentProgressiveTtsChunkPlayer(
    private val activity: MainActivity
) : TtsChunkPlayer {
    override fun prefetch(chunk: CommittedSpeechChunk) {
        val config = VoiceAssistantSettings.get(activity)
        if (config.ttsProvider != VoiceAssistantSettings.PROVIDER_MICROSOFT_EDGE) return
        val voice = LanguagePolicySettings.microsoftVoice(config.ttsLanguage, config.microsoftVoice)
        val traceId = activity.activeProgressiveSpeechTraceId.takeIf {
            activity.activeProgressiveSpeechSessionId == chunk.requestId
        }.orEmpty()
        activity.microsoftTts.prefetch(
            sessionId = chunk.requestId,
            key = progressiveTtsPrefetchKey(chunk),
            text = chunk.speechText,
            voice = voice,
            traceId = traceId
        )
    }

    override fun play(
        chunk: CommittedSpeechChunk,
        callbacks: TtsChunkPlaybackCallbacks
    ): TtsChunkPlayback = activity.playProgressiveTtsChunk(chunk, callbacks)

    override fun releaseSession(sessionId: String) {
        activity.microsoftTts.clearPrefetches(sessionId)
    }
}

internal fun progressiveTtsPrefetchKey(chunk: CommittedSpeechChunk): String =
    "${chunk.requestId}:${chunk.sequence}"

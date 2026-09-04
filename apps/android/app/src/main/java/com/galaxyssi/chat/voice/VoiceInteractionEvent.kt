package com.galaxyssi.chat.voice

sealed interface VoiceInteractionEvent {
    val sessionId: String

    data class CapturePrepared(override val sessionId: String) : VoiceInteractionEvent
    data class AudioLevel(override val sessionId: String, val rms: Float) : VoiceInteractionEvent
    data class SpeechStarted(override val sessionId: String, val atElapsedNs: Long) : VoiceInteractionEvent
    data class SpeechEnded(override val sessionId: String, val atElapsedNs: Long) : VoiceInteractionEvent
    data class FinalizationStarted(override val sessionId: String) : VoiceInteractionEvent
    data class TranscriptPartial(
        override val sessionId: String,
        val value: TranscriptHypothesis
    ) : VoiceInteractionEvent
    data class TranscriptStable(
        override val sessionId: String,
        val value: TranscriptHypothesis
    ) : VoiceInteractionEvent
    data class TranscriptFinal(
        override val sessionId: String,
        val value: TranscriptHypothesis
    ) : VoiceInteractionEvent
    data class TranscriptCorrected(
        override val sessionId: String,
        val original: TranscriptHypothesis,
        val corrected: TranscriptHypothesis
    ) : VoiceInteractionEvent
    data class RouteSelected(
        override val sessionId: String,
        val decision: VoiceRouteDecision
    ) : VoiceInteractionEvent
    data class LocalActionCompleted(override val sessionId: String) : VoiceInteractionEvent
    data class ModelDelta(override val sessionId: String, val text: String) : VoiceInteractionEvent
    data class AgentRunCreated(override val sessionId: String, val runId: String) : VoiceInteractionEvent
    data class AgentAccepted(override val sessionId: String, val runId: String) : VoiceInteractionEvent
    data class AgentProgress(override val sessionId: String, val runId: String) : VoiceInteractionEvent
    data class PlaybackStarted(override val sessionId: String, val utteranceId: String) : VoiceInteractionEvent
    data class Completed(override val sessionId: String) : VoiceInteractionEvent
    data class Cancelled(override val sessionId: String, val reasonCode: String) : VoiceInteractionEvent
    data class Failed(override val sessionId: String, val failure: VoiceFailure) : VoiceInteractionEvent
}

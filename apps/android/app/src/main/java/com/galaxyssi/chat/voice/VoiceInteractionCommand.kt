package com.galaxyssi.chat.voice

sealed interface VoiceInteractionCommand {
    val sessionId: String
    val idempotencyKey: String

    data class RouteFinalTranscript(
        override val sessionId: String,
        val transcript: TranscriptHypothesis,
        override val idempotencyKey: String
    ) : VoiceInteractionCommand

    data class CancelLegacyWork(
        override val sessionId: String,
        val reasonCode: String,
        override val idempotencyKey: String
    ) : VoiceInteractionCommand
}

data class VoiceInteractionTransition(
    val previous: VoiceInteractionState,
    val current: VoiceInteractionState,
    val commands: List<VoiceInteractionCommand> = emptyList(),
    val accepted: Boolean = true
)

package com.galaxyssi.chat.voice

data class VoiceSessionResult(
    val sessionId: String,
    val completed: Boolean,
    val cancelled: Boolean,
    val route: VoiceRouteDecision? = null,
    val failure: VoiceFailure? = null,
    val finalTranscriptRevision: Int? = null
)

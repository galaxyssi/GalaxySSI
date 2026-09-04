package com.galaxyssi.chat.voice

enum class VoiceInteractionPhase {
    IDLE,
    PREPARING,
    LISTENING,
    ENDPOINTING,
    FINALIZING_ASR,
    ROUTING,
    EXECUTING_LOCAL_ACTION,
    WAITING_MODEL_FIRST_TOKEN,
    STREAMING_MODEL_TEXT,
    PLAYING_TTS,
    STARTING_AGENT,
    AGENT_RUNNING,
    COMPLETED,
    CANCELLED,
    FAILED;

    val isTerminal: Boolean
        get() = this == COMPLETED || this == CANCELLED || this == FAILED
}

data class TranscriptHypothesis(
    val text: String,
    val revision: Int,
    val provider: String = "",
    val modelProfileId: String = "",
    val confidence: Float? = null,
    val transcriptId: String = "",
    val stablePrefixLength: Int = 0,
    val isFinal: Boolean = false,
    val language: String? = null,
    val segmentStartMs: Long = 0L,
    val segmentEndMs: Long = 0L,
    val averageLogProb: Float? = null,
    val noSpeechProbability: Float? = null,
    val createdElapsedNs: Long = 0L
) {
    val providerId: String
        get() = provider
}

enum class VoiceRouteKind {
    LOCAL_ACTION,
    CLOUD_MODEL,
    REMOTE_AGENT
}

data class VoiceRouteDecision(
    val kind: VoiceRouteKind,
    val targetId: String = "",
    val reasonCode: String = ""
)

data class VoiceFailure(
    val code: String,
    val recoverable: Boolean,
    val stage: VoiceInteractionPhase,
    val detail: String = ""
)

data class VoiceInteractionState(
    val sessionId: String = "",
    val phase: VoiceInteractionPhase = VoiceInteractionPhase.IDLE,
    val partialText: String = "",
    val stableText: String = "",
    val finalText: String? = null,
    val finalTranscriptRevision: Int? = null,
    val correctedText: String? = null,
    val asrProvider: String? = null,
    val modelProfileId: String? = null,
    val route: VoiceRouteDecision? = null,
    val agentRunId: String? = null,
    val canInterrupt: Boolean = true,
    val failure: VoiceFailure? = null,
    val revision: Long = 0L,
    val createdAtElapsedNs: Long = 0L,
    val updatedAtElapsedNs: Long = 0L
)

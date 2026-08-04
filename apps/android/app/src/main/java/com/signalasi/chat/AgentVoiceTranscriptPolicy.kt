package com.signalasi.chat

internal object AgentVoiceTranscriptPolicy {
    private const val DEDUPE_PREFIX = "agent-voice-transcription:"

    fun dedupeKey(recordingName: String): String =
        "$DEDUPE_PREFIX${recordingName.trim()}"

    fun isVoiceTranscript(entry: AgentTranscriptEntry): Boolean =
        entry.role == AgentTranscriptRole.USER && entry.dedupeKey.startsWith(DEDUPE_PREFIX)

    fun isPending(entry: AgentTranscriptEntry): Boolean =
        isVoiceTranscript(entry) && entry.turnId.isBlank()
}

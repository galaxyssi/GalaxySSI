package com.galaxyssi.chat

internal data class AgentVoiceDraftSnapshot(
    val conversationId: String,
    val text: String
)

internal object AgentVoiceTranscriptPolicy {
    private const val DEDUPE_PREFIX = "agent-voice-transcription:"

    fun dedupeKey(recordingName: String): String =
        "$DEDUPE_PREFIX${recordingName.trim()}"

    fun isVoiceTranscript(entry: AgentTranscriptEntry): Boolean =
        entry.role == AgentTranscriptRole.USER && entry.dedupeKey.startsWith(DEDUPE_PREFIX)

    fun isPending(entry: AgentTranscriptEntry): Boolean =
        isVoiceTranscript(entry) && entry.turnId.isBlank()

    fun draftSnapshot(conversationId: String, text: String): AgentVoiceDraftSnapshot? =
        text.trim().takeIf(String::isNotBlank)?.let { draft ->
            AgentVoiceDraftSnapshot(conversationId.trim(), draft)
        }

    fun mergeDraftWithTranscript(draft: String, transcript: String): String {
        val left = draft.trimEnd()
        val right = transcript.trim()
        if (left.isBlank()) return right
        if (right.isBlank()) return left
        if (left.endsWith(',') || left.endsWith('\uFF0C')) return "$left $right"
        val usesCjkPunctuation = (left + right).any { character ->
            character.code in 0x3400..0x9FFF
        }
        return if (usesCjkPunctuation) "$left\uFF0C$right" else "$left, $right"
    }
}

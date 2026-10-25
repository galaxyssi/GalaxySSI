package com.galaxyssi.chat

import com.galaxyssi.chat.voice.modelstream.SpeechTextNormalizer

/** Only identifiers and a normalized character offset cross the service boundary. */
internal data class VoiceReplySelection(
    val conversationId: String,
    val entryId: String,
    val offset: Int = 0
) {
    fun text(entry: AgentTranscriptEntry?): String? {
        if (entry == null || entry.id != entryId || entry.conversationId != conversationId) return null
        val target = AgentReplySpeechPresentationPolicy.target(entry) ?: return null
        if (!target.complete) return null
        return SpeechTextNormalizer.normalize(target.text).takeIf { it.isNotBlank() }
    }

    companion object {
        fun fromParagraph(entry: AgentTranscriptEntry, source: String, offset: Int): VoiceReplySelection? {
            val target = AgentReplySpeechPresentationPolicy.target(entry)?.takeIf { it.complete } ?: return null
            if (offset !in 0..source.length) return null
            val full = SpeechTextNormalizer.normalize(target.text)
            val sourceStart = full.indexOf(SpeechTextNormalizer.normalize(source))
            if (sourceStart < 0) return null
            val prefix = SpeechTextNormalizer.normalize(source.substring(0, offset))
            // Normalize the suffix too: whitespace trimming must not cut the first spoken word.
            val suffix = SpeechTextNormalizer.normalize(source.substring(offset))
            val start = full.indexOf(suffix, sourceStart + prefix.length)
            if (start < 0 || suffix.isBlank()) return null
            return VoiceReplySelection(entry.conversationId, entry.id, start)
        }
    }
}

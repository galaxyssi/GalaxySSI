package com.galaxyssi.chat

/** Follow a hydrated final row only when its business result is unchanged. */
internal fun resolveBusinessReply(
    entries: List<AgentTranscriptEntry>, reference: AgentTranscriptEntry
): AgentTranscriptEntry? {
    if (reference.conversationId.isBlank() || reference.turnId.isBlank()) return null
    val expected = AgentRichContentCodec.decode(reference.richOutputJson)
    return entries.lastOrNull { candidate ->
        candidate.role == AgentTranscriptRole.ASSISTANT &&
            !AgentTranscriptRenderPolicy.isLiveStream(candidate) &&
            !candidate.dedupeKey.startsWith("remote-approval:") &&
            candidate.conversationId == reference.conversationId &&
            candidate.turnId == reference.turnId && candidate.taskId == reference.taskId &&
            candidate.text == reference.text &&
            (candidate.richOutputJson == reference.richOutputJson || run {
                val actual = AgentRichContentCodec.decode(candidate.richOutputJson)
                expected.isNotEmpty() && actual.size == expected.size && expected.zip(actual).all { (a, b) ->
                    if (a.type !in setOf(AgentRichBlockType.IMAGE, AgentRichBlockType.FILE)) a == b
                    else {
                        val hash = a.metadata["sha256"].orEmpty().lowercase()
                        hash.matches(Regex("[0-9a-f]{64}")) && hash == b.metadata["sha256"].orEmpty().lowercase() &&
                            a.id == b.id && a.type == b.type && a.mimeType == b.mimeType &&
                            a.title == b.title && a.text == b.text
                    }
                }
            })
    }
}

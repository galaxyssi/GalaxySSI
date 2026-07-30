package com.signalasi.chat

data class AgentTranscriptRenderDiff(
    val reset: Boolean,
    val replacementIndices: List<Int>,
    val appendFromIndex: Int
)

object AgentTranscriptRenderPolicy {
    fun signature(entry: AgentTranscriptEntry): Int {
        var result = entry.id.hashCode()
        result = 31 * result + entry.role.hashCode()
        result = 31 * result + entry.timestampMillis.hashCode()
        result = 31 * result + entry.dedupeKey.hashCode()
        result = 31 * result + entry.conversationId.hashCode()
        result = 31 * result + entry.turnId.hashCode()
        result = 31 * result + entry.taskId.hashCode()
        result = 31 * result + if (entry.textSha256.isBlank()) {
            entry.text.hashCode()
        } else {
            entry.textSha256.hashCode()
        }
        result = 31 * result + entry.text.length
        result = 31 * result + if (entry.richOutputSha256.isBlank()) {
            entry.richOutputJson.hashCode()
        } else {
            entry.richOutputSha256.hashCode()
        }
        result = 31 * result + entry.richOutputJson.length
        result = 31 * result + entry.sourceConversationId.hashCode()
        result = 31 * result + entry.sourceConversationTitle.hashCode()
        result = 31 * result + entry.sourceEntryId.hashCode()
        return result
    }

    fun diff(
        renderedIds: List<String>,
        renderedSignatures: Map<String, Int>,
        incoming: List<AgentTranscriptEntry>
    ): AgentTranscriptRenderDiff {
        val incomingIds = incoming.map(AgentTranscriptEntry::id)
        val hasStablePrefix = renderedIds.size <= incomingIds.size &&
            incomingIds.take(renderedIds.size) == renderedIds
        if (!hasStablePrefix) {
            return AgentTranscriptRenderDiff(
                reset = true,
                replacementIndices = emptyList(),
                appendFromIndex = 0
            )
        }
        val signatureReplacements = renderedIds.indices.filter { index ->
            val entry = incoming[index]
            renderedSignatures[entry.id] != signature(entry)
        }
        val changedAssistantGroups = incoming.withIndex()
            .filter { (index, entry) ->
                entry.role == AgentTranscriptRole.ASSISTANT &&
                    (index >= renderedIds.size || index in signatureReplacements)
            }
            .map { (_, entry) -> AgentTranscriptPresentationPolicy.processGroupKey(entry) }
            .toSet()
        val processCompletionReplacements = renderedIds.indices.filter { index ->
            val entry = incoming[index]
            entry.role == AgentTranscriptRole.PROCESS &&
                AgentTranscriptPresentationPolicy.processGroupKey(entry) in changedAssistantGroups
        }
        val replacements = (signatureReplacements + processCompletionReplacements)
            .distinct()
            .sorted()
        return AgentTranscriptRenderDiff(
            reset = false,
            replacementIndices = replacements,
            appendFromIndex = renderedIds.size
        )
    }
}

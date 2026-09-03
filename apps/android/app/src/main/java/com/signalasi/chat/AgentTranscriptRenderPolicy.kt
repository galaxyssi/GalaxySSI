package com.signalasi.chat

data class AgentTranscriptRenderDiff(
    val reset: Boolean,
    val replacementIndices: List<Int>,
    val appendFromIndex: Int
)

object AgentTranscriptRenderPolicy {
    fun identity(entry: AgentTranscriptEntry): String =
        entry.dedupeKey.trim().takeIf(String::isNotBlank) ?: entry.id

    fun sameItem(previous: AgentTranscriptEntry, current: AgentTranscriptEntry): Boolean =
        identity(previous) == identity(current)

    fun sameContent(previous: AgentTranscriptEntry, current: AgentTranscriptEntry): Boolean =
        signature(previous) == signature(current)

    fun isLiveStream(entry: AgentTranscriptEntry): Boolean =
        entry.role == AgentTranscriptRole.ASSISTANT && entry.id.startsWith("agent-stream-")

    fun processGroupSignatures(entries: Collection<AgentTranscriptEntry>): Map<String, Int> =
        entries.asSequence()
            .filter { it.role == AgentTranscriptRole.PROCESS }
            .groupBy(AgentTranscriptPresentationPolicy::processGroupKey)
            .mapValues { (_, groupEntries) ->
                val visibleNarration = groupEntries
                    .sortedBy(AgentTranscriptEntry::timestampMillis)
                    .distinctBy { entry ->
                        AgentTranscriptPresentationPolicy.processNarrationIdentity(entry.text)
                    }
                    .let(AgentTranscriptPresentationPolicy::narrationSegments)
                    .flatMap(AgentTranscriptPresentationPolicy.ProcessSegment::entries)
                visibleNarration.fold(1) { result, entry ->
                    31 * result + sourceProcessSignature(entry)
                }
            }

    private fun sourceProcessSignature(entry: AgentTranscriptEntry): Int {
        var result = AgentTranscriptPresentationPolicy.processNarrationIdentity(entry.text).hashCode()
        result = 31 * result + entry.richOutputJson.hashCode()
        result = 31 * result + entry.textSha256.hashCode()
        result = 31 * result + entry.richOutputSha256.hashCode()
        return result
    }

    fun signature(entry: AgentTranscriptEntry): Int {
        var result = entry.role.hashCode()
        if (entry.role != AgentTranscriptRole.ASSISTANT) {
            result = 31 * result + entry.timestampMillis.hashCode()
        }
        result = 31 * result + entry.turnId.hashCode()
        result = 31 * result + entry.taskId.hashCode()
        result = 31 * result + if (entry.textSha256.isBlank()) {
            entry.text.hashCode()
        } else {
            entry.textSha256.hashCode()
        }
        result = 31 * result + entry.text.length
        result = 31 * result + entry.textChunkCount
        result = 31 * result + entry.textLength
        result = 31 * result + if (entry.richOutputSha256.isBlank()) {
            entry.richOutputJson.hashCode()
        } else {
            entry.richOutputSha256.hashCode()
        }
        result = 31 * result + entry.richOutputJson.length
        result = 31 * result + entry.richOutputChunkCount
        result = 31 * result + entry.richOutputLength
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
        val incomingIds = incoming.map(::identity)
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
            renderedSignatures[identity(entry)] != signature(entry)
        }
        val changedAssistantGroups = incoming.withIndex()
            .filter { (index, entry) ->
                entry.role == AgentTranscriptRole.ASSISTANT &&
                    (
                        index >= renderedIds.size ||
                            (!isLiveStream(entry) && index in signatureReplacements)
                        )
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

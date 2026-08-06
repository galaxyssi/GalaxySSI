package com.signalasi.chat

internal data class PendingAgentReplyIndicator(
    val conversationId: String,
    val turnId: String,
    val startedAtMillis: Long
)

internal data class AgentReplyWaitingRenderResult(
    val entries: List<AgentTranscriptEntry>,
    val resolvedTurnIds: Set<String>
)

internal object AgentReplyWaitingIndicatorPolicy {
    private const val DEDUPE_PREFIX = "ui-reply-waiting:"

    fun apply(
        entries: List<AgentTranscriptEntry>,
        pending: Collection<PendingAgentReplyIndicator>,
        conversationId: String
    ): AgentReplyWaitingRenderResult {
        val assistantTurnIds = entries.asSequence()
            .filter { entry ->
                entry.role == AgentTranscriptRole.ASSISTANT && !isIndicator(entry)
            }
            .flatMap { entry -> sequenceOf(entry.turnId, entry.taskId) }
            .filter(String::isNotBlank)
            .toSet()
        val relevant = pending.filter { indicator ->
            indicator.conversationId == conversationId && indicator.turnId.isNotBlank()
        }
        val resolved = relevant.asSequence()
            .map(PendingAgentReplyIndicator::turnId)
            .filter(assistantTurnIds::contains)
            .toSet()
        val indicators = relevant.asSequence()
            .filterNot { it.turnId in resolved }
            .map(::entry)
            .toList()
        return AgentReplyWaitingRenderResult(
            entries = (entries + indicators).sortedBy(AgentTranscriptEntry::timestampMillis),
            resolvedTurnIds = resolved
        )
    }

    fun isIndicator(entry: AgentTranscriptEntry): Boolean =
        entry.dedupeKey.startsWith(DEDUPE_PREFIX)

    fun stopsFor(phase: AgentPhase): Boolean = phase in setOf(
        AgentPhase.WAITING_CONFIRMATION,
        AgentPhase.PAUSED,
        AgentPhase.BLOCKED,
        AgentPhase.COMPLETED,
        AgentPhase.FAILED,
        AgentPhase.CANCELLED
    )

    private fun entry(indicator: PendingAgentReplyIndicator): AgentTranscriptEntry =
        AgentTranscriptEntry(
            id = "${DEDUPE_PREFIX}${indicator.conversationId}:${indicator.turnId}",
            role = AgentTranscriptRole.ASSISTANT,
            text = "...",
            timestampMillis = indicator.startedAtMillis,
            dedupeKey = "${DEDUPE_PREFIX}${indicator.turnId}",
            conversationId = indicator.conversationId,
            turnId = indicator.turnId,
            taskId = indicator.turnId
        )
}

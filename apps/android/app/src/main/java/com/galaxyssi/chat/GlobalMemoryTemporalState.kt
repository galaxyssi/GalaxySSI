package com.galaxyssi.chat

data class GlobalMemoryTemporalSnapshot(
    val current: List<GlobalWorldItem> = emptyList(),
    val historical: List<GlobalWorldItem> = emptyList(),
    val planned: List<GlobalWorldItem> = emptyList(),
    val deprecated: List<GlobalWorldItem> = emptyList(),
    val conflicted: List<GlobalWorldItem> = emptyList(),
    val pending: List<GlobalWorldItem> = emptyList(),
    val pendingCandidates: List<GlobalMemoryCandidate> = emptyList(),
    val conflictedCandidates: List<GlobalMemoryCandidate> = emptyList()
) {
    fun accepted(state: GlobalMemoryTemporalState): List<GlobalWorldItem> = when (state) {
        GlobalMemoryTemporalState.CURRENT -> current
        GlobalMemoryTemporalState.HISTORICAL -> historical
        GlobalMemoryTemporalState.PLANNED -> planned
        GlobalMemoryTemporalState.DEPRECATED -> deprecated
        GlobalMemoryTemporalState.CONFLICTED -> conflicted
        GlobalMemoryTemporalState.PENDING -> pending
    }

    fun count(state: GlobalMemoryTemporalState): Int = accepted(state).size + when (state) {
        GlobalMemoryTemporalState.PENDING -> pendingCandidates.size
        GlobalMemoryTemporalState.CONFLICTED -> conflictedCandidates.size
        else -> 0
    }
}

object GlobalMemoryTemporalPolicy {
    fun classify(item: GlobalWorldItem): GlobalMemoryTemporalState = when (item.status) {
        GlobalWorldItemStatus.SUPERSEDED -> GlobalMemoryTemporalState.DEPRECATED
        GlobalWorldItemStatus.COMPLETED -> GlobalMemoryTemporalState.HISTORICAL
        GlobalWorldItemStatus.CONFLICTED -> GlobalMemoryTemporalState.CONFLICTED
        GlobalWorldItemStatus.ACTIVE -> item.temporalState
    }

    fun snapshot(
        world: PersonalWorldModel,
        inbox: GlobalMemoryInbox
    ): GlobalMemoryTemporalSnapshot {
        val grouped = world.items.groupBy(::classify)
        return GlobalMemoryTemporalSnapshot(
            current = grouped[GlobalMemoryTemporalState.CURRENT].orEmpty()
                .sortedByDescending(GlobalWorldItem::lastSeenAtMillis),
            historical = grouped[GlobalMemoryTemporalState.HISTORICAL].orEmpty()
                .sortedByDescending(GlobalWorldItem::lastSeenAtMillis),
            planned = grouped[GlobalMemoryTemporalState.PLANNED].orEmpty()
                .sortedByDescending(GlobalWorldItem::lastSeenAtMillis),
            deprecated = grouped[GlobalMemoryTemporalState.DEPRECATED].orEmpty()
                .sortedByDescending(GlobalWorldItem::lastSeenAtMillis),
            conflicted = grouped[GlobalMemoryTemporalState.CONFLICTED].orEmpty()
                .sortedByDescending(GlobalWorldItem::lastSeenAtMillis),
            pending = grouped[GlobalMemoryTemporalState.PENDING].orEmpty()
                .sortedByDescending(GlobalWorldItem::lastSeenAtMillis),
            pendingCandidates = inbox.candidates
                .filter { it.status == GlobalMemoryCandidateStatus.PENDING_REVIEW }
                .sortedByDescending(GlobalMemoryCandidate::createdAtMillis),
            conflictedCandidates = inbox.candidates
                .filter { it.status == GlobalMemoryCandidateStatus.CONFLICTED }
                .sortedByDescending(GlobalMemoryCandidate::createdAtMillis)
        )
    }
}

package com.galaxyssi.chat

internal object CollaborationLabelPolicy {
    fun provider(label: String, model: String): String = (label.split(" · ") + model)
        .map(String::trim).filter(String::isNotBlank).distinct().joinToString(" · ")
}

/** A group has its own projection; single-Agent process collapsing must never select its rows. */
internal object CollaborationPagePolicy {
    fun project(entries: List<AgentTranscriptEntry>): List<AgentTranscriptEntry> {
        val canonical = AgentFinalResponseIdentity.coalesce(entries)
        val decoded = canonical.mapNotNull { entry ->
            CollaborationTranscriptMetadata.decode(entry.collaborationJson)?.let { entry to it }
        }
        val activities = decoded.filter { it.second.activity }.groupBy { it.second.traceTurnId }
        val assignments = decoded.filter { !it.second.activity && !it.second.result }.associateBy { it.second.traceTurnId }
        fun withHistory(metadata: CollaborationTranscriptMetadata): CollaborationTranscriptMetadata {
            val history = activities[metadata.traceTurnId].orEmpty().sortedBy { it.first.timestampMillis }
            val assignment = assignments[metadata.traceTurnId]?.second
            return metadata.copy(summary = history.lastOrNull()?.first?.text.orEmpty(), eventCount = history.size,
                startedAtMillis = metadata.startedAtMillis.takeIf { it > 0L } ?: assignment?.startedAtMillis ?: 0L,
                details = (listOfNotNull(assignments[metadata.traceTurnId]?.first?.text) + history.takeLast(100).map { it.first.text })
                    .joinToString("\n\n"))
        }
        val results = decoded.filter { it.second.result }.mapTo(hashSetOf()) { it.second.traceTurnId }
        val primaryResults = decoded.filter { it.second.primary && it.second.result }
        fun match(answer: AgentTranscriptEntry) = primaryResults.firstOrNull { (entry, _) ->
            entry.taskId == answer.taskId && entry.conversationId == answer.conversationId &&
                entry.text.trim() == answer.text.trim()
        }
        val canonicalMatches = canonical.filter { it.role == AgentTranscriptRole.ASSISTANT }.mapNotNull(::match)
            .mapTo(hashSetOf()) { it.first.id }
        val emittedActivities = hashSetOf<String>()
        return buildList {
            canonical.forEach { entry ->
                val metadata = CollaborationTranscriptMetadata.decode(entry.collaborationJson)
                when {
                    metadata?.activity == true -> Unit
                    metadata?.result == true -> if (entry.id !in canonicalMatches)
                        add(entry.copy(collaborationJson = withHistory(metadata).encode()))
                    metadata != null -> {
                        emittedActivities += metadata.traceTurnId
                        if (metadata.traceTurnId !in results && metadata.status != AgentSubagentStatus.SUCCEEDED)
                            add(entry.copy(collaborationJson = withHistory(metadata).encode()))
                    }
                    entry.role == AgentTranscriptRole.USER -> add(entry)
                    entry.role == AgentTranscriptRole.ASSISTANT -> add(match(entry)?.let {
                        entry.copy(collaborationJson = withHistory(it.second.copy(completedAtMillis =
                            it.second.completedAtMillis.takeIf { at -> at > 0L } ?: it.first.timestampMillis)).encode())
                    } ?: entry)
                    // Approval/control cards must stay actionable, but never masquerade as a member search.
                    entry.dedupeKey.startsWith("remote-approval:") || entry.dedupeKey.startsWith("approval:") ||
                        entry.dedupeKey.startsWith("agent-failure:") -> add(entry)
                }
            }
            // A paged window can contain activity without its earlier status row.
            activities.filterKeys { it !in emittedActivities && it !in results }.values.forEach { history ->
                val latest = history.maxBy { it.first.timestampMillis }
                add(latest.first.copy(text = history.sortedBy { it.first.timestampMillis }.joinToString("\n\n") { it.first.text },
                    collaborationJson = withHistory(latest.second.copy(activity = false,
                        clockStoppedAtMillis = latest.first.timestampMillis)).encode()))
            }
        }
    }
}

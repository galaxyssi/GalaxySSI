package com.galaxyssi.chat

internal object CollaborationLabelPolicy {
    fun provider(label: String, model: String): String = (label.split(" · ") + model)
        .map(String::trim).filter(String::isNotBlank).distinct().joinToString(" · ")
}

/** A group has its own projection; single-Agent process collapsing must never select its rows. */
internal object CollaborationPagePolicy {
    fun project(entries: List<AgentTranscriptEntry>): List<AgentTranscriptEntry> {
        val canonical = AgentFinalResponseIdentity.coalesce(entries)
        val positions = canonical.withIndex().associate { it.value.id to it.index }
        val decoded = canonical.mapNotNull { entry ->
            CollaborationTranscriptMetadata.decode(entry.collaborationJson)?.let { entry to it }
        }
        val activities = decoded.filter { it.second.activity }.groupBy { it.second.traceTurnId }
        val assignments = decoded.filter { !it.second.activity && !it.second.result }.associateBy { it.second.traceTurnId }
        fun person(row: Pair<AgentTranscriptEntry, CollaborationTranscriptMetadata>) =
            row.first.conversationId to row.second.memberId
        // Task IDs identify attempts; a person ID identifies the one current member status.
        // Late activity from an older attempt must not make it current again.
        val attempts = decoded.groupBy { it.second.traceTurnId }.values.map { rows ->
            rows.firstOrNull { !it.second.activity && !it.second.result } ?: rows.first()
        }
        val attemptByTrace = attempts.associateBy { it.second.traceTurnId }
        val resultTraces = decoded.filter { it.second.result }.mapTo(hashSetOf()) { it.second.traceTurnId }
        val attemptOrder = compareBy<Pair<AgentTranscriptEntry, CollaborationTranscriptMetadata>> {
            it.second.startedAtMillis.takeIf { at -> at > 0L } ?: it.first.timestampMillis
        }.thenBy { positions[it.first.id] ?: 0 }
        val latestByPerson = attempts.groupBy(::person).mapValues { (_, rows) ->
            val newest = rows.maxWith(attemptOrder)
            // A newer parallel result must not hide this person's still-running work.
            rows.filter { it.second.runId == newest.second.runId && it.second.status == AgentSubagentStatus.RUNNING &&
                it.second.traceTurnId !in resultTraces }.maxWithOrNull(attemptOrder) ?: newest
        }
        val priorAssignments = assignments.values.groupBy(::person)
        fun withHistory(metadata: CollaborationTranscriptMetadata): CollaborationTranscriptMetadata {
            val history = activities[metadata.traceTurnId].orEmpty().sortedBy { it.first.timestampMillis }
            val assignment = assignments[metadata.traceTurnId]?.second
            val latestActivity = history.lastOrNull()
            val connection = latestActivity?.second?.connectionState.orEmpty()
            val entry = attemptByTrace[metadata.traceTurnId]?.first
            val previous = if (entry != null && latestByPerson[entry.conversationId to metadata.memberId]?.second?.traceTurnId == metadata.traceTurnId)
                priorAssignments[entry.conversationId to metadata.memberId].orEmpty()
                    .filter { it.second.traceTurnId != metadata.traceTurnId }
                    .flatMap { prior -> listOf("[${prior.second.status.name} / ${prior.second.researchStage}] ${prior.first.text}") +
                        activities[prior.second.traceTurnId].orEmpty().sortedBy { it.first.timestampMillis }.map { it.first.text } }
                else emptyList()
            val summary = if (metadata.summary.isNotBlank() &&
                (latestActivity?.first?.timestampMillis ?: 0L) <= metadata.clockStoppedAtMillis) metadata.summary
                else latestActivity?.first?.text ?: metadata.summary
            return metadata.copy(summary = summary, eventCount = history.size,
                connectionState = if (metadata.result || metadata.status.isTerminal) "" else connection,
                startedAtMillis = metadata.startedAtMillis.takeIf { it > 0L } ?: assignment?.startedAtMillis ?: 0L,
                details = (previous + listOfNotNull(assignments[metadata.traceTurnId]?.first?.text) + history.takeLast(100).map { it.first.text })
                    .joinToString("\n\n"))
        }
        val results = resultTraces
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
                        if (latestByPerson[entry.conversationId to metadata.memberId]?.second?.traceTurnId == metadata.traceTurnId &&
                            metadata.traceTurnId !in results && metadata.status != AgentSubagentStatus.SUCCEEDED)
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
                if (latestByPerson[person(latest)]?.second?.traceTurnId != latest.second.traceTurnId) return@forEach
                add(latest.first.copy(text = history.sortedBy { it.first.timestampMillis }.joinToString("\n\n") { it.first.text },
                    collaborationJson = withHistory(latest.second.copy(activity = false,
                        clockStoppedAtMillis = latest.first.timestampMillis)).encode()))
            }
        }
    }
}

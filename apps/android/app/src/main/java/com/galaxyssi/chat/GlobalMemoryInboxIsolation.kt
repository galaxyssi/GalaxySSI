package com.galaxyssi.chat

data class GlobalMemoryInboxIsolationReport(
    val violations: List<String> = emptyList()
) {
    val isSafe: Boolean
        get() = violations.isEmpty()

    fun requireSafe() {
        check(isSafe) {
            "Memory Inbox isolation failed: ${violations.joinToString(",").take(1_000)}"
        }
    }
}

object GlobalMemoryInboxIsolationPolicy {
    private val isolatedStatuses = setOf(
        GlobalMemoryCandidateStatus.PENDING_REVIEW,
        GlobalMemoryCandidateStatus.CONFLICTED,
        GlobalMemoryCandidateStatus.REJECTED
    )

    fun inspect(
        world: PersonalWorldModel,
        topicGraph: GlobalTopicProjectGraph,
        entityGraph: GlobalEntityMemoryGraph,
        inbox: GlobalMemoryInbox
    ): GlobalMemoryInboxIsolationReport {
        val isolated = inbox.candidates.filter { it.status in isolatedStatuses }
        if (isolated.isEmpty()) return GlobalMemoryInboxIsolationReport()

        val sourceEventIds = isolated.mapTo(mutableSetOf(), GlobalMemoryCandidate::sourceEventId)
        val candidateItemIds = isolated.mapTo(mutableSetOf()) { it.item.id }
        val violations = buildList {
            isolated.asSequence()
                .filter { it.risk == GlobalMemoryCandidateRisk.PRIVATE_BLOCKED }
                .filter {
                    it.item.value.isNotBlank() ||
                        it.item.topic != PRIVATE_CANDIDATE_TOPIC ||
                        it.item.contextVisibility != GlobalWorldContextVisibility.LOCAL_ONLY
                }
                .forEach { add("private_candidate_not_redacted:${it.id}") }

            world.items.asSequence()
                .filter { item ->
                    item.id in candidateItemIds ||
                        item.evidenceEventIds.any(sourceEventIds::contains) ||
                        item.evidenceProvenance.any { it.references(sourceEventIds) }
                }
                .forEach { add("world_item:${it.id}") }

            world.links.asSequence()
                .filter { link -> link.evidenceProvenance.any { it.references(sourceEventIds) } }
                .forEach { add("world_link:${it.id}") }

            topicGraph.nodes.asSequence()
                .filter { node ->
                    node.worldItemIds.any(candidateItemIds::contains) ||
                        node.evidenceEventIds.any(sourceEventIds::contains) ||
                        node.evidenceProvenance.any { it.references(sourceEventIds) }
                }
                .forEach { add("topic_node:${it.id}") }

            topicGraph.relations.asSequence()
                .filter { relation ->
                    relation.evidenceEventIds.any(sourceEventIds::contains) ||
                        relation.evidenceProvenance.any { it.references(sourceEventIds) }
                }
                .forEach { add("topic_relation:${it.id}") }

            entityGraph.nodes.asSequence()
                .filter { node -> node.evidence.any { it.references(sourceEventIds) } }
                .forEach { add("entity_node:${it.id}") }

            entityGraph.relations.asSequence()
                .filter { relation -> relation.evidence.any { it.references(sourceEventIds) } }
                .forEach { add("entity_relation:${it.id}") }
        }.distinct().take(MAX_REPORTED_VIOLATIONS)

        return GlobalMemoryInboxIsolationReport(violations)
    }

    private fun GlobalEvidenceRef.references(eventIds: Set<String>): Boolean =
        eventId in eventIds || causalEventIds.any(eventIds::contains)

    private const val PRIVATE_CANDIDATE_TOPIC = "Private memory candidate"
    private const val MAX_REPORTED_VIOLATIONS = 40
}

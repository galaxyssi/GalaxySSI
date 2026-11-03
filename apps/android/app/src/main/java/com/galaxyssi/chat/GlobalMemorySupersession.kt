package com.galaxyssi.chat

data class GlobalMemorySupersessionEdge(
    val previousItemId: String,
    val replacementItemId: String
)

data class GlobalMemorySupersessionTrace(
    val items: List<GlobalWorldItem> = emptyList(),
    val edges: List<GlobalMemorySupersessionEdge> = emptyList(),
    val evidenceEventIds: List<String> = emptyList(),
    val complete: Boolean = true
)

internal class GlobalMemorySupersessionException(violations: List<String>) :
    IllegalStateException("Invalid memory supersession chain: ${violations.joinToString("; ")}")

data class GlobalMemorySupersessionIntegrityReport(
    val edges: List<GlobalMemorySupersessionEdge> = emptyList(),
    val violations: List<String> = emptyList()
) {
    fun requireSafe() {
        if (violations.isNotEmpty()) throw GlobalMemorySupersessionException(violations)
    }
}

object GlobalMemorySupersessionPolicy {
    /** Restore only the inverse links lost by the former twelve-link truncation. */
    fun restoreTruncatedForwardLinks(world: PersonalWorldModel): PersonalWorldModel {
        val report = inspect(world)
        if (report.violations.isEmpty() || report.violations.any { !it.startsWith("missing_forward:") }) return world
        val byId = world.items.associateBy(GlobalWorldItem::id)
        if (byId.size != world.items.size) return world
        val additions = mutableMapOf<String, MutableList<String>>()
        world.items.forEach { previous ->
            val successor = byId[previous.supersededByItemId] ?: return@forEach
            if (previous.id !in successor.supersedesItemIds) {
                if (previous.status != GlobalWorldItemStatus.SUPERSEDED ||
                    !GlobalMemoryNamespacePolicy.same(previous, successor)) return world
                additions.getOrPut(successor.id) { mutableListOf() }.add(previous.id)
            }
        }
        val repaired = world.copy(items = world.items.map { item ->
            additions[item.id]?.let { item.copy(supersedesItemIds = (item.supersedesItemIds + it).distinct()) } ?: item
        })
        inspect(repaired).requireSafe()
        return repaired
    }

    fun inspect(world: PersonalWorldModel): GlobalMemorySupersessionIntegrityReport {
        val byId = world.items.associateBy(GlobalWorldItem::id)
        val edges = edges(world)
        val violations = mutableListOf<String>()
        world.items.forEach { replacement ->
            replacement.supersedesItemIds
                .filter(String::isNotBlank)
                .distinct()
                .forEach { previousId ->
                    val previous = byId[previousId]
                    when {
                        previous == null -> violations += "missing_previous:$previousId"
                        previous.id == replacement.id -> violations += "self_reference:${replacement.id}"
                        previous.supersededByItemId != replacement.id ->
                            violations += "missing_reverse:${previous.id}:${replacement.id}"
                        previous.status != GlobalWorldItemStatus.SUPERSEDED ->
                            violations += "previous_not_superseded:${previous.id}"
                        !GlobalMemoryNamespacePolicy.same(previous, replacement) ->
                            violations += "cross_namespace:${previous.id}:${replacement.id}"
                    }
                }
            replacement.supersededByItemId
                .takeIf(String::isNotBlank)
                ?.let { replacementId ->
                    val successor = byId[replacementId]
                    when {
                        successor == null -> violations += "missing_replacement:$replacementId"
                        replacement.id !in successor.supersedesItemIds ->
                            violations += "missing_forward:${replacement.id}:$replacementId"
                        !GlobalMemoryNamespacePolicy.same(replacement, successor) ->
                            violations += "cross_namespace:${replacement.id}:$replacementId"
                    }
                }
        }
        if (containsCycle(edges)) violations += "cycle"
        return GlobalMemorySupersessionIntegrityReport(
            edges = edges,
            violations = violations.distinct()
        )
    }

    fun trace(world: PersonalWorldModel, itemId: String): GlobalMemorySupersessionTrace {
        val byId = world.items.associateBy(GlobalWorldItem::id)
        if (itemId !in byId) return GlobalMemorySupersessionTrace(complete = false)
        val edges = edges(world)
        val adjacent = mutableMapOf<String, MutableSet<String>>()
        edges.forEach { edge ->
            adjacent.getOrPut(edge.previousItemId) { linkedSetOf() } += edge.replacementItemId
            adjacent.getOrPut(edge.replacementItemId) { linkedSetOf() } += edge.previousItemId
        }
        val connectedIds = linkedSetOf<String>()
        val queue = ArrayDeque<String>()
        queue += itemId
        while (queue.isNotEmpty()) {
            val current = queue.removeFirst()
            if (!connectedIds.add(current)) continue
            adjacent[current].orEmpty().forEach(queue::addLast)
        }
        val connectedEdges = edges.filter {
            it.previousItemId in connectedIds || it.replacementItemId in connectedIds
        }
        val connectedItems = connectedIds.mapNotNull(byId::get)
            .sortedWith(
                compareBy<GlobalWorldItem>(GlobalWorldItem::firstSeenAtMillis)
                    .thenBy(GlobalWorldItem::lastSeenAtMillis)
            )
        val complete = connectedEdges.all {
            it.previousItemId in byId && it.replacementItemId in byId
        } && !containsCycle(connectedEdges)
        return GlobalMemorySupersessionTrace(
            items = connectedItems,
            edges = connectedEdges,
            evidenceEventIds = connectedItems
                .flatMap(GlobalWorldItem::evidenceEventIds)
                .filter(String::isNotBlank)
                .distinct(),
            complete = complete
        )
    }

    private fun edges(world: PersonalWorldModel): List<GlobalMemorySupersessionEdge> =
        buildList {
            world.items.forEach { item ->
                item.supersedesItemIds.filter(String::isNotBlank).forEach { previousId ->
                    add(GlobalMemorySupersessionEdge(previousId, item.id))
                }
                item.supersededByItemId.takeIf(String::isNotBlank)?.let { replacementId ->
                    add(GlobalMemorySupersessionEdge(item.id, replacementId))
                }
            }
        }.distinct()

    private fun containsCycle(edges: List<GlobalMemorySupersessionEdge>): Boolean {
        val outgoing = edges.groupBy(
            GlobalMemorySupersessionEdge::previousItemId,
            GlobalMemorySupersessionEdge::replacementItemId
        )
        val visiting = mutableSetOf<String>()
        val visited = mutableSetOf<String>()
        fun visit(itemId: String): Boolean {
            if (itemId in visiting) return true
            if (!visited.add(itemId)) return false
            visiting += itemId
            val cycle = outgoing[itemId].orEmpty().any(::visit)
            visiting -= itemId
            return cycle
        }
        return edges.any { visit(it.previousItemId) }
    }
}

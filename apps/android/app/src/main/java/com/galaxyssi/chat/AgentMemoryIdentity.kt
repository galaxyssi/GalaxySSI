package com.galaxyssi.chat

import java.util.UUID

internal object AgentMemoryIdentity {
    fun sameNamespace(first: AgentMemoryItem, second: AgentMemoryItem): Boolean =
        first.kind == second.kind && first.scope == second.scope && first.scopeId == second.scopeId

    fun sameKey(first: AgentMemoryItem, second: AgentMemoryItem): Boolean =
        sameNamespace(first, second) && first.key == second.key

    private data class Key(
        val kind: AgentMemoryKind,
        val scope: AgentMemoryScope,
        val scopeId: String,
        val key: String
    )

    private fun key(item: AgentMemoryItem) = Key(item.kind, item.scope, item.scopeId, item.key)

    // Old stores grouped conflicts without a namespace. Repair only those groups,
    // preserving values, provenance, privacy and the ordering of the original rows.
    fun normalizeConflicts(items: List<AgentMemoryItem>): List<AgentMemoryItem> {
        val replacements = mutableMapOf<String, AgentMemoryItem>()
        items.filter { it.status == AgentMemoryStatus.CONFLICTED }
            .groupBy { it.conflictGroupId }.forEach { (groupId, group) ->
                val partitions = group.groupBy(::key)
                partitions.forEach { (_, candidates) ->
                    if (candidates.size == 1) {
                        val item = candidates.single()
                        replacements[item.id] = item.copy(status = AgentMemoryStatus.ACTIVE, conflictGroupId = "")
                    } else if (partitions.size > 1 || groupId.isBlank()) {
                        val first = candidates.first()
                        val encoded = listOf(groupId, first.kind.name, first.scope.name, first.scopeId, first.key)
                            .joinToString("") { "${it.length}:$it" }
                        val scopedId = UUID.nameUUIDFromBytes(encoded.toByteArray(Charsets.UTF_8)).toString()
                        candidates.forEach { replacements[it.id] = it.copy(conflictGroupId = scopedId) }
                    }
                }
            }
        return if (replacements.isEmpty()) items else items.map { replacements[it.id] ?: it }
    }

    fun conflictCandidates(items: List<AgentMemoryItem>, groupId: String, selectedId: String): List<AgentMemoryItem> {
        val selected = items.firstOrNull {
            it.id == selectedId && it.conflictGroupId == groupId && it.status == AgentMemoryStatus.CONFLICTED
        } ?: return emptyList()
        return items.filter {
            it.conflictGroupId == groupId && it.status == AgentMemoryStatus.CONFLICTED && sameKey(it, selected)
        }
    }

    fun lineageIds(items: List<AgentMemoryItem>, target: AgentMemoryItem): Set<String> {
        val scoped = items.filter { sameNamespace(it, target) }.associateBy { it.id }
        val children = scoped.values.groupBy { it.supersedesId }
        val pending = ArrayDeque<String>().apply { add(target.id) }
        val visited = mutableSetOf<String>()
        while (pending.isNotEmpty()) {
            val id = pending.removeFirst()
            if (!visited.add(id)) continue
            val item = scoped[id] ?: continue
            if (item.supersedesId in scoped) pending.add(item.supersedesId)
            children[id].orEmpty().forEach { pending.add(it.id) }
        }
        return visited
    }
}

package com.galaxyssi.chat

import java.util.UUID

internal data class AgentMemoryRememberMutation(
    val before: List<AgentMemoryItem>,
    val after: List<AgentMemoryItem>,
    val result: AgentMemoryWriteResult
) {
    companion object {
        fun plan(next: AgentMemoryItem, candidates: List<AgentMemoryItem>, now: Long): AgentMemoryRememberMutation {
            require(candidates.all { it.status != AgentMemoryStatus.SUPERSEDED && AgentMemoryIdentity.sameKey(it, next) })
            val duplicate = candidates.firstOrNull { it.value.equals(next.value, ignoreCase = true) }
            if (duplicate != null) {
                val merged = duplicate.copy(
                    confidence = maxOf(duplicate.confidence, next.confidence),
                    evidenceCount = (duplicate.evidenceCount.toLong() + next.evidenceCount).coerceAtMost(10_000L).toInt(),
                    lastConfirmedAtMillis = maxOf(duplicate.lastConfirmedAtMillis, next.lastConfirmedAtMillis, now),
                    expiresAtMillis = maxOf(duplicate.expiresAtMillis, next.expiresAtMillis)
                )
                return AgentMemoryRememberMutation(listOf(duplicate), listOf(merged), AgentMemoryWriteResult(merged, duplicate = true))
            }
            if (next.key.isBlank() || candidates.isEmpty()) {
                return AgentMemoryRememberMutation(emptyList(), listOf(next), AgentMemoryWriteResult(next))
            }
            val group = candidates.firstNotNullOfOrNull { it.conflictGroupId.takeIf(String::isNotBlank) }
                ?: UUID.randomUUID().toString()
            val existing = candidates.map { it.copy(status = AgentMemoryStatus.CONFLICTED, conflictGroupId = group) }
            val conflicted = next.copy(
                version = Math.addExact(candidates.maxOf { it.version }, 1),
                supersedesId = candidates.maxByOrNull { it.version }!!.id,
                status = AgentMemoryStatus.CONFLICTED, conflictGroupId = group
            )
            val after = existing + conflicted
            return AgentMemoryRememberMutation(candidates, after, AgentMemoryWriteResult(conflicted,
                AgentMemoryConflict(group, next.kind, next.key, after.sortedBy { it.version })))
        }
    }
}

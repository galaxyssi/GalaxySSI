package com.galaxyssi.chat

internal data class AgentMemoryAccessRefresh(
    val items: List<AgentMemoryItem>,
    val changed: Boolean
)

internal object AgentMemoryAccessTracker {
    fun refresh(
        items: List<AgentMemoryItem>,
        recalledIds: Set<String>,
        nowMillis: Long,
        minimumWriteIntervalMillis: Long = DEFAULT_WRITE_INTERVAL_MILLIS
    ): AgentMemoryAccessRefresh {
        if (items.isEmpty() || recalledIds.isEmpty()) return AgentMemoryAccessRefresh(items, false)
        val interval = minimumWriteIntervalMillis.coerceAtLeast(0L)
        var changed = false
        val refreshed = items.map { item ->
            if (item.id !in recalledIds || !shouldRefresh(item.lastAccessedAtMillis, nowMillis, interval)) {
                item
            } else {
                changed = true
                item.copy(lastAccessedAtMillis = nowMillis.coerceAtLeast(0L))
            }
        }
        return if (changed) AgentMemoryAccessRefresh(refreshed, true) else AgentMemoryAccessRefresh(items, false)
    }

    private fun shouldRefresh(lastAccessedAtMillis: Long, nowMillis: Long, intervalMillis: Long): Boolean =
        lastAccessedAtMillis <= 0L ||
            nowMillis >= lastAccessedAtMillis && nowMillis - lastAccessedAtMillis >= intervalMillis

    internal const val DEFAULT_WRITE_INTERVAL_MILLIS = 5 * 60 * 1_000L
}

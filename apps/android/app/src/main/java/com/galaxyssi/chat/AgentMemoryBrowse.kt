package com.galaxyssi.chat

enum class AgentMemorySection { ACTIVE, CONFLICTS, HISTORY }
data class AgentMemoryBrowseCounts(val active: Long, val conflicts: Long, val history: Long)
data class AgentMemoryBrowseCursor(val priority: Int, val time: Long, val position: Long, val key: String,
    val revision: String, val scope: String)
data class AgentMemoryBrowseRequest(val section: AgentMemorySection = AgentMemorySection.ACTIVE,
    val kinds: Set<AgentMemoryKind> = emptySet(), val cursor: AgentMemoryBrowseCursor? = null,
    val limit: Int = 25, val publicOnly: Boolean = false, val nowMillis: Long = 0, val backwards: Boolean = false)
data class AgentMemoryBrowseEntry(val item: AgentMemoryItem, val conflictSize: Long = 0)
data class AgentMemoryBrowsePage(val entries: List<AgentMemoryBrowseEntry>, val counts: AgentMemoryBrowseCounts,
    val next: AgentMemoryBrowseCursor?, val previous: AgentMemoryBrowseCursor? = null)
class AgentMemoryPageChanged : IllegalStateException("Memories changed; reload the first page")

internal object AgentMemoryBrowseOrder {
    fun priority(item: AgentMemoryItem): Int = if (item.status == AgentMemoryStatus.ACTIVE && !item.important) 1 else 0
    fun time(timestamp: Long): Long = timestamp.inv()
    fun scope(request: AgentMemoryBrowseRequest, generation: String): String =
        "$generation:${request.section}:${request.kinds.map { it.name }.sorted().joinToString(",")}:${request.publicOnly}:${request.nowMillis}"
    fun validate(request: AgentMemoryBrowseRequest) {
        require(request.limit in 1..100) { "Memory page size must be between 1 and 100" }
        require(!request.publicOnly || request.section == AgentMemorySection.ACTIVE)
        require(!request.backwards || request.cursor != null)
    }
}

/** Used only by the nonpersistent test store; the encrypted store overrides all browse APIs. */
internal fun AgentMemorySnapshot.browseInMemory(request: AgentMemoryBrowseRequest): AgentMemoryBrowsePage {
    AgentMemoryBrowseOrder.validate(request)
    val filtered: (AgentMemoryItem) -> Boolean = { request.kinds.isEmpty() || it.kind in request.kinds }
    val active = activeItems.filter(filtered)
    val groups = conflicts.filter { request.kinds.isEmpty() || it.kind in request.kinds }
    val history = historyItems.filter(filtered)
    val entries = when (request.section) {
        AgentMemorySection.ACTIVE -> active.filter { !request.publicOnly || (!it.privateMemory && !it.isExpired(request.nowMillis)) }
            .sortedWith(compareByDescending<AgentMemoryItem> { it.important }.thenByDescending { it.timestampMillis })
            .map { AgentMemoryBrowseEntry(it) }
        AgentMemorySection.CONFLICTS -> groups.sortedByDescending { it.candidates.maxOf { item -> item.timestampMillis } }
            .map { AgentMemoryBrowseEntry(it.candidates.maxBy { item -> item.timestampMillis }, it.candidates.size.toLong()) }
        AgentMemorySection.HISTORY -> history.sortedByDescending { it.timestampMillis }.map { AgentMemoryBrowseEntry(it) }
    }
    val revision = (activeItems + historyItems + conflicts.flatMap { it.candidates }).hashCode().toString()
    val scope = AgentMemoryBrowseOrder.scope(request, "in-memory")
    request.cursor?.let { require(it.scope == scope); if (it.revision != revision) throw AgentMemoryPageChanged() }
    val start = if (request.backwards) maxOf(0, Math.toIntExact(request.cursor!!.position) - request.limit)
        else request.cursor?.position?.let { Math.toIntExact(it + 1) } ?: 0
    val shown = entries.drop(start).take(request.limit)
    val next = if (start + shown.size < entries.size) AgentMemoryBrowseCursor(0, 0,
        (start + shown.size - 1).toLong(), shown.last().item.id, revision, scope) else null
    val previous = if (start > 0 && shown.isNotEmpty()) AgentMemoryBrowseCursor(0, 0, start.toLong(), shown.first().item.id, revision, scope) else null
    return AgentMemoryBrowsePage(shown, AgentMemoryBrowseCounts(active.size.toLong(), groups.size.toLong(), history.size.toLong()), next, previous)
}

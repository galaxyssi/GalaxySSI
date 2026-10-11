package com.galaxyssi.chat

/** A bounded exact comparison, cleared with other runtime plaintext. Delivery ACKs are not cached. */
internal class AgentTeamPublicationCache(
    private val capacity: Int = 128,
    private val clock: () -> Long = System::nanoTime
) : RuntimeSensitiveCache {
    private data class Entry(val snapshot: AgentTeamExecutionSnapshot, val expiresAt: Long, val characters: Long)
    private val entries = LinkedHashMap<String, Entry>(16, 0.75f, true)
    private var characters = 0L

    init { require(capacity > 0) }

    @Synchronized
    fun isCurrent(snapshot: AgentTeamExecutionSnapshot): Boolean {
        pruneExpired()
        return entries[snapshot.supervisorRunId]?.snapshot == snapshot
    }

    @Synchronized
    fun mark(snapshot: AgentTeamExecutionSnapshot) {
        pruneExpired()
        val size = snapshot.goal.length.toLong() + snapshot.finalOutput.length + snapshot.members.sumOf {
            it.output.length.toLong() + it.errorMessage.length + it.objective.length + it.role.length +
                it.displayName.length + it.pendingDependencyNames.sumOf(String::length)
        }
        if (size > MAX_CHARACTERS) return
        characters -= entries.remove(snapshot.supervisorRunId)?.characters ?: 0L
        entries[snapshot.supervisorRunId] = Entry(snapshot, clock() + RuntimeCachePolicy.SENSITIVE_TTL_NANOS, size)
        characters += size
        while (entries.size > capacity || characters > MAX_CHARACTERS) {
            characters -= entries.remove(entries.keys.first())!!.characters
        }
        RuntimeSensitiveCaches.track(this)
    }

    @Synchronized
    override fun pruneExpired(): Boolean {
        val now = clock()
        val iterator = entries.values.iterator()
        while (iterator.hasNext()) {
            val entry = iterator.next()
            if (entry.expiresAt <= now) { characters -= entry.characters; iterator.remove() }
        }
        return entries.isNotEmpty()
    }

    @Synchronized
    override fun clearSensitive() { entries.clear(); characters = 0L }

    private companion object { const val MAX_CHARACTERS = 524_288L }
}

package com.signalasi.chat

/** Keeps delayed UI batches from an abandoned provider attempt out of the active transcript. */
internal class AgentConnectorStreamAttemptRegistry(
    private val maxClosedEntries: Int = 512
) {
    private val activeAttempts = HashMap<Long, Int>()
    private val closedSources = LinkedHashSet<Long>()

    init {
        require(maxClosedEntries >= 16)
    }

    @Synchronized
    fun accept(update: AgentConnectorStreamUpdate): Boolean {
        if (update.sourceMessageId <= 0L) return false
        val incoming = update.attemptOrdinal.coerceAtLeast(0)
        if (update.sourceMessageId in closedSources) return false
        val current = activeAttempts[update.sourceMessageId]
        if (current != null && incoming < current) return false
        activeAttempts[update.sourceMessageId] = incoming
        return true
    }

    @Synchronized
    fun isCurrent(update: AgentConnectorStreamUpdate): Boolean =
        activeAttempts[update.sourceMessageId] == update.attemptOrdinal.coerceAtLeast(0)

    @Synchronized
    fun close(sourceMessageId: Long) {
        if (sourceMessageId <= 0L) return
        activeAttempts.remove(sourceMessageId)
        closedSources.remove(sourceMessageId)
        closedSources.add(sourceMessageId)
        while (closedSources.size > maxClosedEntries) {
            closedSources.remove(closedSources.first())
        }
    }

    @Synchronized
    fun clear() {
        activeAttempts.clear()
        closedSources.clear()
    }
}

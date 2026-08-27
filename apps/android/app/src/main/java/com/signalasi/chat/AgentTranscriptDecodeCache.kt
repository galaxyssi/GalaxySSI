package com.signalasi.chat

internal class AgentTranscriptDecodeCache(
    private val capacity: Int = DEFAULT_CAPACITY,
    private val ttlNanos: Long = DEFAULT_TTL_NANOS,
    private val clockNanos: () -> Long = System::nanoTime
) {
    private data class CachedEntry(
        val encryptedPayload: String,
        val entry: AgentTranscriptEntry,
        val expiresAtNanos: Long
    )

    private val entries = object : LinkedHashMap<String, CachedEntry>(capacity, 0.75f, true) {
        override fun removeEldestEntry(
            eldest: MutableMap.MutableEntry<String, CachedEntry>?
        ): Boolean = size > capacity
    }

    init {
        require(capacity > 0) { "Transcript decode cache capacity must be positive" }
        require(ttlNanos > 0L) { "Transcript decode cache TTL must be positive" }
    }

    @Synchronized
    fun get(entryId: String, encryptedPayload: String): AgentTranscriptEntry? {
        val cached = entries[entryId] ?: return null
        if (cached.encryptedPayload != encryptedPayload || cached.expiresAtNanos <= clockNanos()) {
            entries.remove(entryId)
            return null
        }
        return cached.entry
    }

    @Synchronized
    fun put(entryId: String, encryptedPayload: String, entry: AgentTranscriptEntry) {
        pruneExpired(clockNanos())
        entries[entryId] = CachedEntry(
            encryptedPayload = encryptedPayload,
            entry = entry,
            expiresAtNanos = clockNanos() + ttlNanos
        )
    }

    @Synchronized
    fun remove(entryId: String) {
        entries.remove(entryId)
    }

    @Synchronized
    fun clear() {
        entries.clear()
    }

    private fun pruneExpired(now: Long) {
        entries.entries.removeAll { (_, cached) -> cached.expiresAtNanos <= now }
    }

    private companion object {
        const val DEFAULT_CAPACITY = 1_024
        const val DEFAULT_TTL_NANOS = 30L * 1_000_000_000L
    }
}

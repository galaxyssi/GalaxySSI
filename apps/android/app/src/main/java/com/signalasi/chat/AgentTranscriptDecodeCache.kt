package com.signalasi.chat

internal class AgentTranscriptDecodeCache(
    private val capacity: Int = DEFAULT_CAPACITY
) {
    private data class CachedEntry(
        val encryptedPayload: String,
        val entry: AgentTranscriptEntry
    )

    private val entries = object : LinkedHashMap<String, CachedEntry>(capacity, 0.75f, true) {
        override fun removeEldestEntry(
            eldest: MutableMap.MutableEntry<String, CachedEntry>?
        ): Boolean = size > capacity
    }

    init {
        require(capacity > 0) { "Transcript decode cache capacity must be positive" }
    }

    @Synchronized
    fun get(entryId: String, encryptedPayload: String): AgentTranscriptEntry? =
        entries[entryId]
            ?.takeIf { it.encryptedPayload == encryptedPayload }
            ?.entry

    @Synchronized
    fun put(entryId: String, encryptedPayload: String, entry: AgentTranscriptEntry) {
        entries[entryId] = CachedEntry(encryptedPayload, entry)
    }

    @Synchronized
    fun remove(entryId: String) {
        entries.remove(entryId)
    }

    @Synchronized
    fun clear() {
        entries.clear()
    }

    private companion object {
        const val DEFAULT_CAPACITY = 1_024
    }
}

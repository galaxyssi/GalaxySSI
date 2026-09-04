package com.galaxyssi.chat

/** Reuses an immutable decoded snapshot until its persisted plaintext changes. */
internal class AgentPersistentSnapshotCache<T> {
    private val lock = Any()
    private var cachedRaw: String? = null
    private var cachedItems: List<T> = emptyList()

    fun get(raw: String, decode: (String) -> List<T>): List<T> = synchronized(lock) {
        if (cachedRaw == raw) return@synchronized cachedItems
        decode(raw).toList().also { items ->
            cachedRaw = raw
            cachedItems = items
        }
    }

    fun put(raw: String, items: List<T>) = synchronized(lock) {
        cachedRaw = raw
        cachedItems = items.toList()
    }
}

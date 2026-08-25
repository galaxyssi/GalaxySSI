package com.signalasi.chat

/** Reuses immutable workflow snapshots until their encrypted preference plaintext changes. */
internal class AgentWorkflowSnapshotCache {
    private val lock = Any()
    private var cachedRaw: String? = null
    private var cachedItems: List<AgentWorkflow> = emptyList()

    fun get(raw: String, decode: (String) -> List<AgentWorkflow>): List<AgentWorkflow> = synchronized(lock) {
        if (cachedRaw == raw) return@synchronized cachedItems
        decode(raw).toList().also { items ->
            cachedRaw = raw
            cachedItems = items
        }
    }

    fun put(raw: String, items: List<AgentWorkflow>) = synchronized(lock) {
        cachedRaw = raw
        cachedItems = items.toList()
    }
}

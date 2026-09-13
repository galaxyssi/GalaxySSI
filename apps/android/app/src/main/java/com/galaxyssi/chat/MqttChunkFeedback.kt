package com.galaxyssi.chat

/** Coalesced state only. Existing MQTT maintenance owns flushing; no new worker or timer. */
internal class MqttChunkFeedback {
    private data class Key(val scope: String, val transfer: String, val request: String)
    private data class Pending(val due: Long, val revision: Long, val send: () -> Unit)
    private val pending = linkedMapOf<Key, Pending>()

    @Synchronized fun offer(scope: String, transfer: String, request: String, revision: Long, send: () -> Unit,
                            now: Long, urgent: Boolean = false): (() -> Unit)? {
        val key = Key(scope, transfer, request)
        val previous = pending[key]
        if (previous != null && revision < previous.revision) return null
        if (urgent) { pending.remove(key); return send }
        if (previous == null && (pending.size >= MqttBrokerCatalog.MAX_CHUNK_FEEDBACK ||
                pending.keys.count { it.scope == scope } >= MqttBrokerCatalog.PEER_CHUNK_FEEDBACK)) return null
        pending[key] = Pending(previous?.due ?: (now + MqttBrokerCatalog.CHUNK_FEEDBACK_WINDOW_MS), revision, send)
        return null
    }
    @Synchronized fun drain(now: Long, limit: Int = 16): List<() -> Unit> = pending.filterValues { it.due <= now }
        .keys.take(limit).map { pending.remove(it)!!.send }
    @Synchronized fun forget(scope: String) { pending.keys.removeAll { it.scope == scope } }
}

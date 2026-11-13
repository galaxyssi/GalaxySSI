package com.galaxyssi.chat

/** Coalesced state only. Existing MQTT maintenance owns flushing; no new worker or timer. */
internal class MqttChunkFeedback {
    private data class Key(val scope: String, val transfer: String, val request: String)
    private class Pending(var due: Long, val expires: Long, val revision: Long,
                          val send: () -> Boolean, var running: Boolean = false)
    private val pending = linkedMapOf<Key, Pending>()

    private fun expire(now: Long) { pending.entries.removeAll { it.value.expires <= now && !it.value.running } }

    @Synchronized fun offer(scope: String, transfer: String, request: String, revision: Long, send: () -> Boolean,
                            now: Long, urgent: Boolean = false): (() -> Unit)? {
        expire(now)
        val key = Key(scope, transfer, request)
        val previous = pending[key]
        if (previous != null && revision < previous.revision) return null
        if (previous == null && (pending.size >= MqttBrokerCatalog.MAX_CHUNK_FEEDBACK ||
                pending.keys.count { it.scope == scope } >= MqttBrokerCatalog.PEER_CHUNK_FEEDBACK)) return null
        val due = if (urgent) now else previous?.due ?: (now + MqttBrokerCatalog.CHUNK_FEEDBACK_WINDOW_MS)
        val item = Pending(due, now + MqttBrokerCatalog.RECEIPT_RETRY_TTL_MS, revision, send)
        pending[key] = item
        return if (urgent) claim(key, item, now) else null
    }
    private fun claim(key: Key, item: Pending, now: Long): () -> Unit {
        item.running = true
        item.due = now + MqttBrokerCatalog.RECEIPT_RETRY_MS
        pending.remove(key)
        pending[key] = item
        return {
            var sent = false
            try {
                val current = synchronized(this) { pending[key] === item }
                if (current) sent = item.send()
            } finally {
                synchronized(this) {
                    item.running = false
                    if (sent && pending[key] === item) pending.remove(key)
                }
            }
        }
    }
    @Synchronized fun drain(now: Long, limit: Int = 16): List<() -> Unit> {
        expire(now)
        return pending.entries.filter { !it.value.running && it.value.due <= now }.take(limit)
            .map { (key, item) -> claim(key, item, now) }
    }
    @Synchronized fun forget(scope: String) { pending.keys.removeAll { it.scope == scope } }
}

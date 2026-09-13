package com.galaxyssi.chat

/** Local retry acceleration only. Durable sender replay survives expiry or process death. */
internal class MqttReceiptRetry {
    private data class Key(val scope: String, val message: String, val attempt: String)
    private class Pending(var due: Long, val expires: Long, val send: () -> Boolean, var running: Boolean = false)
    private val pending = linkedMapOf<Key, Pending>()

    private fun expire(now: Long) { pending.entries.removeAll { it.value.expires <= now && !it.value.running } }

    fun offer(scope: String, message: String, attempt: String, send: () -> Boolean, now: Long) {
        val key = Key(scope, message, attempt)
        val item = synchronized(this) {
            expire(now)
            if (key in pending || pending.size >= MqttBrokerCatalog.MAX_PENDING_RECEIPTS ||
                pending.keys.count { it.scope == scope } >= MqttBrokerCatalog.PEER_PENDING_RECEIPTS) return
            Pending(now, now + MqttBrokerCatalog.RECEIPT_RETRY_TTL_MS, send).also { pending[key] = it }
        }
        run(key, item, now)
    }

    private fun run(key: Key, item: Pending, now: Long) {
        synchronized(this) {
            if (pending[key] !== item || item.running || item.due > now || item.expires <= now) return
            item.running = true
            item.due = now + MqttBrokerCatalog.RECEIPT_RETRY_MS
            pending.remove(key)
            pending[key] = item
        }
        var sent = false
        try { sent = item.send() } finally {
            synchronized(this) {
                item.running = false
                if (sent && pending[key] === item) pending.remove(key)
            }
        }
    }

    @Synchronized fun drain(now: Long, limit: Int = 16): List<() -> Unit> {
        expire(now)
        return pending.entries.filter { !it.value.running && it.value.due <= now }.take(limit).map { (key, item) ->
            { run(key, item, now) }
        }
    }
    @Synchronized fun forget(scope: String) { pending.keys.removeAll { it.scope == scope } }
}

package com.galaxyssi.chat

/** Receipt credit, not PUBACK credit: broker acceptance does not free the receiver. */
internal class MqttOutboxRetryWindow(
    private val clock: () -> Long = android.os.SystemClock::elapsedRealtime,
    private val capacity: Int = 8,
    private val receiptWindowMillis: Long = 30_000L
) {
    private data class Entry(val route: String, val until: Long)
    private val entries = mutableMapOf<String, Entry>()

    @Synchronized
    fun acquire(route: String, messageId: String): Long {
        val now = clock()
        entries.entries.removeAll { it.value.until <= now }
        entries[messageId]?.let { return (it.until - now).coerceAtLeast(1) }
        val lane = entries.values.filter { it.route == route }
        if (lane.size >= capacity) return (lane.minOf { it.until } - now).coerceAtLeast(1)
        entries[messageId] = Entry(route, now + receiptWindowMillis)
        return 0L
    }

    @Synchronized fun release(messageId: String) { entries.remove(messageId) }
}

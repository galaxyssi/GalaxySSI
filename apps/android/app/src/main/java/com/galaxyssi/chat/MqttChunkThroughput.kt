package com.galaxyssi.chat

/** Process-local observations under the policy lock; not a durable message/retry ledger. */
internal class MqttChunkThroughput {
    data class Chunk(val transfer: String, val request: String, val index: Int, val sampleEligible: Boolean)
    private data class Key(val peer: String, val transfer: String, val request: String, val index: Int)
    private data class Flight(val broker: String, val generation: Long, val bytes: Int, val started: Long, var eligible: Boolean)
    private data class Rate(val updated: Long, val bytesPerSecond: Double, val samples: Int)
    private val flights = mutableMapOf<Key, Flight>()
    private val rates = mutableMapOf<Pair<String, String>, Rate>()

    fun expire(now: Long) {
        flights.entries.removeAll { now - it.value.started !in 0..MqttBrokerCatalog.ATTEMPT_OBSERVATION_MS }
        rates.entries.removeAll { now - it.value.updated !in 0..MqttBrokerCatalog.METRIC_TTL_MS }
    }
    fun track(peer: String, chunk: Chunk, broker: String, generation: Long, bytes: Int, now: Long) {
        expire(now)
        flights.keys.removeAll { it.peer == peer && it.transfer == chunk.transfer && it.request != chunk.request }
        val key = Key(peer, chunk.transfer, chunk.request, chunk.index)
        val previous = flights[key]
        if (previous != null) previous.eligible = false
        else if (flights.size < MqttBrokerCatalog.MAX_ATTEMPTS)
            flights[key] = Flight(broker, generation, bytes, now, chunk.sampleEligible)
    }
    fun discard(peer: String, chunk: Chunk) { flights.remove(Key(peer, chunk.transfer, chunk.request, chunk.index)) }
    fun confirmed(peer: String, transfer: String, request: String, indices: Collection<Int>, generations: Map<String, Long>, now: Long) {
        expire(now)
        val groups = indices.mapNotNull { flights.remove(Key(peer, transfer, request, it)) }
            .filter { it.eligible && generations[it.broker] == it.generation }.groupBy { it.broker }
        groups.forEach { (broker, values) ->
            val elapsed = now - values.minOf { it.started }
            if (elapsed <= 0) return@forEach
            val sample = values.sumOf { it.bytes.toLong() } * 1000.0 / elapsed.coerceAtLeast(20)
            val old = rates[peer to broker]
            rates[peer to broker] = Rate(now, if (old == null) sample else old.bytesPerSecond * 0.75 + sample * 0.25,
                ((old?.samples ?: 0) + 1).coerceAtMost(32))
        }
    }
    fun pendingBytes(broker: String) = flights.values.filter { it.broker == broker }.sumOf { it.bytes.toLong() }
    fun rate(peer: String, broker: String): Double = rates[peer to broker]?.takeIf { it.samples >= MqttBrokerCatalog.CHUNK_MIN_SAMPLES }
        ?.bytesPerSecond ?: MqttBrokerCatalog.UNMEASURED_CHUNK_BYTES_PER_SECOND.toDouble()
    fun forget(peer: String) {
        flights.keys.removeAll { it.peer == peer }
        rates.keys.removeAll { it.first == peer }
    }
    fun reset() { flights.clear(); rates.clear() }
}

package com.galaxyssi.chat

import java.security.MessageDigest
import java.security.SecureRandom
import java.util.ArrayDeque
import kotlin.math.ceil

/** Transport scheduling only. Link authenticates and durably stores peer receipts. */
internal class MqttMultipathPolicy(
    private val tieSeed: ByteArray = ByteArray(16).also(SecureRandom()::nextBytes)
) {
    enum class Traffic { CONTROL, MESSAGE, FINAL, PROGRESS, CHUNK, RECEIPT }
    data class PhysicalKey(val brokerId: String, val generation: Long, val packetId: Int)
    data class PeerRoute(
        val epoch: Long,
        val receiveBrokers: Set<String>,
        val packetBytes: Int,
        val chunkAcks: Boolean,
        val expiresAt: Long
    )
    data class Dispatch(val brokerId: String, val generation: Long, val delayMs: Long)
    data class Attempt(
        val peer: String,
        val messageId: String,
        val contentHash: String,
        val brokerId: String,
        val generation: Long,
        val wireBytes: Int,
        val traffic: Traffic,
        val startedAt: Long,
        var brokerAcked: Boolean = false,
        var slotHeld: Boolean = true,
        var peerAccepted: Boolean = false
    )
    data class PathSnapshot(val connected: Boolean, val generation: Long, val subscriptionCount: Int)
    data class Diagnostics(val paths: Map<String, PathSnapshot>, val inflightPackets: Int,
                           val inflightBytes: Long, val pendingAttempts: Int)
    private data class Path(var generation: Long = 0, var connected: Boolean = false,
                            var packetBytes: Int = MqttBrokerCatalog.PACKET_BYTES,
                            val topics: MutableSet<String> = mutableSetOf())
    private val paths = MqttBrokerCatalog.brokers.keys.associateWith { Path() }
    private val routes = mutableMapOf<String, PeerRoute>()
    private val attempts = mutableMapOf<String, Attempt>()
    private val rtt = mutableMapOf<Pair<String, String>, ArrayDeque<Pair<Long, Long>>>()
    private var network = ""
    private val chunks = MqttChunkThroughput()

    @Synchronized fun setNetwork(value: String) {
        if (value != network) {
            network = value
            rtt.clear()
            chunks.reset()
        }
    }

    @Synchronized fun connected(broker: String, generation: Long,
                                packetBytes: Int = MqttBrokerCatalog.PACKET_BYTES): Boolean {
        require(packetBytes > 0)
        val path = paths.getValue(broker)
        if (generation <= path.generation) return false
        releasePath(broker, path.generation)
        path.generation = generation
        path.connected = true
        path.packetBytes = packetBytes.coerceAtMost(MqttBrokerCatalog.PACKET_BYTES)
        path.topics.clear()
        return true
    }

    @Synchronized fun disconnected(broker: String, generation: Long): Boolean {
        val path = paths.getValue(broker)
        if (path.generation != generation) return false
        path.connected = false
        path.topics.clear()
        releasePath(broker, generation)
        return true
    }

    private fun releasePath(broker: String, generation: Long) {
        attempts.values.filter { it.brokerId == broker && it.generation == generation }
            .forEach { it.slotHeld = false }
        attempts.entries.removeAll { it.value.peerAccepted && !it.value.slotHeld }
    }

    @Synchronized fun subscribed(broker: String, generation: Long, topics: Set<String>): Boolean {
        val path = paths.getValue(broker)
        if (!path.connected || path.generation != generation) return false
        path.topics.addAll(topics)
        return true
    }

    @Synchronized fun unsubscribe(topics: Set<String>) {
        paths.values.forEach { it.topics.removeAll(topics) }
    }

    /** Call after authenticated Link processing and the durable route-epoch check. */
    @Synchronized fun acceptVerifiedResume(peer: String, route: PeerRoute, now: Long): Boolean {
        if (peer.isBlank() || route.epoch !in 1..9_007_199_254_740_991L ||
            !paths.keys.containsAll(route.receiveBrokers) ||
            route.packetBytes !in 1..MqttBrokerCatalog.PACKET_BYTES ||
            route.expiresAt <= now || route.expiresAt - now > MqttBrokerCatalog.RESUME_TTL_MS
        ) return false
        val previous = routes[peer]
        if (previous != null && route.epoch <= previous.epoch) return route == previous
        if (previous == null && routes.size >= MqttBrokerCatalog.MAX_PEER_ROUTES) return false
        routes[peer] = route.copy(receiveBrokers = route.receiveBrokers.toSet())
        return true
    }

    @Synchronized fun forgetPeer(peer: String) {
        chunks.forget(peer)
        routes.remove(peer)
        rtt.keys.removeAll { it.first == peer }
        attempts.entries.removeAll { it.value.peer == peer }
    }

    @Synchronized fun readyBrokers(receiveTopics: Set<String>): Set<String> = paths.filterValues {
        it.connected && receiveTopics.isNotEmpty() && it.topics.containsAll(receiveTopics)
    }.keys.toSet()

    private fun samples(peer: String, broker: String, now: Long): List<Long> {
        val values = rtt[peer to broker] ?: return emptyList()
        while (values.isNotEmpty() && now - values.first.first > MqttBrokerCatalog.METRIC_TTL_MS) {
            values.removeFirst()
        }
        return values.map { it.second }
    }

    private fun score(peer: String, broker: String, now: Long, traffic: Traffic, wireBytes: Int): Double {
        val values = samples(peer, broker, now)
        val latency = if (values.isEmpty()) MqttBrokerCatalog.UNMEASURED_HEDGE_MS.toDouble() else values.average()
        val load = attempts.values.filter { it.brokerId == broker && it.slotHeld }.sumOf { it.wireBytes.toLong() }
        if (traffic == Traffic.CHUNK)
            return latency + (wireBytes + maxOf(load, chunks.pendingBytes(broker))) * 1000.0 / chunks.rate(peer, broker)
        return latency * (1 + load.toDouble() / MqttBrokerCatalog.PEER_INFLIGHT_BYTES)
    }

    private fun tie(peer: String, messageId: String, broker: String): String {
        val digest = MessageDigest.getInstance("SHA-256")
            .digest(tieSeed + "$peer\u0000$messageId\u0000$broker".toByteArray())
        val digits = "0123456789abcdef"
        return buildString(64) {
            digest.forEach { byte ->
                append(digits[(byte.toInt() ushr 4) and 15])
                append(digits[byte.toInt() and 15])
            }
        }
    }

    @Synchronized fun plan(
        peer: String, messageId: String, traffic: Traffic, wireBytes: Int, receiveTopics: Set<String>,
        now: Long, ingress: String? = null, attempted: Set<String> = emptySet()
    ): List<Dispatch> {
        chunks.expire(now)
        if (messageId.isBlank() || wireBytes !in 1..MqttBrokerCatalog.PACKET_BYTES) return emptyList()
        val route = routes[peer] ?: return emptyList()
        if (route.expiresAt <= now || wireBytes > route.packetBytes ||
            (traffic == Traffic.CHUNK && !route.chunkAcks)) return emptyList()
        val common = (readyBrokers(receiveTopics) intersect route.receiveBrokers)
            .filter { wireBytes <= paths.getValue(it).packetBytes }
        val unused = common.filterNot(attempted::contains)
        val candidates = (unused.ifEmpty { common }).sortedWith(
            compareBy<String> { score(peer, it, now, traffic, wireBytes) }.thenBy { tie(peer, messageId, it) }
        ).toMutableList()
        if (candidates.isEmpty()) return emptyList()
        if (traffic == Traffic.RECEIPT && ingress in candidates) {
            candidates.remove(ingress)
            candidates.add(0, requireNotNull(ingress))
        }
        val small = wireBytes <= MqttBrokerCatalog.SMALL_PACKET_BYTES
        if (traffic == Traffic.CONTROL && small) {
            return candidates.map { Dispatch(it, paths.getValue(it).generation, 0) }
        }
        val first = candidates.first()
        val result = mutableListOf(Dispatch(first, paths.getValue(first).generation, 0))
        if (small && traffic in setOf(Traffic.MESSAGE, Traffic.FINAL) && candidates.size > 1) {
            val primarySamples = samples(peer, first, now)
            val values = (if (primarySamples.size >= MqttBrokerCatalog.HEDGE_MIN_SAMPLES) primarySamples
                else candidates.flatMap { samples(peer, it, now) }).sorted()
            val delay = (if (values.size < MqttBrokerCatalog.HEDGE_MIN_SAMPLES) MqttBrokerCatalog.UNMEASURED_HEDGE_MS
                else (values[ceil(values.size * 0.9).toInt() - 1] * 1.5).toLong())
                .coerceIn(MqttBrokerCatalog.HEDGE_MIN_MS, MqttBrokerCatalog.HEDGE_MAX_MS)
            candidates.drop(1).forEachIndexed { index, broker ->
                result.add(Dispatch(broker, paths.getValue(broker).generation, delay * (index + 1)))
            }
        }
        return result
    }

    @Synchronized fun reserve(attemptId: String, attempt: Attempt): Boolean {
        if (attemptId.isBlank() || attempt.peer.isBlank() || attempt.messageId.isBlank() ||
            !attempt.contentHash.matches(Regex("[0-9a-f]{64}")) ||
            attempt.wireBytes !in 1..MqttBrokerCatalog.PACKET_BYTES) return false
        val path = paths[attempt.brokerId] ?: return false
        val priority = attempt.traffic in setOf(Traffic.CONTROL, Traffic.RECEIPT, Traffic.FINAL)
        val trackingLimit = MqttBrokerCatalog.MAX_ATTEMPTS - if (priority) 0 else MqttBrokerCatalog.CONTROL_RESERVE
        if (!path.connected || path.generation != attempt.generation || attempt.wireBytes > path.packetBytes ||
            attemptId in attempts || attempts.size >= trackingLimit) return false
        if (attempts.values.any { it.peer == attempt.peer && it.messageId == attempt.messageId &&
                it.contentHash != attempt.contentHash }) return false
        val active = attempts.values.filter { it.slotHeld }
        val packetLimit = MqttBrokerCatalog.INFLIGHT_PACKETS - if (priority) 0 else MqttBrokerCatalog.CONTROL_RESERVE
        val byteLimit = MqttBrokerCatalog.INFLIGHT_BYTES - if (priority) 0 else
            MqttBrokerCatalog.CONTROL_RESERVE * MqttBrokerCatalog.SMALL_PACKET_BYTES
        val peerByteLimit = MqttBrokerCatalog.PEER_INFLIGHT_BYTES - if (priority) 0 else
            MqttBrokerCatalog.CONTROL_RESERVE * MqttBrokerCatalog.SMALL_PACKET_BYTES
        if (active.size >= packetLimit || active.sumOf { it.wireBytes.toLong() } + attempt.wireBytes > byteLimit ||
            active.filter { it.peer == attempt.peer }.sumOf { it.wireBytes.toLong() } + attempt.wireBytes >
            peerByteLimit) return false
        attempts[attemptId] = attempt.copy(brokerAcked = false, slotHeld = true, peerAccepted = false)
        return true
    }

    @Synchronized fun brokerAck(attemptId: String, broker: String, generation: Long): Boolean {
        val attempt = attempts[attemptId] ?: return false
        if (attempt.brokerId != broker || attempt.generation != generation) return false
        attempt.brokerAcked = true
        attempt.slotHeld = false
        if (attempt.peerAccepted) attempts.remove(attemptId)
        return true
    }

    @Synchronized fun acceptVerifiedReceipt(
        peer: String, messageId: String, contentHash: String, acceptedAttemptId: String, now: Long
    ): Set<String> {
        val accepted = attempts[acceptedAttemptId] ?: return emptySet()
        if (accepted.peerAccepted || accepted.peer != peer || accepted.messageId != messageId || accepted.contentHash != contentHash) {
            return emptySet()
        }
        val elapsed = now - accepted.startedAt
        if (elapsed >= 0) {
            val values = rtt.getOrPut(peer to accepted.brokerId) { ArrayDeque() }
            if (values.size >= 32) values.removeFirst()
            values.addLast(now to elapsed)
        }
        val completed = attempts.filterValues {
            it.peer == peer && it.messageId == messageId && it.contentHash == contentHash
        }.keys.toSet()
        completed.forEach { key ->
            val attempt = attempts.getValue(key)
            attempt.peerAccepted = true
            if (!attempt.slotHeld) attempts.remove(key)
        }
        return completed
    }

    @Synchronized fun acceptVerifiedMessage(peer: String, messageId: String, contentHash: String): Set<String> {
        val completed = attempts.filterValues {
            it.peer == peer && it.messageId == messageId && it.contentHash == contentHash
        }.keys.toSet()
        completed.forEach { key ->
            val attempt = attempts.getValue(key)
            attempt.peerAccepted = true
            if (!attempt.slotHeld) attempts.remove(key)
        }
        return completed
    }

    @Synchronized fun discardAttempt(attemptId: String) { attempts.remove(attemptId) }
    @Synchronized fun trackChunk(peer: String, chunk: MqttChunkThroughput.Chunk, broker: String, generation: Long, bytes: Int, now: Long) {
        if (peer in routes && paths.getValue(broker).generation == generation) chunks.track(peer, chunk, broker, generation, bytes, now)
    }
    @Synchronized fun discardChunk(peer: String, chunk: MqttChunkThroughput.Chunk) { chunks.discard(peer, chunk) }
    /** Called only after the solicited pair-authenticated bitmap commit succeeds. */
    @Synchronized fun confirmChunkState(peer: String, transfer: String, request: String, indices: Collection<Int>, now: Long) {
        chunks.confirmed(peer, transfer, request, indices, paths.filterValues { it.connected }.mapValues { it.value.generation }, now)
    }
    @Synchronized fun pending(peer: String, messageId: String): Boolean =
        attempts.values.any { it.peer == peer && it.messageId == messageId && !it.peerAccepted }

    @Synchronized fun expireAttempts(before: Long): Set<String> {
        val expired = attempts.filterValues { it.startedAt < before }.keys.toSet()
        expired.forEach(attempts::remove)
        return expired
    }

    @Synchronized fun diagnostics(): Diagnostics = Diagnostics(
        paths.mapValues { (_, value) -> PathSnapshot(value.connected, value.generation, value.topics.size) },
        attempts.values.count { it.slotHeld },
        attempts.values.filter { it.slotHeld }.sumOf { it.wireBytes.toLong() },
        attempts.size
    )
}

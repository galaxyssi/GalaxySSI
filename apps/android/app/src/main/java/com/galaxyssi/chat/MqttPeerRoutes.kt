package com.galaxyssi.chat

import org.json.JSONObject
import java.util.ArrayDeque
import java.util.Locale
import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock

/** Authenticated per-relationship resume. Call handleVerified only after opening that relationship's AEAD. */
internal class MqttPeerRoutes(
    private val transport: MqttPoolTransport,
    private val store: Persistence,
    private val seal: (String, String) -> String,
    private val onReady: (String) -> Unit = {},
    private val onFailure: (Throwable) -> Unit = {},
    private val onChanged: () -> Unit = {},
    private val now: () -> Long = { System.nanoTime() / 1_000_000 },
    private val wall: () -> Long = System::currentTimeMillis
) {
    interface Persistence {
        fun issue(peer: String, sender: String, receiver: String, brokers: Set<String>, at: Long): MqttRouteAdvertisement
        /** True only when newly committed or identical to the existing durable revision. */
        fun record(peer: String, advertisement: MqttRouteAdvertisement, at: Long): Boolean
        fun forget(peer: String)
    }
    data class Binding(val scope: String, val sender: String, val receiver: String, val secret: String,
        val sendTopic: String, val sendTopics: Set<String>, val receiveTopics: Set<String>, val enabled: Boolean = true) {
        val identity get() = listOf(scope, sender, receiver, secret)
    }
    private class Peer(var binding: Binding) {
        val lock = ReentrantLock()
        var active = true
        var local: MqttRouteAdvertisement? = null
        var generations: Map<String, Long> = emptyMap()
        var confirmedEpoch = 0L
        var remoteEpoch = 0L
        var nextSend = 0L
        var failureUntil = 0L
        val responses = mutableMapOf<String, Pair<String, Long>>()
    }
    private val lock = Any()
    private var peers = mapOf<String, Peer>()
    private var outgoing = mapOf<String, Peer>()
    private val rotation = ArrayDeque<String>()
    private val urgent = linkedSetOf<String>()

    fun replace(bindings: List<Binding>) {
        require(bindings.size <= MqttBrokerCatalog.MAX_PEER_ROUTES && bindings.map { it.scope }.toSet().size == bindings.size)
        val topics = bindings.flatMap { it.sendTopics }
        require(topics.toSet().size == topics.size)
        bindings.forEach { binding ->
            require(binding.scope.isNotBlank() && binding.scope.length <= 512 &&
                binding.sender.matches(Regex("[a-f0-9]{64}")) && binding.receiver.matches(Regex("[a-f0-9]{64}")) &&
                binding.sender != binding.receiver && binding.secret.matches(Regex("[A-Za-z0-9_-]{43}")) &&
                binding.receiveTopics.isNotEmpty() && binding.receiveTopics.size <= 16 &&
                binding.sendTopic in binding.sendTopics && binding.sendTopics.size <= 16 &&
                (binding.sendTopics + binding.receiveTopics).all { it.isNotEmpty() && it.length <= 512 && it.none { c -> c in "#+\u0000" } })
        }
        synchronized(lock) {
            val retained = bindings.associate { binding ->
                var peer = peers[binding.scope]
                if (peer != null && peer.binding.identity != binding.identity) {
                    retire(peer)
                    peer = null
                }
                if (peer == null) peer = Peer(binding)
                else peer.lock.withLock {
                    if (peer.binding.receiveTopics != binding.receiveTopics) {
                        peer.local = null
                        peer.confirmedEpoch = 0
                    }
                    peer.binding = binding
                }
                binding.scope to peer
            }
            (peers.keys - retained.keys).forEach { retire(peers.getValue(it)) }
            val order = rotation.filter { it in retained }
            rotation.clear()
            rotation.addAll(order)
            rotation.addAll(retained.keys - order.toSet())
            peers = retained
            outgoing = retained.values.flatMap { p -> p.binding.sendTopics.map { it to p } }.toMap()
            urgent.retainAll(retained.keys)
        }
    }

    private fun retire(peer: Peer) = peer.lock.withLock {
        store.forget(peer.binding.scope)
        peer.active = false
        transport.policy.forgetPeer(peer.binding.scope)
    }

    fun request(scope: String) = synchronized(lock) {
        if (scope in peers && urgent.size < 64) urgent.add(scope)
    }

    private fun local(peer: Peer, at: Long): MqttRouteAdvertisement? {
        val binding = peer.binding
        val generations = transport.readyPathGenerations(binding.receiveTopics)
        if (generations.isEmpty()) return null
        val old = peer.local
        if (old == null || old.receiveBrokers != generations.keys || peer.generations != generations ||
            old.expiresAtMs - at < MqttBrokerCatalog.RESUME_TTL_MS / 2) {
            peer.local = store.issue(binding.scope, binding.sender, binding.receiver, generations.keys, at)
            peer.confirmedEpoch = 0
            peer.generations = generations
        }
        return peer.local
    }

    fun maintenance(limit: Int = 16) {
        require(limit in 1..64)
        val selected = synchronized(lock) {
            val scopes = urgent.take(limit).toMutableList()
            urgent.removeAll(scopes.toSet())
            repeat(minOf(limit - scopes.size, rotation.size)) {
                val scope = rotation.removeFirst()
                rotation.addLast(scope)
                if (scope !in scopes) scopes.add(scope)
            }
            scopes.mapNotNull(peers::get)
        }
        for (peer in selected) {
            if (!peer.lock.tryLock()) continue
            val publication: Pair<Binding, MqttRouteAdvertisement>
            var changed = false
            try {
                if (!peer.active || now() < peer.failureUntil) continue
                val previous = peer.local
                val advertisement = local(peer, wall()) ?: continue
                changed = previous !== advertisement
                if (previous === advertisement && (peer.confirmedEpoch == advertisement.epoch || now() < peer.nextSend)) continue
                peer.nextSend = now() + 5_000
                publication = peer.binding to advertisement
            } catch (error: Exception) {
                peer.failureUntil = now() + 5_000
                onFailure(error)
                continue
            } finally { peer.lock.unlock() }
            for (broker in publication.second.receiveBrokers) {
                runCatching { control(publication.first, publication.second.toWire(), broker) }.onFailure(onFailure)
            }
            if (changed) onChanged()
        }
    }

    private fun control(binding: Binding, payload: JSONObject, broker: String) {
        if (broker !in transport.readyPathGenerations(binding.receiveTopics)) return
        val raw = payload.toString()
        val hash = MqttRouteAdvertisement.sha256(raw)
        val descriptor = MqttPoolTransport.Publication(binding.scope, hash, hash, MqttMultipathPolicy.Traffic.CONTROL,
            binding.receiveTopics, bootstrap = true, preferredBroker = broker)
        transport.publish(binding.sendTopic, org.eclipse.paho.client.mqttv3.MqttMessage(seal(raw, binding.secret).toByteArray())
            .apply { qos = 1; isRetained = false }, publication = descriptor)
    }

    fun handleVerified(scope: String, payload: JSONObject, ingress: MqttBrokerPool.Ingress, identity: List<String>): Boolean {
        val type = payload.optString("type")
        if (type !in setOf("link_resume", "link_resume_ack")) return false
        val peer = synchronized(lock) { peers[scope] } ?: error("Unconfigured resume peer")
        val path = transport.snapshot()[ingress.brokerId]
        if (path?.connected != true || path.generation != ingress.generation) return true
        var response: JSONObject? = null
        var notify = false
        var expedite = false
        val binding: Binding
        peer.lock.withLock {
            binding = peer.binding
            require(peer.active && binding.identity == identity) { "Resume pair authentication changed" }
            if (transport.readyPathGenerations(binding.receiveTopics)[ingress.brokerId] != ingress.generation) return true
            val at = wall()
            val advertisement = MqttRouteAdvertisement.parseVerified(
                if (type == "link_resume") payload else payload.getJSONObject("advertisement"), binding.receiver, binding.sender, at)
            if (type == "link_resume_ack") {
                val ours = peer.local ?: error("Unrequested resume acknowledgement")
                val epoch = payload.opt("acknowledged_route_epoch")
                require(ours.expiresAtMs > at && payload.optString("acknowledged_resume_id") == ours.resumeId &&
                    (epoch is Int || epoch is Long) && (epoch as Number).toLong() == ours.epoch &&
                    payload.optString("acknowledged_digest") == ours.digest()) { "Stale resume acknowledgement" }
            }
            if (!store.record(scope, advertisement, at)) return true
            if (advertisement.epoch > peer.remoteEpoch) {
                if (!transport.policy.acceptVerifiedResume(scope, MqttMultipathPolicy.PeerRoute(advertisement.epoch,
                        advertisement.receiveBrokers, advertisement.packetBytes, true,
                        now() + minOf(MqttBrokerCatalog.RESUME_TTL_MS, advertisement.expiresAtMs - at)), now())) return true
                peer.remoteEpoch = advertisement.epoch
                if (peer.local == null || peer.confirmedEpoch != peer.local?.epoch) {
                    peer.nextSend = 0
                    expedite = true
                }
            }
            if (type == "link_resume_ack") {
                notify = peer.confirmedEpoch != peer.local!!.epoch
                peer.confirmedEpoch = peer.local!!.epoch
            } else {
                val ours = local(peer, at)
                val key = "${advertisement.epoch}:${advertisement.resumeId}"
                val previous = peer.responses[ingress.brokerId]
                if (ours != null && (previous == null || previous.first != key || now() - previous.second >= 1000)) {
                    peer.responses[ingress.brokerId] = key to now()
                    response = JSONObject().put("type", "link_resume_ack").put("advertisement", ours.toWire())
                        .put("acknowledged_resume_id", advertisement.resumeId).put("acknowledged_route_epoch", advertisement.epoch)
                        .put("acknowledged_digest", advertisement.digest())
                }
            }
        }
        response?.let { control(binding, it, ingress.brokerId) }
        if (expedite) request(scope)
        if (notify) onReady(scope)
        return true
    }

    fun ready(scope: String): Boolean {
        val peer = synchronized(lock) { peers[scope] } ?: return false
        return peer.lock.withLock {
            val advertisement = peer.local ?: return false
            val binding = peer.binding
            if (!peer.active || !binding.enabled || advertisement.expiresAtMs <= wall() || peer.confirmedEpoch != advertisement.epoch) return false
            val current = transport.readyPathGenerations(binding.receiveTopics)
            if (current.isEmpty() || current.any { peer.generations[it.key] != it.value }) return false
            transport.policy.plan(scope, "route-readiness", MqttMultipathPolicy.Traffic.MESSAGE, 1, binding.receiveTopics, now()).isNotEmpty()
        }
    }

    fun classify(topic: String, payload: ByteArray): MqttPoolTransport.Publication? {
        val peer = synchronized(lock) { outgoing[topic] } ?: return null
        if (!ready(peer.binding.scope)) { request(peer.binding.scope); return null }
        return peer.lock.withLock {
            if (!peer.active || !peer.binding.enabled || topic !in peer.binding.sendTopics ||
                peer.confirmedEpoch != peer.local?.epoch || peer.local!!.expiresAtMs <= wall()) return null
            val digest = MqttRouteAdvertisement.sha256(payload.toString(Charsets.UTF_8))
            MqttPoolTransport.Publication(peer.binding.scope, digest, digest, MqttMultipathPolicy.Traffic.MESSAGE,
                peer.binding.receiveTopics, authorizedPaths = peer.generations.toMap())
        }
    }

    fun readyForTopic(topic: String): Boolean = synchronized(lock) { outgoing[topic]?.binding?.scope }?.let(::ready) == true
    fun anyReady(): Boolean = synchronized(lock) { peers.keys.toList() }.any(::ready)

    fun prepareDelivery(topic: String, wire: JSONObject, messageId: String,
                        traffic: MqttMultipathPolicy.Traffic): MqttDeliveryDispatch.Delivery? {
        val peer = synchronized(lock) { outgoing[topic] } ?: return null
        if (!ready(peer.binding.scope)) { request(peer.binding.scope); return null }
        val binding = peer.lock.withLock {
            if (!peer.active || !peer.binding.enabled) return null
            peer.binding
        }
        val immutable = JSONObject(wire.toString())
        val message = MqttDeliveryEnvelope.Message(messageId, MqttDeliveryEnvelope.contentHash(immutable),
            binding.sender, binding.receiver, traffic.name.lowercase(Locale.ROOT))
        val encode: (MqttDeliveryEnvelope.Frame) -> ByteArray = { frame ->
            seal(frame.attach(immutable).toString(), binding.secret).toByteArray(Charsets.UTF_8)
        }
        val authorized: (String, Long) -> Boolean = { broker, generation ->
            peer.lock.withLock {
                val local = peer.local
                peer.active && peer.binding == binding && binding.enabled && local != null &&
                    local.expiresAtMs > wall() && peer.confirmedEpoch == local.epoch &&
                    peer.generations[broker] == generation && transport.readyPathGenerations(binding.receiveTopics)[broker] == generation
            }
        }
        val longest = MqttBrokerCatalog.brokers.keys.maxBy { it.length }
        val preview = encode(MqttDeliveryEnvelope.Frame(message,
            MqttDeliveryEnvelope.Attempt("0".repeat(32), longest, MqttDeliveryEnvelope.MAX_SAFE_INTEGER)))
        val size = mqttPublishPacketBytes(topic, preview.size)
        require(size <= Int.MAX_VALUE)
        return MqttDeliveryDispatch.Delivery(binding.scope, message, binding.receiveTopics, encode, authorized, size.toInt())
    }

    fun acceptDeliveryReceipt(scope: String, payload: JSONObject, ingress: MqttBrokerPool.Ingress, identity: List<String>,
                              commit: (MqttDeliveryEnvelope.Frame) -> Unit): Pair<Boolean, Boolean> {
        if (payload.optString("type") != MqttDeliveryEnvelope.RECEIPT_TYPE) return false to false
        val peer = synchronized(lock) { peers[scope] } ?: error("Unconfigured receipt peer")
        return peer.lock.withLock {
            val binding = peer.binding
            require(peer.active && binding.enabled && binding.identity == identity) { "Receipt pair authentication changed" }
            if (transport.readyPathGenerations(binding.receiveTopics)[ingress.brokerId] != ingress.generation) return true to false
            val frame = MqttDeliveryEnvelope.parseVerifiedReceipt(payload, binding.sender, binding.receiver)
            true to transport.delivery.acceptVerifiedReceipt(scope, frame) { commit(frame) }
        }
    }

    fun publishStoredReceipt(scope: String, frame: MqttDeliveryEnvelope.Frame, messageId: String, wireHash: String,
                             identity: List<String>) {
        val peer = synchronized(lock) { peers[scope] } ?: return
        if (!ready(scope)) return
        val binding: Binding
        val payload: ByteArray
        val publication: MqttPoolTransport.Publication
        peer.lock.withLock {
            binding = peer.binding
            val local = peer.local
            if (!peer.active || !binding.enabled || binding.identity != identity || local == null ||
                local.expiresAtMs <= wall() || peer.confirmedEpoch != local.epoch ||
                frame.message.sender != binding.receiver || frame.message.receiver != binding.sender) return
            val receipt = frame.receiptAfterStore(messageId, wireHash)
            payload = seal(receipt.toString(), binding.secret).toByteArray(Charsets.UTF_8)
            val digest = MqttRouteAdvertisement.sha256(payload.toString(Charsets.UTF_8))
            publication = MqttPoolTransport.Publication(scope, digest, digest, MqttMultipathPolicy.Traffic.RECEIPT,
                binding.receiveTopics, preferredBroker = frame.attempt.brokerId, authorizedPaths = peer.generations.toMap())
        }
        transport.publish(binding.sendTopic, org.eclipse.paho.client.mqttv3.MqttMessage(payload).apply { qos = 1 }, publication = publication)
    }

    fun chunkBinding(topic: String): Binding? {
        val peer = synchronized(lock) { outgoing[topic] } ?: return null
        if (!ready(peer.binding.scope)) return null
        return peer.lock.withLock { if (peer.active && peer.binding.enabled) peer.binding else null }
    }

    fun chunkPublication(topic: String, payload: JSONObject, identity: List<String>, attempted: Set<String>,
                         onPath: (String, Long) -> Unit): MqttPoolTransport.Publication? {
        val binding = chunkBinding(topic) ?: return null
        if (binding.identity != identity) return null
        val peer = synchronized(lock) { peers[binding.scope] } ?: return null
        return peer.lock.withLock {
            if (!peer.active || peer.binding.identity != identity) return null
            val (id, digest, traffic) = if (payload.optString("type") == MqttChunkReceipts.PROBE) {
                val query = MqttChunkReceipts.parse(payload)
                Triple("${query.transfer}:probe", query.manifest, MqttMultipathPolicy.Traffic.RECEIPT)
            } else {
                val chunk = MqttChunkManifest.parse(payload)
                Triple("${chunk.transfer}:${chunk.index}", chunk.digest, MqttMultipathPolicy.Traffic.CHUNK)
            }
            MqttPoolTransport.Publication(binding.scope, id, digest, traffic, binding.receiveTopics,
                authorizedPaths = peer.generations.toMap(), attemptedBrokers = attempted, onPath = onPath)
        }
    }

    fun chunkIngress(scope: String, ingress: MqttBrokerPool.Ingress, identity: List<String>): Boolean {
        val peer = synchronized(lock) { peers[scope] } ?: return false
        return peer.lock.withLock { peer.active && peer.binding.enabled && peer.binding.identity == identity &&
            transport.readyPathGenerations(peer.binding.receiveTopics)[ingress.brokerId] == ingress.generation }
    }

    fun publishChunkState(scope: String, payload: JSONObject, identity: List<String>, broker: String) {
        MqttChunkReceipts.parseState(payload)
        val peer = synchronized(lock) { peers[scope] } ?: return
        if (!ready(scope)) return
        val binding: Binding
        val encoded: ByteArray
        val descriptor: MqttPoolTransport.Publication
        peer.lock.withLock {
            binding = peer.binding
            if (!peer.active || !binding.enabled || binding.identity != identity) return
            encoded = seal(payload.toString(), binding.secret).toByteArray(Charsets.UTF_8)
            val digest = MqttRouteAdvertisement.sha256(encoded.toString(Charsets.UTF_8))
            descriptor = MqttPoolTransport.Publication(scope, digest, digest, MqttMultipathPolicy.Traffic.RECEIPT,
                binding.receiveTopics, preferredBroker = broker, authorizedPaths = peer.generations.toMap())
        }
        transport.publish(binding.sendTopic, org.eclipse.paho.client.mqttv3.MqttMessage(encoded).apply { qos = 1 }, publication = descriptor)
    }
}

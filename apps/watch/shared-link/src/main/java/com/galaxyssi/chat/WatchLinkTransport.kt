package com.galaxyssi.chat

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.util.Log
import org.eclipse.paho.client.mqttv3.*
import org.json.JSONObject
import java.util.concurrent.atomic.AtomicBoolean

/** Wear UI adapter. Routing, path selection, receipts, chunks and replay use phone sources. */
class WatchLinkTransport(
    private val context: Context,
    private val onState: (Boolean) -> Unit,
    private val onControl: (String, JSONObject) -> Unit,
    private val onPayload: (String, JSONObject) -> Unit,
    private val onStored: (String, String, String) -> Unit,
    private val onReady: () -> Unit,
    private val contacts: WatchContacts? = null,
    private val onContactControl: (String, JSONObject) -> Unit = { _, _ -> }
) : AutoCloseable {
    private data class Packet(val ingress: MqttBrokerPool.Ingress, val topic: String, val bytes: ByteArray)
    private val closed = AtomicBoolean()
    private val receiptCredit = MqttOutboxRetryWindow()
    private val replayWorker = java.util.concurrent.Executors.newSingleThreadExecutor()
    private val inbox = GalaxySSILinkDeliveryStore.inbox(context)
    private val legacyInbox = AgentEncryptedDatabase(context, "watch_inbox")
    private val bindings = MqttInboundBindings()
    private val inbound = MqttInboundRoutePool<Packet>(process = ::receive, onFailure = ::failed)
    private var topics = emptySet<String>()
    private val mqtt: MqttPoolTransport = MqttPoolTransport(object : MqttPoolTransport.Listener {
        override fun onConnectionChanged(connected: Boolean) { if (!closed.get()) onState(connected) }
        override fun onSubscriptionsChanged() { if (!closed.get()) onReady() }
        override fun onPacket(ingress: MqttBrokerPool.Ingress, topic: String, payload: ByteArray) {
            val scope = bindings.scope(topic) ?: return
            if (payload.isNotEmpty()) inbound.submit(scope, Packet(ingress, topic, payload), payload.size)
        }
        override fun onMaintenanceFailure(error: Throwable) = failed(error)
    }, classify = { topic, bytes -> peers.classify(topic, bytes) })
    private val peers: MqttPeerRoutes = MqttPeerRoutes(mqtt, MqttRouteState(context), GalaxySSILinkProtocol::sealWirePacket,
        onReady = { onReady() }, onFailure = ::failed, onChanged = { onReady() })
    private val connectivity = context.getSystemService(ConnectivityManager::class.java)
    private val networkCallback = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) { mqtt.networkAvailable(network.toString()) }
        override fun onLost(network: Network) {
            if (connectivity.activeNetwork == null) mqtt.networkUnavailable()
        }
    }
    val isConnected get() = mqtt.isConnected

    fun start() {
        refresh()
        mqtt.onTick = { peers.maintenance() }
        connectivity.registerDefaultNetworkCallback(networkCallback)
        if (connectivity.activeNetwork == null) mqtt.networkUnavailable()
        mqtt.start()
        replayWorker.execute { runCatching { replay() }.onFailure(::failed) }
    }

    @Synchronized fun refresh() {
        val links = allLinks()
        bindings.replace(links.map { it.desktopId to it.routes.receiveWindow }, contacts?.rendezvousTopics().orEmpty())
        peers.replace(links.map { link -> val r = link.routes
            MqttPeerRoutes.Binding(scope(r), r.localFingerprint.lowercase(), r.remoteFingerprint.lowercase(),
                r.linkSecret, r.up, r.sendWindow, r.receiveWindow, link.paired)
        })
        val desired = links.flatMap { it.routes.receiveWindow }.toSet() + contacts?.rendezvousTopics().orEmpty()
        val callback = object : IMqttActionListener {
            override fun onSuccess(token: IMqttToken?) { onReady() }
            override fun onFailure(token: IMqttToken?, error: Throwable?) { error?.let(::failed) }
        }
        val removed = topics - desired
        if (removed.isNotEmpty()) mqtt.unsubscribe(removed.toTypedArray(), null, callback)
        val added = desired - topics
        if (added.isNotEmpty()) mqtt.subscribe(added.toTypedArray(), IntArray(added.size) { 1 }, null, callback)
        topics = desired
    }

    fun ready(link: GalaxySSILinkProtocol.ServerLink) = peers.ready(scope(link.routes))

    fun bootstrap(topic: String, raw: String, receiveTopics: Set<String>): Boolean {
        val hash = MqttRouteAdvertisement.sha256(raw)
        var sent = false
        mqtt.readyPathGenerations(receiveTopics).keys.forEach { broker ->
            runCatching {
                mqtt.publish(topic, message(raw), publication = MqttPoolTransport.Publication(
                    "pairing", hash, hash, MqttMultipathPolicy.Traffic.CONTROL, receiveTopics,
                    bootstrap = true, preferredBroker = broker))
            }.onSuccess { sent = true }.onFailure(::failed)
        }
        return sent
    }

    fun publish(link: GalaxySSILinkProtocol.ServerLink, id: String, raw: String, type: String): Boolean {
        if (!ready(link)) { peers.request(scope(link.routes)); return false }
        val wire = JSONObject(raw)
        val parts = GalaxySSIMqttWireChunking.encode(raw)
        if (parts.size > 1) {
            val batch = AndroidMqttChunks.prepare(context, link.routes.up, parts, link.routes.linkSecret, peers) ?: return false
            batch.forEach { (encoded, publication) -> mqtt.publish(link.routes.up, message(encoded), publication = publication) }
        } else if (type == "delivery_ack" || MqttQueryDeliveryPolicy.hasRetryOwner(type)) {
            mqtt.publish(link.routes.up, message(GalaxySSILinkProtocol.sealWirePacket(raw, link.routes.linkSecret)))
        } else {
            if (receiptCredit.acquire(scope(link.routes), id) > 0) return false
            val traffic = MqttTrafficPolicy.parse(MqttTrafficPolicy.classify(JSONObject().put("type", type)))
            try {
                val delivery = peers.prepareDelivery(link.routes.up, wire, id, traffic)
                    ?: run { receiptCredit.release(id); return false }
                mqtt.publishDelivery(link.routes.up, delivery)
            } catch (error: Exception) { receiptCredit.release(id); throw error }
        }
        return true
    }

    private fun receive(packet: Packet) {
        if (closed.get()) return
        contacts?.session(packet.topic)?.let { session ->
            val raw = JSONObject(GalaxySSILinkProtocol.openWirePacket(packet.bytes, session.getString("secret")))
            onContactControl(packet.topic, raw)
            return
        }
        val link = allLinks().firstOrNull { packet.topic in it.routes.receiveWindow } ?: return
        val r = link.routes
        val raw = JSONObject(GalaxySSILinkProtocol.openWirePacket(packet.bytes, r.linkSecret))
        if (contacts?.isPeer(link.desktopId) == true && PhoneContactCard.isRelationshipControlType(raw.optString("type"))) {
            onContactControl(packet.topic, raw); return
        }
        if (peers.handleVerified(scope(r), raw, packet.ingress, identity(r))) return
        if (raw.optString("type") == MqttDeliveryEnvelope.RECEIPT_TYPE) {
            peers.acceptDeliveryReceipt(scope(r), raw, packet.ingress, identity(r)) { frame ->
                onStored(link.desktopId, frame.message.messageId, frame.message.contentHash)
                receiptCredit.release(frame.message.messageId)
            }
            return
        }
        if (raw.optString("type") in setOf("pairing_confirmed", "pairing_rejected")) {
            onControl(link.desktopId, raw); return
        }
        if (AndroidMqttChunks.receive(context, r, raw, packet.ingress, peers, link.desktopId,
                GalaxySSICrypto.localGalaxySSIId(),
                onWire = { wire, transfer -> decode(link, wire, null, transfer) },
                repeatReceipt = { id -> receipt(link, id) })) return
        val frame = if (raw.has(MqttDeliveryEnvelope.FIELD)) MqttDeliveryEnvelope.parseVerifiedFrame(raw,
            r.remoteFingerprint.lowercase(), r.localFingerprint.lowercase(), packet.ingress.brokerId) else null
        decode(link, raw, frame, null)
    }

    private fun decode(link: GalaxySSILinkProtocol.ServerLink, wire: JSONObject,
                       frame: MqttDeliveryEnvelope.Frame?, transfer: String?) {
        val phone = contacts?.isPeer(link.desktopId) == true
        require(wire.optString("scheme") == "signal" && if (phone) contacts?.approved(link.desktopId) == true
            else GalaxySSILinkProtocol.isCryptographicallyReady(context, link))
        require(wire.optString("from") == link.desktopId && wire.optString("to") == GalaxySSICrypto.localGalaxySSIId())
        val r = link.routes
        val peer = GalaxySSILinkInbox.Peer(scope(r), link.desktopId, phone)
        val hash = MqttDeliveryEnvelope.contentHash(wire)
        // An upgrade cannot decrypt an already consumed Signal ratchet message again.
        // Old encrypted inbox records prove this exact ciphertext was previously stored.
        val legacyKey = MqttImmutableContent.sha256(link.desktopId + wire.getString("body"))
        val legacy = legacyInbox.readString(legacyKey, "")
        if (!phone && legacy.isNotBlank()) {
            val record = JSONObject(legacy)
            require(record.getString("desktop") == link.desktopId)
            val payload = record.getJSONObject("payload")
            val id = payload.getString("message_id")
            frame?.validateApplication(id, hash)
            onPayload(link.desktopId, payload)
            if (frame != null && frame.message.traffic != "receipt")
                peers.publishStoredReceipt(scope(r), frame, id, hash, identity(r))
            return
        }
        // The full canonical wire hash distinguishes endpoints and all Signal fields.
        val replay = inbox.replay(peer.scope, hash)
        if (replay != null) {
            AndroidMqttChunks.releaseStored(context, r, transfer, hash)
            if (replay.receiptRequired) receipt(link, replay.messageId)
            stored(link, frame, replay.messageId)
            if (!replay.completed) replay()
            return
        }
        var accepted: GalaxySSILinkInbox.Accepted? = null
        val result = GalaxySSICrypto.decryptEnvelopeDetailed(wire) { envelope ->
            require(envelope.optString("source_id") == link.desktopId &&
                envelope.optString("target_id") == GalaxySSICrypto.localGalaxySSIId())
            frame?.validateApplication(envelope.optString("message_id"), hash)
            val payload = GalaxySSILinkProtocol.unwrapEnvelope(envelope) ?: error("Invalid application envelope")
            if (phone && payload.optString("type") == "peer_message") require(WatchPeerProtocol.validIncoming(
                payload, link.desktopId, GalaxySSICrypto.localGalaxySSIId(), r.clientRouteId))
            accepted = inbox.accept(peer, envelope.getString("message_id"), MqttImmutableContent.hash(envelope),
                payload, hash, payload.optString("type") != "delivery_ack", hash)
        }
        if (result !is GalaxySSICrypto.EnvelopeDecryptionResult.Success) {
            if (phone && result is GalaxySSICrypto.EnvelopeDecryptionResult.Failure)
                onContactControl("recovery", JSONObject().put("peer", link.desktopId))
            error("Signal receive rejected")
        }
        val saved = checkNotNull(accepted)
        val id = saved.payload.getString("message_id")
        AndroidMqttChunks.releaseStored(context, r, transfer, hash)
        stored(link, frame, id)
        if (saved.payload.optString("type") != "delivery_ack") receipt(link, id)
        if (saved.stage != GalaxySSILinkInbox.Stage.COMPLETED) dispatch(link.desktopId, saved.payload)
    }

    private fun stored(link: GalaxySSILinkProtocol.ServerLink, frame: MqttDeliveryEnvelope.Frame?, id: String) {
        if (frame == null || frame.message.traffic == "receipt") return
        val proof = inbox.storedReceipt(scope(link.routes), id) ?: return
        peers.publishStoredReceipt(scope(link.routes), frame, proof.messageId, proof.wireHash, identity(link.routes))
    }

    private fun receipt(link: GalaxySSILinkProtocol.ServerLink, id: String) {
        val proof = inbox.storedReceipt(scope(link.routes), id) ?: return
        val payload = MqttDeliveryEnvelope.storedReceipt(id, proof.wireHash)
        val envelope = GalaxySSILinkProtocol.makeEnvelope(payload, GalaxySSICrypto.localGalaxySSIId(), link.desktopId)
        val encrypted = (if (contacts?.isPeer(link.desktopId) == true)
            GalaxySSICrypto.encryptPayloadForContact(link.desktopId, envelope)
            else GalaxySSICrypto.encryptPayloadForDesktop(link.desktopId, envelope)) ?: return
        runCatching { publish(link, envelope.getString("message_id"), encrypted.toString(), "delivery_ack") }.onFailure(::failed)
    }

    private fun dispatch(desktop: String, payload: JSONObject) {
        if (payload.optString("type") == "delivery_ack") {
            val (id, hash) = MqttDeliveryEnvelope.parseStoredReceipt(payload)
            val link = findLink(desktop) ?: return
            onStored(desktop, id, hash)
            receiptCredit.release(id)
            mqtt.delivery.acceptVerifiedMessage(scope(link.routes), id, hash)
        } else onPayload(desktop, payload)
        inbox.complete(payload)
    }

    fun replay() {
        var cursor = ""
        do {
            val pending = inbox.pending(cursor)
            pending.forEach { entry ->
                val link = findLink(entry.peer.endpoint)
                if (link != null && (!entry.peer.phone || contacts?.approved(entry.peer.endpoint) == true) && scope(link.routes) == entry.peer.scope) dispatch(entry.peer.endpoint, JSONObject(entry.payload))
            }
            cursor = pending.lastOrNull()?.recordKey.orEmpty()
        } while (cursor.isNotEmpty())
        inbox.pruneCompleted()
    }

    private fun allLinks() = GalaxySSILinkProtocol.allServerLinks(context) + contacts?.links().orEmpty()
    private fun findLink(id: String) = GalaxySSILinkProtocol.serverLink(context, id) ?: contacts?.link(id)
    fun hash(raw: String): String = MqttDeliveryEnvelope.contentHash(JSONObject(raw))
    fun diagnostics(): String = mqtt.snapshot().entries.joinToString { "${it.key}:${it.value.state}" }
    private fun scope(r: GalaxySSILinkProtocol.Routes) = GalaxySSILinkDeliveryStore.peerScope(r)
    private fun identity(r: GalaxySSILinkProtocol.Routes) = listOf(scope(r), r.localFingerprint.lowercase(), r.remoteFingerprint.lowercase(), r.linkSecret)
    private fun message(raw: String) = MqttMessage(raw.toByteArray()).apply { qos = 1; isRetained = false }
    private fun failed(error: Throwable) { Log.w("WatchLink", "Transport deferred: ${error.javaClass.simpleName}", error) }

    override fun close() {
        if (!closed.compareAndSet(false, true)) return
        runCatching { connectivity.unregisterNetworkCallback(networkCallback) }
        mqtt.close(); inbound.close(); replayWorker.shutdownNow()
    }
}

package com.galaxyssi.chat

import android.content.Context
import android.util.Log
import org.json.JSONObject

internal object AndroidMqttChunks {
    @Volatile private var instance: MqttDurableChunks? = null
    @Volatile private var outgoing: MqttOutgoingChunks? = null
    private fun store(context: Context) = instance ?: synchronized(this) {
        instance ?: MqttDurableChunks(GalaxySSILinkDeliveryStore.transportMetadataDatabase(context)).also { instance = it }
    }
    private fun sender(context: Context) = outgoing ?: synchronized(this) {
        outgoing ?: MqttOutgoingChunks(GalaxySSILinkDeliveryStore.transportMetadataDatabase(context)).also { outgoing = it }
    }

    private fun scope(routes: GalaxySSILinkProtocol.Routes) = MqttDeliveryEnvelope.receiptBinding(
        GalaxySSILinkDeliveryStore.peerScope(routes), routes.remoteFingerprint.lowercase(), routes.localFingerprint.lowercase(), routes.linkSecret)

    fun accept(context: Context, routes: GalaxySSILinkProtocol.Routes, wire: JSONObject): String? = store(context).accept(scope(routes), wire)

    fun releaseStored(context: Context, routes: GalaxySSILinkProtocol.Routes, transfer: String?, ciphertextDigest: String) {
        if (transfer == null) return
        runCatching {
            val proof = GalaxySSILinkDeliveryStore.inbox(context).replay(GalaxySSILinkDeliveryStore.peerScope(routes), ciphertextDigest) ?: return
            if (proof.wireHash.isNotEmpty()) store(context).releaseAfterStore(scope(routes), transfer, proof.wireHash, proof.messageId)
        }.onFailure { Log.w("GalaxySSIRecovery", "Wire fragment cleanup deferred: ${it.javaClass.simpleName}") }
    }

    private fun identity(routes: GalaxySSILinkProtocol.Routes) = listOf(GalaxySSILinkDeliveryStore.peerScope(routes),
        routes.localFingerprint.lowercase(), routes.remoteFingerprint.lowercase(), routes.linkSecret)

    fun prepare(context: Context, topic: String, rawParts: List<String>, secret: String,
                peers: MqttPeerRoutes?): List<Pair<String, MqttPoolTransport.Publication>>? {
        val router = peers ?: return null
        val binding = router.chunkBinding(topic) ?: return null
        if (binding.secret != secret) return null
        val key = MqttDeliveryEnvelope.receiptBinding(binding.scope, binding.sender, binding.receiver, binding.secret)
        val batch = sender(context).prepare(key, rawParts.map(::JSONObject))
        return batch.selected.map { (index, payload) ->
            val descriptor = router.chunkPublication(topic, payload, binding.identity, batch.attempted(index)) { broker, _ ->
                sender(context).recordPath(key, batch.query, index, broker)
            } ?: return null
            GalaxySSILinkProtocol.sealWirePacket(payload.toString(), secret) to descriptor
        }
    }

    fun receive(context: Context, routes: GalaxySSILinkProtocol.Routes, wire: JSONObject, ingress: MqttBrokerPool.Ingress,
                peers: MqttPeerRoutes?, expectedSource: String, expectedTarget: String,
                onWire: (JSONObject, String) -> Unit, repeatReceipt: (String) -> Unit): Boolean = try {
        receiveVerified(context, routes, wire, ingress, peers, expectedSource, expectedTarget, onWire, repeatReceipt)
    } catch (error: IllegalArgumentException) {
        GalaxySSILinkTransportDiagnostics.record(context, GalaxySSILinkTransportDiagnostics.classifyFragmentFailure(error),
            expectedSource, wire.optString("transfer_id"), error.javaClass.simpleName)
        throw error
    }

    private fun receiveVerified(context: Context, routes: GalaxySSILinkProtocol.Routes, wire: JSONObject, ingress: MqttBrokerPool.Ingress,
                peers: MqttPeerRoutes?, expectedSource: String, expectedTarget: String,
                onWire: (JSONObject, String) -> Unit, repeatReceipt: (String) -> Unit): Boolean {
        val type = wire.optString("type")
        val chunk = GalaxySSIMqttWireChunking.isChunk(wire)
        if (!chunk && type !in setOf(MqttChunkReceipts.PROBE, MqttChunkReceipts.STATE)) return false
        val router = peers ?: return true
        val peer = GalaxySSILinkDeliveryStore.peerScope(routes)
        val identity = identity(routes)
        if (!router.chunkIngress(peer, ingress, identity)) return true
        if (type == MqttChunkReceipts.STATE) {
            if (sender(context).accept(MqttDeliveryEnvelope.receiptBinding(peer, identity[1], identity[2], identity[3]), wire))
                router.committedChunkState(peer, wire)
            return true
        }
        val query: MqttChunkReceipts.Query?
        val complete: String?
        val transfer: String
        if (chunk) {
            require(wire.optString("protocol") == GalaxySSILinkProtocol.NAME &&
                wire.optInt("version") == GalaxySSILinkProtocol.VERSION &&
                wire.optString("from") == expectedSource && wire.optString("to") == expectedTarget) { "Chunk endpoints do not match the authenticated pair" }
            query = MqttChunkReceipts.fromChunk(wire)
            transfer = wire.getString("transfer_id")
            complete = store(context).accept(scope(routes), wire)
        } else {
            query = MqttChunkReceipts.parse(wire)
            transfer = query.transfer
            store(context).snapshot(scope(routes), query)
            complete = store(context).recoverComplete(scope(routes), query)
        }
        if (complete != null) onWire(JSONObject(complete), transfer)
        if (query != null) runCatching {
            val snapshot = store(context).snapshot(scope(routes), query)
            router.publishChunkState(peer, snapshot.state, identity, ingress.brokerId, urgent = type == MqttChunkReceipts.PROBE)
            snapshot.proof?.let { (messageId, hash) ->
                if (complete == null && GalaxySSILinkDeliveryStore.inbox(context).storedReceipt(peer, messageId)?.wireHash == hash) repeatReceipt(messageId)
            }
        }.onFailure { Log.w("GalaxySSIRecovery", "Chunk state response deferred: ${it.javaClass.simpleName}") }
        return true
    }
}

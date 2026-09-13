package com.galaxyssi.chat

import android.content.Context
import android.util.Log
import org.json.JSONObject

/** Android storage/UI binding for transport frames; task dispatch remains in the existing inbox path. */
internal object AndroidMqttDelivery {
    private fun identity(routes: GalaxySSILinkProtocol.Routes): List<String> = listOf(
        GalaxySSILinkDeliveryStore.peerScope(routes), routes.localFingerprint.lowercase(),
        routes.remoteFingerprint.lowercase(), routes.linkSecret)

    fun receiveReceipt(context: Context, routes: GalaxySSILinkProtocol.Routes, wire: JSONObject,
                       ingress: MqttBrokerPool.Ingress, peers: MqttPeerRoutes?, onStored: (JSONObject) -> Unit): Boolean {
        if (wire.optString("type") != MqttDeliveryEnvelope.RECEIPT_TYPE) return false
        val router = peers ?: return true
        var saved: JSONObject? = null
        router.acceptDeliveryReceipt(GalaxySSILinkDeliveryStore.peerScope(routes), wire, ingress, identity(routes)) { frame ->
            val receipt = MqttDeliveryEnvelope.storedReceipt(frame.message.messageId, frame.message.contentHash)
            if (GalaxySSILinkDeliveryStore.acknowledgeVerified(context, routes, receipt)) saved = receipt
        }
        saved?.let(onStored)
        return true
    }

    fun frame(routes: GalaxySSILinkProtocol.Routes, wire: JSONObject, ingress: MqttBrokerPool.Ingress): MqttDeliveryEnvelope.Frame? =
        if (!wire.has(MqttDeliveryEnvelope.FIELD)) null else MqttDeliveryEnvelope.parseVerifiedFrame(wire,
            routes.remoteFingerprint.lowercase(), routes.localFingerprint.lowercase(), ingress.brokerId)

    fun stored(context: Context, routes: GalaxySSILinkProtocol.Routes, frame: MqttDeliveryEnvelope.Frame?,
               messageId: String, peers: MqttPeerRoutes?) {
        if (frame == null || peers == null || frame.message.traffic == "receipt") return
        runCatching {
            val scope = GalaxySSILinkDeliveryStore.peerScope(routes)
            val proof = GalaxySSILinkDeliveryStore.inbox(context).storedReceipt(scope, messageId) ?: return
            peers.publishStoredReceipt(scope, frame, proof.messageId, proof.wireHash, identity(routes))
        }.onFailure { Log.w("GalaxySSIRecovery", "Attempt receive receipt deferred: ${it.javaClass.simpleName}") }
    }

    fun acceptedMessage(mqtt: MqttPoolTransport?, routes: GalaxySSILinkProtocol.Routes, payload: JSONObject) {
        val (message, hash) = MqttDeliveryEnvelope.parseStoredReceipt(payload)
        mqtt?.delivery?.acceptVerifiedMessage(GalaxySSILinkDeliveryStore.peerScope(routes), message, hash)
    }
}

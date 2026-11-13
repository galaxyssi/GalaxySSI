package com.galaxyssi.chat

import android.content.Context
import android.util.Log
import org.json.JSONObject

internal object DesktopControlPacketPublisher {
    fun publish(
        context: Context,
        connected: Boolean,
        desktopId: String,
        payload: JSONObject,
        durable: Boolean,
        clientRouteId: String,
        transient: Boolean,
        ready: (String) -> Boolean,
        scheduleRetries: () -> Unit,
        send: (String, String, String?, String, Boolean) -> Boolean
    ): Boolean {
        val link = if (clientRouteId.isBlank()) {
            GalaxySSILinkProtocol.serverLink(context, desktopId)
        } else {
            GalaxySSILinkProtocol.serverLink(context, desktopId, clientRouteId)
        } ?: return false
        if (!connected || !link.paired || !GalaxySSICrypto.hasDesktopSession(context, desktopId)) return false
        val transientQuery = transient || MqttQueryDeliveryPolicy.isTransient(payload.optString("type"))
        if (transientQuery && !ready(link.routes.control)) return false
        val durableDelivery = durable && !transientQuery
        if (durableDelivery && !GalaxySSILinkDeliveryStore.hasCapacity(context, link.routes,
                MqttTrafficPolicy.classify(payload), payload.optString("type"))) {
            Log.w("GalaxySSILink", "Desktop control deferred: durable outbox capacity reached")
            return false
        }
        payload.put("desktop_id", desktopId)
        val envelope = runCatching {
            GalaxySSILinkProtocol.makeEnvelope(payload, GalaxySSICrypto.localGalaxySSIId(), desktopId)
        }.getOrNull() ?: return false
        val encrypted = GalaxySSICrypto.encryptPayloadForDesktop(desktopId, envelope) ?: return false
        val messageId = envelope.getString("message_id")
        val wirePayload = encrypted.toString()
        if (transient && wirePayload.toByteArray(Charsets.UTF_8).size >
            GalaxySSIMqttWireChunking.DEFAULT_DIRECT_LIMIT_BYTES) return false
        if (durableDelivery) {
            if (!GalaxySSILinkDeliveryStore.enqueue(context, messageId, link.routes.control, wirePayload,
                receiptRoutes = link.routes, transportTraffic = MqttTrafficPolicy.classify(payload),
                payloadType = payload.optString("type"))) return false
            if (!ready(link.routes.control)) {
                scheduleRetries()
                return true
            }
            GalaxySSILinkDeliveryStore.markAttempt(context, messageId)
        }
        if (!send(link.routes.control, wirePayload, messageId.takeIf { durableDelivery },
                MqttTrafficPolicy.classify(payload), transientQuery)) {
            if (durableDelivery) {
                scheduleRetries()
                return true
            }
            return false
        }
        return true
    }
}

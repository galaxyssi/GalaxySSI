package com.signalasi.chat

import android.content.Context
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

internal data class PreparedPeerChatMessage(
    val topic: String?,
    val payload: JSONObject,
    val attachments: List<AgentPreparedOutboundAttachment>
)

internal object PeerChatTransport {
    fun prepare(
        context: Context,
        content: String,
        contactId: String,
        topicOverride: String?,
        clientMessageId: Long?,
        deliveryTrace: JSONArray?,
        attachments: List<AgentInputAttachment>,
        messageKind: String = "text",
        durationMillis: Long = 0L
    ): PreparedPeerChatMessage? {
        if (content.isBlank() && attachments.isEmpty()) return null
        val desktopDevice = AppStore.isDesktopDeviceContact(context, contactId)
        val personContact = AppStore.isPersonContact(context, contactId)
        if (!desktopDevice && !personContact) return null
        val endpointId = if (desktopDevice) AppStore.desktopIdForContact(context, contactId) else contactId
        val link = endpointId.takeIf { desktopDevice && it.isNotBlank() }
            ?.let { SignalASILinkProtocol.serverLink(context, it) }
        val phoneRoutes = if (personContact) AppStore.phoneRoutesForIdentity(context, contactId) else null
        val routeId = link?.routes?.clientRouteId ?: phoneRoutes?.clientRouteId.orEmpty()
        if (!SignalASILinkProtocol.validRouteId(routeId)) return null
        val sourceMessageId = clientMessageId ?: System.currentTimeMillis()
        val transportMessageId = UUID.randomUUID().toString()
        val conversationId = if (link != null) {
            "peer:${link.routes.clientRouteId}"
        } else {
            listOf(SignalASICrypto.localSignalasiId(), contactId).sorted().joinToString(":", "peer:")
        }
        val turnId = "peer-turn:$sourceMessageId"
        val taskId = "peer:$sourceMessageId"
        val prepared = if (attachments.isEmpty()) emptyList() else runCatching {
            AgentOutboundAttachmentTransferStore.prepare(
                context = context,
                scope = AgentAttachmentTransferScope(
                    contactId = contactId,
                    desktopId = endpointId,
                    clientRouteId = routeId,
                    conversationId = conversationId,
                    taskId = taskId,
                    turnId = turnId,
                    clientMessageId = sourceMessageId,
                    durationMillis = durationMillis
                ),
                attachments = attachments,
                mediaProfile = AgentMediaNetworkDetector.detect(context),
                preserveOriginalBytes = true
            )
        }.onFailure { error ->
            Log.e("SignalASIPeerTransport", "Could not prepare direct-message attachments", error)
        }.getOrNull() ?: return null
        val payload = JSONObject()
            .put("type", "peer_message")
            .put("message_id", transportMessageId)
            .put("source_message_id", sourceMessageId.toString())
            .put("client_message_id", sourceMessageId)
            .put("content", content.take(24_000))
            .put("message_kind", messageKind.take(32))
            .put(
                "contact_id",
                if (desktopDevice) endpointId else SignalASICrypto.localSignalasiId()
            )
            .put("desktop_id", if (desktopDevice) endpointId else "")
            .put("client_route_id", routeId)
            .put("conversation_id", conversationId)
            .put("task_id", taskId)
            .put("turn_id", turnId)
            .put("sender", if (desktopDevice) "self" else SignalASICrypto.localSignalasiId())
            .put("peer_chat", true)
            .put("time", System.currentTimeMillis())
        if (durationMillis > 0L) payload.put("duration_ms", durationMillis.coerceAtMost(60L * 60L * 1_000L))
        deliveryTrace?.let { payload.put("delivery_trace", it) }
        if (prepared.isNotEmpty()) {
            payload.put("attachments", JSONArray(prepared.map(AgentPreparedOutboundAttachment::descriptor)))
        }
        return PreparedPeerChatMessage(
            topic = topicOverride ?: AppStore.outgoingTopicForContact(context, contactId),
            payload = payload,
            attachments = prepared
        )
    }
}

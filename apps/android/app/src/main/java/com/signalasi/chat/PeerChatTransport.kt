package com.signalasi.chat

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

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
        attachments: List<AgentInputAttachment>
    ): PreparedPeerChatMessage? {
        if (content.isBlank() && attachments.isEmpty()) return null
        if (!AppStore.isDesktopDeviceContact(context, contactId)) return null
        val desktopId = AppStore.desktopIdForContact(context, contactId)
        val link = SignalASILinkProtocol.serverLink(context, desktopId) ?: return null
        val sourceMessageId = clientMessageId ?: System.currentTimeMillis()
        val conversationId = "peer:${link.routes.clientRouteId}"
        val turnId = "peer-turn:$sourceMessageId"
        val taskId = "peer:$sourceMessageId"
        val prepared = if (attachments.isEmpty()) emptyList() else runCatching {
            AgentOutboundAttachmentTransferStore.prepare(
                context = context,
                scope = AgentAttachmentTransferScope(
                    contactId = contactId,
                    desktopId = desktopId,
                    clientRouteId = link.routes.clientRouteId,
                    conversationId = conversationId,
                    taskId = taskId,
                    turnId = turnId,
                    clientMessageId = sourceMessageId
                ),
                attachments = attachments,
                mediaProfile = AgentMediaNetworkDetector.detect(context)
            )
        }.getOrNull() ?: return null
        val payload = JSONObject()
            .put("type", "peer_message")
            .put("message_id", sourceMessageId.toString())
            .put("source_message_id", sourceMessageId.toString())
            .put("client_message_id", sourceMessageId)
            .put("content", content.take(24_000))
            .put("contact_id", desktopId)
            .put("desktop_id", desktopId)
            .put("client_route_id", link.routes.clientRouteId)
            .put("conversation_id", conversationId)
            .put("task_id", taskId)
            .put("turn_id", turnId)
            .put("sender", "self")
            .put("time", System.currentTimeMillis())
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

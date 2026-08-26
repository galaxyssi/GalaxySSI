package com.signalasi.chat

import org.json.JSONArray
import org.json.JSONObject

internal object SignalASIMqttMessagePublisher {
    fun requestSignalBundle(context: android.content.Context, contactId: String): Boolean {
        SignalASIMqttClient.bindApplicationContext(context)
        val contact = AppStore.contactById(context, contactId) ?: return false
        val routes = AppStore.phoneRoutesForIdentity(context, contactId) ?: return false
        val localCard = PhoneContactCard.identityCard(context)
        val request = PhoneContactCard.controlPayload(
            PhoneContactCard.BUNDLE_REFRESH_TYPE,
            contactId,
            localCard
        )
            .put("requested_fingerprint", contact.optString("identity_fingerprint"))
        return SignalASIMqttClient.publishOpaqueRelationshipOrConnect(
            context,
            routes.up,
            routes.linkSecret,
            request,
            "phone_bundle_refresh"
        )
    }

    fun publishGroupTextMessage(
        content: String,
        groupId: String,
        groupName: String,
        memberId: String,
        memberTopic: String
    ): Boolean = SignalASIMqttClient.publishJsonForTransport(
        JSONObject()
            .put("type", "text")
            .put("content", content)
            .put("sender", SignalASICrypto.localSignalasiId())
            .put("contact_id", groupId)
            .put("group_id", groupId)
            .put("group_name", groupName)
            .put("delivery_mode", "per_member_signal")
            .put("time", System.currentTimeMillis()),
        memberTopic,
        memberId
    )

    fun publishFileMessage(
        fileId: String,
        name: String,
        size: Long,
        contentType: String,
        caption: String,
        contactId: String,
        topicOverride: String?
    ): Boolean {
        val type = when {
            contentType.startsWith("image/") -> "image"
            contentType.startsWith("audio/") -> "audio"
            else -> "file_notify"
        }
        return SignalASIMqttClient.publishJsonForTransport(
            JSONObject()
                .put("type", type)
                .put("file_id", fileId)
                .put("name", name)
                .put("size", size)
                .put("caption", caption)
                .put("content", caption)
                .put("contact_id", contactId)
                .put("time", System.currentTimeMillis()),
            topicOverride ?: SignalASIMqttClient.outgoingTopicFor(contactId),
            contactId
        )
    }

    fun publishTaskCancel(
        taskId: String,
        contactId: String,
        sourceMessageId: Long,
        conversationId: String,
        turnId: String,
        topicOverride: String?
    ): Boolean {
        if (taskId.isBlank() || conversationId.isBlank() || turnId.isBlank()) return false
        val payload = JSONObject()
            .put("type", "agent_task_cancel")
            .put("task_id", taskId)
            .put("conversation_id", conversationId)
            .put("turn_id", turnId)
            .put("contact_id", contactId)
            .put("source_message_id", sourceMessageId)
            .put("time", System.currentTimeMillis())
        SignalASIMqttClient.applicationContext()?.let { context ->
            AppStore.contactById(context, contactId)?.let { contact ->
                payload
                    .put(
                        "agent_id",
                        contact.optString("agent_id").ifBlank {
                            AppStore.agentIdForContact(context, contactId)
                        }
                    )
                    .put("desktop_id", contact.optString("desktop_id"))
            }
        }
        return SignalASIMqttClient.publishJsonForTransport(
            payload,
            topicOverride ?: SignalASIMqttClient.outgoingTopicFor(contactId),
            contactId
        )
    }

    fun publishTaskApproval(
        decision: AgentRemoteApprovalDecision,
        topicOverride: String?
    ): Boolean {
        val payload = JSONObject()
            .put("type", "agent_task_approval")
            .put("task_id", decision.taskId)
            .put("client_route_id", decision.clientRouteId)
            .put("conversation_id", decision.conversationId)
            .put("turn_id", decision.turnId)
            .put("contact_id", decision.contactId)
            .put("source_message_id", decision.sourceMessageId)
            .put("approval_id", decision.approvalId)
            .put("action_hash", decision.actionHash)
            .put("decision_scope", decision.choice.wireValue)
            .put("approved", decision.approved)
            .put("time", System.currentTimeMillis())
        SignalASIMqttClient.applicationContext()?.let { context ->
            AppStore.contactById(context, decision.contactId)?.let { contact ->
                payload
                    .put(
                        "agent_id",
                        contact.optString("agent_id").ifBlank {
                            AppStore.agentIdForContact(context, decision.contactId)
                        }
                    )
                    .put("desktop_id", contact.optString("desktop_id"))
            }
        }
        return SignalASIMqttClient.publishJsonForTransport(
            payload,
            topicOverride ?: SignalASIMqttClient.outgoingTopicFor(decision.contactId),
            decision.contactId
        )
    }

    fun publishConversationDelete(conversationId: String, taskIds: Set<String>): Boolean {
        if (conversationId.isBlank()) return false
        return SignalASIMqttClient.publishJsonForTransport(
            JSONObject()
                .put("type", "agent_conversation_delete")
                .put("conversation_id", conversationId)
                .put("task_ids", JSONArray(taskIds.toList()))
                .put("cleanup_scope", "records_and_temporary_files")
                .put("time", System.currentTimeMillis()),
            SignalASIMqttClient.outgoingTopicFor("hermes"),
            "hermes"
        )
    }

    fun publishProfileUpdate(contactId: String, topicOverride: String?): Boolean {
        val context = SignalASIMqttClient.applicationContext() ?: return false
        val profile = AppStore.profile(context)
        val topic = topicOverride ?: AppStore.outgoingTopicForContact(context, contactId) ?: return false
        return SignalASIMqttClient.publishJsonForTransport(
            JSONObject()
                .put("type", "profile_update")
                .put("contact_id", contactId)
                .put("sender", SignalASICrypto.localSignalasiId())
                .put("name", profile.optString("name", "Me"))
                .put("signalasi_id", profile.optString("signalasi_id"))
                .put("identity_fingerprint", profile.optString("identity_fingerprint"))
                .put("time", System.currentTimeMillis()),
            topic,
            contactId
        )
    }

    fun publishPhoneContactRequest(targetCard: JSONObject): Boolean {
        val context = SignalASIMqttClient.applicationContext() ?: return false
        if (!PhoneContactCard.isQrOfferValid(targetCard)) return false
        val targetId = targetCard.optString("signalasi_id")
        if (targetId == SignalASICrypto.localSignalasiId()) return false
        val localCard = PhoneContactCard.identityCard(context)
        AppStore.phoneRoutesForIdentity(context, targetId) ?: return false
        SignalASIMqttClient.refreshOpaqueSubscriptions(context)
        val payload = PhoneContactCard.controlPayload(
            PhoneContactCard.REQUEST_TYPE,
            targetId,
            localCard,
            targetCard.optString("pairing_token")
        )
        return SignalASIMqttClient.publishOpaquePairingOrConnect(
            context,
            targetCard.optString("pairing_topic"),
            targetCard.optString("pairing_secret"),
            payload,
            "phone_pairing_claim"
        )
    }

    fun publishPhoneContactBundle(targetCard: JSONObject): Boolean {
        val context = SignalASIMqttClient.applicationContext() ?: return false
        if (!PhoneContactCard.isIdentityValid(targetCard)) return false
        val targetId = targetCard.optString("signalasi_id")
        val routes = AppStore.phoneRoutesForIdentity(context, targetId) ?: return false
        val localCard = PhoneContactCard.identityCard(context)
        val payload = PhoneContactCard.controlPayload(
            PhoneContactCard.BUNDLE_RESPONSE_TYPE,
            targetId,
            localCard
        )
        return SignalASIMqttClient.publishOpaqueRelationshipOrConnect(
            context,
            routes.up,
            routes.linkSecret,
            payload,
            "phone_pairing_confirmation"
        )
    }
}

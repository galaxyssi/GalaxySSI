package com.signalasi.chat

import android.content.Context
import org.json.JSONObject

internal data class AgentPendingDelivery(
    val sourceMessageId: Long,
    val conversationId: String,
    val turnId: String,
    val taskId: String,
    val contactId: String
)

internal object AgentPendingDeliveryStore {
    private const val PREFS = "signalasi_agent_pending_deliveries"
    private const val KEY_PREFIX = "source:"

    @Synchronized
    fun put(context: Context, delivery: AgentPendingDelivery) {
        if (delivery.sourceMessageId <= 0L ||
            delivery.conversationId.isBlank() ||
            delivery.turnId.isBlank()
        ) return
        AgentEncryptedPreferences(context, PREFS).writeString(
            key(delivery.sourceMessageId),
            JSONObject()
                .put("source_message_id", delivery.sourceMessageId)
                .put("conversation_id", delivery.conversationId)
                .put("turn_id", delivery.turnId)
                .put("task_id", delivery.taskId)
                .put("contact_id", delivery.contactId)
                .toString()
        )
    }

    @Synchronized
    fun find(context: Context, sourceMessageId: Long, contactId: String = ""): AgentPendingDelivery? {
        if (sourceMessageId <= 0L) return null
        val raw = AgentEncryptedPreferences(context, PREFS).readString(key(sourceMessageId), "")
        val value = runCatching { JSONObject(raw) }.getOrNull() ?: return null
        val storedContactId = value.optString("contact_id")
        if (contactId.isNotBlank() && storedContactId.isNotBlank() && contactId != storedContactId) {
            return null
        }
        val conversationId = value.optString("conversation_id")
        val turnId = value.optString("turn_id")
        if (conversationId.isBlank() || turnId.isBlank()) return null
        return AgentPendingDelivery(
            sourceMessageId = value.optLong("source_message_id", sourceMessageId),
            conversationId = conversationId,
            turnId = turnId,
            taskId = value.optString("task_id").ifBlank { turnId },
            contactId = storedContactId
        )
    }

    @Synchronized
    fun remove(context: Context, sourceMessageId: Long) {
        if (sourceMessageId > 0L) AgentEncryptedPreferences(context, PREFS).remove(key(sourceMessageId))
    }

    private fun key(sourceMessageId: Long): String = "$KEY_PREFIX$sourceMessageId"
}

internal object AgentDeliveryFailureRecorder {
    @Synchronized
    fun record(
        context: Context,
        sourceMessageId: Long,
        contactId: String,
        message: String
    ): AgentPendingDelivery? {
        val delivery = AgentPendingDeliveryStore.find(context, sourceMessageId, contactId) ?: return null
        AgentTranscriptStore(context).upsert(
            role = AgentTranscriptRole.ASSISTANT,
            text = message,
            dedupeKey = dedupeKey(sourceMessageId),
            conversationId = delivery.conversationId,
            turnId = delivery.turnId,
            taskId = delivery.taskId
        )
        AgentPendingDeliveryStore.remove(context, sourceMessageId)
        return delivery
    }

    fun dedupeKey(sourceMessageId: Long): String = "delivery-failed:$sourceMessageId"
}

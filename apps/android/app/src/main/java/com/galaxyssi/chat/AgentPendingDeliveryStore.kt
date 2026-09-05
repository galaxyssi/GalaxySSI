package com.galaxyssi.chat

import android.content.Context
import org.json.JSONObject

internal data class AgentPendingDelivery(
    val sourceMessageId: Long,
    val conversationId: String,
    val turnId: String,
    val taskId: String,
    val contactId: String,
    val recoverySuccessorSourceMessageId: Long = 0L
)

internal object AgentPendingDeliveryStore {
    private const val PREFS = "galaxyssi_agent_pending_deliveries"
    private const val KEY_PREFIX = "source:"
    private const val TURN_KEY_PREFIX = "turn:"

    /** Only pending identity keys; never decrypt all pending bodies or scan conversation history. */
    internal fun sourceIds(context: Context): LongArray = context.applicationContext
        .getSharedPreferences(PREFS, Context.MODE_PRIVATE).all.keys.asSequence()
        .filter { it.startsWith(KEY_PREFIX) }
        .mapNotNull { it.removePrefix(KEY_PREFIX).toLongOrNull()?.takeIf { id -> id > 0L } }
        .toList().toLongArray().also { it.sortDescending() }

    @Synchronized
    fun put(context: Context, delivery: AgentPendingDelivery) {
        if (delivery.sourceMessageId <= 0L ||
            delivery.conversationId.isBlank() ||
            delivery.turnId.isBlank()
        ) return
        val preferences = AgentEncryptedPreferences(context, PREFS)
        preferences.writeString(
            key(delivery.sourceMessageId),
            JSONObject()
                .put("source_message_id", delivery.sourceMessageId)
                .put("conversation_id", delivery.conversationId)
                .put("turn_id", delivery.turnId)
                .put("task_id", delivery.taskId)
                .put("contact_id", delivery.contactId)
                .put("recovery_successor_source_message_id", delivery.recoverySuccessorSourceMessageId)
                .toString()
        )
        preferences.writeString(turnKey(delivery.conversationId, delivery.turnId), delivery.sourceMessageId.toString())
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
            contactId = storedContactId,
            recoverySuccessorSourceMessageId = value.optLong("recovery_successor_source_message_id")
        )
    }

    @Synchronized
    fun markRecoveryPredecessor(
        context: Context,
        predecessorSourceMessageId: Long,
        successorSourceMessageId: Long
    ): AgentPendingDelivery? {
        if (predecessorSourceMessageId <= 0L || successorSourceMessageId <= 0L ||
            predecessorSourceMessageId == successorSourceMessageId
        ) return null
        val predecessor = find(context, predecessorSourceMessageId) ?: return null
        val updated = predecessor.copy(recoverySuccessorSourceMessageId = successorSourceMessageId)
        val preferences = AgentEncryptedPreferences(context, PREFS)
        preferences.writeString(
            key(predecessorSourceMessageId),
            JSONObject()
                .put("source_message_id", updated.sourceMessageId)
                .put("conversation_id", updated.conversationId)
                .put("turn_id", updated.turnId)
                .put("task_id", updated.taskId)
                .put("contact_id", updated.contactId)
                .put("recovery_successor_source_message_id", successorSourceMessageId)
                .toString()
        )
        return updated
    }

    @Synchronized
    fun recoverySuccessorForResponse(
        context: Context,
        sourceMessageId: Long,
        conversationId: String,
        turnId: String
    ): Long? {
        val predecessor = find(context, sourceMessageId) ?: return null
        if (predecessor.conversationId != conversationId || predecessor.turnId != turnId) return null
        return predecessor.recoverySuccessorSourceMessageId.takeIf { it > 0L }
    }

    @Synchronized
    fun completeResponse(context: Context, delivery: AgentPendingDelivery?) {
        if (delivery == null) return
        val preferences = AgentEncryptedPreferences(context, PREFS)
        val currentSource = preferences
            .readString(turnKey(delivery.conversationId, delivery.turnId), "")
            .toLongOrNull()
            .orZero()
        setOf(
            delivery.sourceMessageId,
            delivery.recoverySuccessorSourceMessageId,
            currentSource
        ).filter { it > 0L }.forEach { preferences.remove(key(it)) }
        preferences.remove(turnKey(delivery.conversationId, delivery.turnId))
    }

    @Synchronized
    fun remove(context: Context, sourceMessageId: Long) {
        if (sourceMessageId <= 0L) return
        val delivery = find(context, sourceMessageId)
        val preferences = AgentEncryptedPreferences(context, PREFS)
        preferences.remove(key(sourceMessageId))
        if (delivery != null) {
            val turnKey = turnKey(delivery.conversationId, delivery.turnId)
            if (preferences.readString(turnKey, "").toLongOrNull() == sourceMessageId) {
                preferences.remove(turnKey)
            }
        }
    }

    @Synchronized
    fun isSuperseded(
        context: Context,
        sourceMessageId: Long,
        conversationId: String,
        turnId: String
    ): Boolean {
        if (sourceMessageId <= 0L || conversationId.isBlank() || turnId.isBlank()) return false
        val currentSource = AgentEncryptedPreferences(context, PREFS)
            .readString(turnKey(conversationId, turnId), "")
            .toLongOrNull()
            ?: return false
        if (currentSource == sourceMessageId) return false
        val delivery = find(context, sourceMessageId) ?: return true
        return delivery.conversationId != conversationId ||
            delivery.turnId != turnId ||
            delivery.recoverySuccessorSourceMessageId != currentSource
    }

    private fun Long?.orZero(): Long = this ?: 0L

    private fun key(sourceMessageId: Long): String = "$KEY_PREFIX$sourceMessageId"

    private fun turnKey(conversationId: String, turnId: String): String =
        "$TURN_KEY_PREFIX${conversationId.trim()}:${turnId.trim()}"
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
        AgentTerminalDeliveryStore.mark(context, delivery, message)
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

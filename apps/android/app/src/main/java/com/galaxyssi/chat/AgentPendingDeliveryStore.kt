package com.galaxyssi.chat

import android.content.Context
import java.util.concurrent.ConcurrentHashMap

internal data class AgentPendingDelivery(
    val sourceMessageId: Long,
    val conversationId: String,
    val turnId: String,
    val taskId: String,
    val contactId: String,
    val recoverySuccessorSourceMessageId: Long = 0L
)

internal object AgentPendingDeliveryStore {
    private val journals = ConcurrentHashMap<String, AgentPendingDeliveryJournal>()
    private fun journal(context: Context): AgentPendingDeliveryJournal {
        val app = context.applicationContext
        val path = app.getDatabasePath(AgentPendingDeliveryJournal.DATABASE_NAME).absolutePath
        return journals.computeIfAbsent(path) { AgentPendingDeliveryJournal(app, path) }
    }

    fun put(context: Context, delivery: AgentPendingDelivery) = journal(context).put(delivery)
    fun find(context: Context, sourceMessageId: Long, contactId: String = ""): AgentPendingDelivery? =
        journal(context).find(sourceMessageId, contactId)
    fun markRecoveryPredecessor(context: Context, predecessorSourceMessageId: Long, successorSourceMessageId: Long): AgentPendingDelivery? =
        journal(context).markRecoveryPredecessor(predecessorSourceMessageId, successorSourceMessageId)
    fun recoverySuccessorForResponse(context: Context, sourceMessageId: Long, conversationId: String, turnId: String): Long? =
        find(context, sourceMessageId)?.takeIf { AgentPendingDeliveryCodec.sameTurn(it, conversationId, turnId) }
            ?.recoverySuccessorSourceMessageId?.takeIf { it > 0 }
    fun completeResponse(context: Context, delivery: AgentPendingDelivery?) = journal(context).completeResponse(delivery)
    fun remove(context: Context, sourceMessageId: Long) = journal(context).remove(sourceMessageId)
    fun isSuperseded(context: Context, sourceMessageId: Long, conversationId: String, turnId: String): Boolean =
        journal(context).isSuperseded(sourceMessageId, conversationId, turnId)
    internal fun page(context: Context, beforeSource: Long? = null): AgentPendingDeliveryPage = journal(context).page(beforeSource)
    internal fun close(context: Context) {
        journals.remove(context.applicationContext.getDatabasePath(AgentPendingDeliveryJournal.DATABASE_NAME).absolutePath)?.close()
    }
}

internal object AgentDeliveryFailureRecorder {
    @Synchronized
    fun record(context: Context, sourceMessageId: Long, contactId: String, message: String): AgentPendingDelivery? {
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

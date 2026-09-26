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
    fun completeResponse(context: Context, delivery: AgentPendingDelivery?) {
        journal(context).completeResponse(delivery)
        delivery?.let {
            AndroidAgentRemoteSilence.retire(context, it.sourceMessageId)
            AndroidAgentRemoteSilence.retire(context, it.recoverySuccessorSourceMessageId)
        }
    }
    fun remove(context: Context, sourceMessageId: Long) {
        journal(context).remove(sourceMessageId)
        AndroidAgentRemoteSilence.retire(context, sourceMessageId)
    }
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
        if (AgentConnectorResponseStore.hasReceivedDelivery(context, sourceMessageId, contactId)) return null
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
        reconcileWorkspace(context, delivery)
        return delivery
    }

    fun terminalFailure(context: Context, workspace: AgentWorkspace): AgentTranscriptEntry? {
        val transcript = AgentTranscriptStore(context)
        val entries = transcript.workspacePreviews(workspace)
        val failure = entries
            .filter { AgentDeliveryFailurePolicy.matches(workspace, it) }
            .filter { entry ->
                val terminal = AgentTerminalDeliveryStore.find(context,
                    requireNotNull(AgentDeliveryFailurePolicy.sourceMessageId(entry)))
                terminal != null && terminal.conversationId == entry.conversationId &&
                    terminal.turnId == entry.turnId && terminal.taskId == entry.taskId
            }.maxByOrNull { it.timestampMillis }
            ?: return null
        if (entries.any { it.timestampMillis > failure.timestampMillis &&
                ConversationHubAgentStatusPolicy.hasDeliveredReply(workspace, it) }) return null
        return failure
    }

    fun reconcileWorkspace(context: Context, delivery: AgentPendingDelivery) {
        val store = EncryptedAgentWorkspaceStore(context)
        repeat(4) {
            val workspace = store.find(delivery.turnId) ?: return
            if (workspace.status !in setOf(AgentWorkspaceStatus.CREATED, AgentWorkspaceStatus.QUEUED,
                    AgentWorkspaceStatus.RUNNING, AgentWorkspaceStatus.WAITING_RESPONSE) || workspace.cancellationRequested ||
                workspace.conversationId != delivery.conversationId) return
            val failure = terminalFailure(context, workspace) ?: return
            try {
                store.upsert(workspace.copy(status = AgentWorkspaceStatus.FAILED,
                    errorMessage = failure.text), expectedRevision = workspace.revision)
                return
            } catch (_: AgentWorkspaceRevisionConflictException) {
                // A newer attempt may have resumed; recheck its identity and evidence.
            }
        }
    }

    fun reconcileKnownFailures(context: Context, excludedWorkspaceIds: Set<String>) {
        EncryptedAgentWorkspaceStore(context).recoverable(AgentWorkspaceLimits.MAX_RECOVERY_CANDIDATES)
            .filterNot { it.workspaceId in excludedWorkspaceIds }
            .forEach { workspace ->
                val entry = terminalFailure(context, workspace) ?: return@forEach
                val source = requireNotNull(AgentDeliveryFailurePolicy.sourceMessageId(entry))
                val terminal = AgentTerminalDeliveryStore.find(context, source) ?: return@forEach
                reconcileWorkspace(context, AgentPendingDelivery(source, terminal.conversationId,
                    terminal.turnId, terminal.taskId, terminal.contactId))
            }
    }

    fun dedupeKey(sourceMessageId: Long): String = "delivery-failed:$sourceMessageId"
}

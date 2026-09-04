package com.galaxyssi.chat

import android.content.Context
import org.json.JSONObject

internal data class AgentTerminalDelivery(
    val sourceMessageId: Long,
    val conversationId: String,
    val turnId: String,
    val taskId: String,
    val contactId: String,
    val reason: String,
    val terminalAtMillis: Long
)

/** Prevents a request that already showed a terminal failure from being revived by a late reply. */
internal object AgentTerminalDeliveryStore {
    private const val PREFS = "galaxyssi_agent_terminal_deliveries"
    private const val KEY_PREFIX = "source:"
    private const val MAX_RECORDS = 512

    @Synchronized
    fun mark(
        context: Context,
        delivery: AgentPendingDelivery,
        reason: String,
        terminalAtMillis: Long = System.currentTimeMillis()
    ) {
        mark(
            context = context,
            terminal = AgentTerminalDelivery(
                sourceMessageId = delivery.sourceMessageId,
                conversationId = delivery.conversationId,
                turnId = delivery.turnId,
                taskId = delivery.taskId,
                contactId = delivery.contactId,
                reason = reason,
                terminalAtMillis = terminalAtMillis
            )
        )
    }

    @Synchronized
    fun mark(context: Context, terminal: AgentTerminalDelivery) {
        if (terminal.sourceMessageId <= 0L) return
        val preferences = AgentEncryptedPreferences(context, PREFS)
        preferences.writeString(
            key(terminal.sourceMessageId),
            JSONObject()
                .put("source_message_id", terminal.sourceMessageId)
                .put("conversation_id", terminal.conversationId)
                .put("turn_id", terminal.turnId)
                .put("task_id", terminal.taskId)
                .put("contact_id", terminal.contactId)
                .put("reason", terminal.reason.take(1_000))
                .put("terminal_at_millis", terminal.terminalAtMillis)
                .toString()
        )
        prune(preferences)
    }

    @Synchronized
    fun find(context: Context, sourceMessageId: Long): AgentTerminalDelivery? {
        if (sourceMessageId <= 0L) return null
        return decode(
            AgentEncryptedPreferences(context, PREFS).readString(key(sourceMessageId), "")
        )?.takeIf { it.sourceMessageId == sourceMessageId }
    }

    fun isTerminal(context: Context, sourceMessageId: Long): Boolean =
        find(context, sourceMessageId) != null

    private fun prune(preferences: AgentEncryptedPreferences) {
        val records = preferences.keys()
            .asSequence()
            .filter { it.startsWith(KEY_PREFIX) }
            .mapNotNull { storageKey ->
                decode(preferences.readString(storageKey, ""))?.let { storageKey to it }
            }
            .sortedByDescending { (_, record) -> record.terminalAtMillis }
            .toList()
        records.drop(MAX_RECORDS).forEach { (storageKey, _) -> preferences.remove(storageKey) }
    }

    private fun decode(raw: String): AgentTerminalDelivery? = runCatching {
        val value = JSONObject(raw)
        val sourceMessageId = value.optLong("source_message_id")
        if (sourceMessageId <= 0L) return@runCatching null
        AgentTerminalDelivery(
            sourceMessageId = sourceMessageId,
            conversationId = value.optString("conversation_id"),
            turnId = value.optString("turn_id"),
            taskId = value.optString("task_id"),
            contactId = value.optString("contact_id"),
            reason = value.optString("reason"),
            terminalAtMillis = value.optLong("terminal_at_millis")
        )
    }.getOrNull()

    private fun key(sourceMessageId: Long): String = "$KEY_PREFIX$sourceMessageId"
}

internal object AgentLateConnectorResponsePolicy {
    fun exactTurnId(
        explicitTurnId: String,
        taskTurnId: String,
        indexedTurnId: String,
        conversationEntries: List<AgentTranscriptEntry>
    ): String? {
        val candidates = listOf(explicitTurnId, taskTurnId, indexedTurnId)
            .map(String::trim)
            .filter(String::isNotBlank)
            .distinct()
        return candidates.firstOrNull { candidate ->
            conversationEntries.any { entry ->
                entry.role == AgentTranscriptRole.USER && entry.turnId == candidate
            }
        }
    }

    fun canAccept(
        sourceIsTerminal: Boolean,
        exactTurnId: String?,
        conversationEntries: List<AgentTranscriptEntry>
    ): Boolean {
        if (sourceIsTerminal || exactTurnId.isNullOrBlank()) return false
        return conversationEntries.none { entry ->
            entry.role == AgentTranscriptRole.ASSISTANT &&
                entry.turnId == exactTurnId &&
                !isApprovalEntry(entry)
        }
    }

    private fun isApprovalEntry(entry: AgentTranscriptEntry): Boolean =
        entry.taskId.isNotBlank() && AgentRichContentCodec.decode(entry.richOutputJson).any { block ->
            block.type == AgentRichBlockType.APPROVAL && block.actions.any { action ->
                action.verb in setOf("decide_task_permission", "decide_remote_task_permission")
            }
        }
}

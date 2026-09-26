package com.galaxyssi.chat

internal object AgentDeliveryFailurePolicy {
    fun sourceMessageId(entry: AgentTranscriptEntry): Long? =
        entry.takeIf { it.role == AgentTranscriptRole.ASSISTANT &&
            !AgentTranscriptRenderPolicy.isLiveStream(it) && it.dedupeKey.startsWith("delivery-failed:") }
            ?.dedupeKey?.removePrefix("delivery-failed:")?.toLongOrNull()?.takeIf { it > 0L }

    fun matches(workspace: AgentWorkspace, entry: AgentTranscriptEntry): Boolean {
        if (sourceMessageId(entry) == null || entry.conversationId.isBlank() ||
            entry.conversationId != workspace.conversationId || entry.turnId.isBlank() ||
            entry.timestampMillis < workspace.createdAtMillis) return false
        if (entry.turnId != workspace.workspaceId && entry.turnId != workspace.taskId) return false
        val exactTask = entry.taskId.isNotBlank() && entry.taskId == workspace.taskId
        val parentTurn = entry.turnId == workspace.workspaceId && workspace.taskId == workspace.workspaceId
        if (!exactTask && !parentTurn) return false
        return workspace.eventJournal.none {
            it.kind == AgentTaskEventKinds.RESUMED && it.timestampMillis > entry.timestampMillis
        }
    }
}

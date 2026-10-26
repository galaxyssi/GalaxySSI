package com.galaxyssi.chat

internal data class VoiceReminderItem(
    val id: String,
    val kind: String,
    val title: String,
    val content: String,
    val atMillis: Long,
    val resourceId: String = "",
    val conversationId: String = "",
    val state: String = ""
) {
    fun toJson(): AgentNativeJsonObject = mapOf("id" to id, "kind" to kind, "title" to title,
        "content" to content, "at_epoch_ms" to atMillis, "resource_id" to resourceId,
        "conversation_id" to conversationId, "state" to state)
}

internal data class VoiceReminderSnapshot(
    val items: List<VoiceReminderItem>,
    val sources: Map<String, String>
) {
    fun toJson(): AgentNativeJsonObject = mapOf("reminders" to items.map(VoiceReminderItem::toJson),
        "sources" to sources, "scope" to "personal_reminders_and_news_summary",
        "news_bodies_included" to false)
}

internal object VoiceReminderPolicy {
    fun personal(item: GlobalProactiveInboxItem): Boolean = item.isNew && item.newsArticleKey.isBlank() &&
        item.messageIds.none { it.startsWith("attention-feed:") }

    fun taskNeedsAttention(workspace: AgentWorkspace): Boolean = !workspace.cancellationRequested &&
        workspace.conversationId.isNotBlank() && workspace.status in setOf(
            AgentWorkspaceStatus.PAUSED, AgentWorkspaceStatus.BLOCKED, AgentWorkspaceStatus.WAITING_CONFIRMATION)

    fun select(items: List<VoiceReminderItem>): List<VoiceReminderItem> {
        val valid = items.filter { it.id.isNotBlank() && it.content.isNotBlank() }.distinctBy { it.id }
        // Reserve space for each available source instead of letting a single feed fill the screen.
        return listOf("task", "calendar", "personal", "news").flatMap { kind ->
            valid.filter { it.kind == kind }.let { rows ->
                if (kind == "calendar") rows.sortedBy { it.atMillis } else rows.sortedByDescending { it.atMillis }
            }.take(if (kind == "news") 1 else 2)
        }
    }
}

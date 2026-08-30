package com.signalasi.chat

import java.util.Locale

internal enum class ConversationHubTab {
    CONVERSATIONS,
    CONTACTS
}

internal enum class ConversationHubBackAction {
    SHOW_CONVERSATIONS,
    DISMISS
}

internal object ConversationHubBackPolicy {
    fun action(tab: ConversationHubTab, archived: Boolean): ConversationHubBackAction =
        if (tab != ConversationHubTab.CONVERSATIONS || archived) {
            ConversationHubBackAction.SHOW_CONVERSATIONS
        } else {
            ConversationHubBackAction.DISMISS
        }
}

internal data class ConversationHubConversationSections(
    val pinned: List<ConversationHubItem>,
    val recent: List<ConversationHubItem>
)

internal enum class ConversationHubItemKind {
    AGENT,
    CONTACT
}

internal data class ConversationHubItem(
    val id: String,
    val kind: ConversationHubItemKind,
    val title: String,
    val subtitle: String,
    val updatedAt: Long,
    val pinned: Boolean = false,
    val archived: Boolean = false,
    val searchableMetadata: String = "",
    val unreadCount: Int = 0
)

internal data class ConversationHubContactSummary(
    val contactId: String,
    val title: String,
    val lastMessage: String,
    val updatedAt: Long,
    val pinned: Boolean = false,
    val unreadCount: Int = 0
)

internal enum class ConversationHubPreviewKind {
    TEXT,
    VOICE,
    IMAGE,
    FILE
}

internal data class ConversationHubMessagePreview(
    val kind: ConversationHubPreviewKind,
    val text: String = "",
    val name: String = "",
    val sizeBytes: Long = 0L,
    val durationSeconds: Long = 0L
)

internal object ConversationHubPreviewPolicy {
    fun classify(
        content: String,
        attachments: List<PeerChatAttachment>
    ): ConversationHubMessagePreview {
        val normalizedContent = content.trim()
        val attachment = attachments.firstOrNull()
        val contentIsAttachmentName = attachment != null &&
            normalizedContent.equals(attachment.name.trim(), ignoreCase = true)
        if (normalizedContent.isNotBlank() && !contentIsAttachmentName) {
            return ConversationHubMessagePreview(ConversationHubPreviewKind.TEXT, text = normalizedContent)
        }
        if (attachment == null) {
            return ConversationHubMessagePreview(ConversationHubPreviewKind.TEXT, text = normalizedContent)
        }
        return when {
            attachment.mimeType.startsWith("audio/", ignoreCase = true) ->
                ConversationHubMessagePreview(
                    ConversationHubPreviewKind.VOICE,
                    durationSeconds = (attachment.durationMillis / 1_000L).coerceAtLeast(1L)
                )
            attachment.mimeType.startsWith("image/", ignoreCase = true) ->
                ConversationHubMessagePreview(ConversationHubPreviewKind.IMAGE)
            else -> ConversationHubMessagePreview(
                ConversationHubPreviewKind.FILE,
                name = attachment.name.trim(),
                sizeBytes = attachment.sizeBytes.coerceAtLeast(0L)
            )
        }
    }
}

internal object ConversationHubModels {
    fun clearContactUnread(
        source: List<ConversationHubContactSummary>,
        contactId: String
    ): List<ConversationHubContactSummary> = source.map { summary ->
        if (summary.contactId == contactId && summary.unreadCount != 0) {
            summary.copy(unreadCount = 0)
        } else {
            summary
        }
    }

    fun conversations(
        source: List<AgentConversation>,
        query: String,
        archived: Boolean
    ): ConversationHubConversationSections = unifiedConversations(
        agents = source.map { conversation ->
            ConversationHubItem(
                id = conversation.id,
                kind = ConversationHubItemKind.AGENT,
                title = conversation.title,
                subtitle = conversation.summary,
                updatedAt = conversation.updatedAt,
                pinned = conversation.pinned,
                archived = conversation.status == AgentConversationStatus.ARCHIVED,
                searchableMetadata = conversation.selectedModelOrAgent
            )
        },
        contacts = emptyList(),
        query = query,
        archived = archived
    )

    fun unifiedConversations(
        agents: List<ConversationHubItem>,
        contacts: List<ConversationHubContactSummary>,
        query: String,
        archived: Boolean
    ): ConversationHubConversationSections {
        val normalizedQuery = query.trim().lowercase(Locale.ROOT)
        val contactItems = if (archived) emptyList() else contacts.map { contact ->
            ConversationHubItem(
                id = contact.contactId,
                kind = ConversationHubItemKind.CONTACT,
                title = contact.title,
                subtitle = contact.lastMessage,
                updatedAt = contact.updatedAt,
                pinned = contact.pinned,
                unreadCount = contact.unreadCount
            )
        }
        val matching = (agents.asSequence() + contactItems.asSequence())
            .filter { it.archived == archived }
            .filter {
                normalizedQuery.isBlank() ||
                    it.title.lowercase(Locale.ROOT).contains(normalizedQuery) ||
                    it.subtitle.lowercase(Locale.ROOT).contains(normalizedQuery) ||
                    it.searchableMetadata.lowercase(Locale.ROOT).contains(normalizedQuery)
            }
            .sortedByDescending(ConversationHubItem::updatedAt)
            .toList()
        return if (archived) {
            ConversationHubConversationSections(emptyList(), matching)
        } else {
            ConversationHubConversationSections(
                pinned = matching.filter(ConversationHubItem::pinned),
                recent = matching.filterNot(ConversationHubItem::pinned)
            )
        }
    }

    fun contacts(source: List<Contact>, query: String): List<Contact> {
        val normalizedQuery = query.trim().lowercase(Locale.ROOT)
        return source.asSequence()
            .filter {
                normalizedQuery.isBlank() ||
                    it.name.lowercase(Locale.ROOT).contains(normalizedQuery) ||
                    it.id.lowercase(Locale.ROOT).contains(normalizedQuery)
            }
            .sortedWith(compareBy<Contact> { contactSection(it.name) }.thenBy { it.name.lowercase(Locale.ROOT) })
            .toList()
    }

    fun contactSection(name: String): String {
        val first = name.trim().firstOrNull() ?: return "#"
        return if (first in 'a'..'z' || first in 'A'..'Z') first.uppercaseChar().toString() else "#"
    }
}

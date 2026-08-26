package com.signalasi.chat

import java.util.Locale

internal enum class ConversationHubTab {
    CONVERSATIONS,
    CONTACTS
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
    val searchableMetadata: String = ""
)

internal data class ConversationHubContactSummary(
    val contactId: String,
    val title: String,
    val lastMessage: String,
    val updatedAt: Long,
    val pinned: Boolean = false
)

internal object ConversationHubModels {
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
                pinned = contact.pinned
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

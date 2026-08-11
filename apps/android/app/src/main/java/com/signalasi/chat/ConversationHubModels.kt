package com.signalasi.chat

import java.util.Locale

internal enum class ConversationHubTab {
    CONVERSATIONS,
    CONTACTS,
    GROUPS
}

internal data class ConversationHubConversationSections(
    val pinned: List<AgentConversation>,
    val recent: List<AgentConversation>
)

internal object ConversationHubModels {
    fun conversations(
        source: List<AgentConversation>,
        query: String,
        archived: Boolean
    ): ConversationHubConversationSections {
        val normalizedQuery = query.trim().lowercase(Locale.ROOT)
        val status = if (archived) AgentConversationStatus.ARCHIVED else AgentConversationStatus.ACTIVE
        val matching = source.asSequence()
            .filter { it.status == status }
            .filter {
                normalizedQuery.isBlank() ||
                    it.title.lowercase(Locale.ROOT).contains(normalizedQuery) ||
                    it.selectedModelOrAgent.lowercase(Locale.ROOT).contains(normalizedQuery)
            }
            .sortedByDescending(AgentConversation::updatedAt)
            .toList()
        return if (archived) {
            ConversationHubConversationSections(emptyList(), matching)
        } else {
            ConversationHubConversationSections(
                pinned = matching.filter(AgentConversation::pinned),
                recent = matching.filterNot(AgentConversation::pinned)
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

package com.signalasi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ConversationHubModelsTest {
    @Test
    fun activeConversationsAreSeparatedIntoPinnedAndRecent() {
        val sections = ConversationHubModels.conversations(
            source = listOf(
                conversation("recent", updatedAt = 30L),
                conversation("pinned", updatedAt = 10L, pinned = true),
                conversation("archived", updatedAt = 40L, status = AgentConversationStatus.ARCHIVED)
            ),
            query = "",
            archived = false
        )

        assertEquals(listOf("pinned"), sections.pinned.map(AgentConversation::title))
        assertEquals(listOf("recent"), sections.recent.map(AgentConversation::title))
    }

    @Test
    fun archivedModeExcludesActiveConversationsAndSupportsModelSearch() {
        val sections = ConversationHubModels.conversations(
            source = listOf(
                conversation("active", 10L),
                conversation("research", 20L, model = "Codex", status = AgentConversationStatus.ARCHIVED)
            ),
            query = "codex",
            archived = true
        )

        assertTrue(sections.pinned.isEmpty())
        assertEquals(listOf("research"), sections.recent.map(AgentConversation::title))
    }

    @Test
    fun contactsCanBeSearchedByNameOrIdentityAndAreSectioned() {
        val contacts = ConversationHubModels.contacts(
            listOf(
                Contact("desktop:codex", "Codex", ""),
                Contact("hermes-home", "Hermes", ""),
                Contact("friend-zh", "张三", "")
            ),
            "desktop"
        )

        assertEquals(listOf("Codex"), contacts.map(Contact::name))
        assertEquals("C", ConversationHubModels.contactSection("Codex"))
        assertEquals("#", ConversationHubModels.contactSection("张三"))
    }

    private fun conversation(
        title: String,
        updatedAt: Long,
        pinned: Boolean = false,
        model: String = "Automatic",
        status: AgentConversationStatus = AgentConversationStatus.ACTIVE
    ) = AgentConversation(
        id = title,
        title = title,
        createdAt = updatedAt,
        updatedAt = updatedAt,
        selectedModelOrAgent = model,
        status = status,
        pinned = pinned
    )
}

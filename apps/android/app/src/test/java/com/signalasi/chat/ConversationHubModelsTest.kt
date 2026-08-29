package com.signalasi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ConversationHubModelsTest {
    @Test
    fun backFromArchivedOrContactsReturnsToConversationList() {
        assertEquals(
            ConversationHubBackAction.SHOW_CONVERSATIONS,
            ConversationHubBackPolicy.action(ConversationHubTab.CONVERSATIONS, archived = true)
        )
        assertEquals(
            ConversationHubBackAction.SHOW_CONVERSATIONS,
            ConversationHubBackPolicy.action(ConversationHubTab.CONTACTS, archived = false)
        )
        assertEquals(
            ConversationHubBackAction.DISMISS,
            ConversationHubBackPolicy.action(ConversationHubTab.CONVERSATIONS, archived = false)
        )
    }

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

        assertEquals(listOf("pinned"), sections.pinned.map(ConversationHubItem::title))
        assertEquals(listOf("recent"), sections.recent.map(ConversationHubItem::title))
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
        assertEquals(listOf("research"), sections.recent.map(ConversationHubItem::title))
    }

    @Test
    fun contactChatsJoinAgentConversationsAndSortByLastActivity() {
        val sections = ConversationHubModels.unifiedConversations(
            agents = listOf(
                ConversationHubItem(
                    id = "agent-session",
                    kind = ConversationHubItemKind.AGENT,
                    title = "Build project",
                    subtitle = "Project completed",
                    updatedAt = 20L
                )
            ),
            contacts = listOf(
                ConversationHubContactSummary(
                    contactId = "desktop-route",
                    title = "T14 Desktop",
                    lastMessage = "photo.jpg",
                    updatedAt = 30L,
                    unreadCount = 3
                )
            ),
            query = "",
            archived = false
        )

        assertEquals(listOf("T14 Desktop", "Build project"), sections.recent.map(ConversationHubItem::title))
        assertEquals(ConversationHubItemKind.CONTACT, sections.recent.first().kind)
        assertEquals(3, sections.recent.first().unreadCount)
    }

    @Test
    fun pinnedContactChatMovesOutOfRecentConversations() {
        val sections = ConversationHubModels.unifiedConversations(
            agents = emptyList(),
            contacts = listOf(
                ConversationHubContactSummary(
                    contactId = "desktop-route",
                    title = "T14 Desktop",
                    lastMessage = "Connected",
                    updatedAt = 30L,
                    pinned = true
                )
            ),
            query = "",
            archived = false
        )

        assertEquals(listOf("T14 Desktop"), sections.pinned.map(ConversationHubItem::title))
        assertTrue(sections.recent.isEmpty())
    }

    @Test
    fun contactChatCanBeFoundByLastMessageButIsHiddenFromArchive() {
        val contacts = listOf(ConversationHubContactSummary("phone", "S26U", "quarterly report", 10L))

        assertEquals(
            listOf("S26U"),
            ConversationHubModels.unifiedConversations(emptyList(), contacts, "report", false)
                .recent.map(ConversationHubItem::title)
        )
        assertTrue(ConversationHubModels.unifiedConversations(emptyList(), contacts, "", true).recent.isEmpty())
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

    @Test
    fun attachmentPreviewsUseSemanticTypesInsteadOfGeneratedNames() {
        val voice = ConversationHubPreviewPolicy.classify(
            content = "voice-19.opus",
            attachments = listOf(
                PeerChatAttachment(
                    name = "voice-19.opus",
                    mimeType = "audio/opus",
                    sizeBytes = 24_000L,
                    durationMillis = 19_400L
                )
            )
        )
        val image = ConversationHubPreviewPolicy.classify(
            content = "photo.jpg",
            attachments = listOf(PeerChatAttachment("photo.jpg", "image/jpeg", 1_024L))
        )
        val file = ConversationHubPreviewPolicy.classify(
            content = "report.zip",
            attachments = listOf(PeerChatAttachment("report.zip", "application/zip", 8_192L))
        )

        assertEquals(ConversationHubPreviewKind.VOICE, voice.kind)
        assertEquals(19L, voice.durationSeconds)
        assertEquals(ConversationHubPreviewKind.IMAGE, image.kind)
        assertEquals(ConversationHubPreviewKind.FILE, file.kind)
        assertEquals("report.zip", file.name)
    }

    @Test
    fun meaningfulTextCaptionWinsOverAttachmentType() {
        val preview = ConversationHubPreviewPolicy.classify(
            content = "请查看这张截图",
            attachments = listOf(PeerChatAttachment("screen.png", "image/png", 1_024L))
        )

        assertEquals(ConversationHubPreviewKind.TEXT, preview.kind)
        assertEquals("请查看这张截图", preview.text)
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

package com.galaxyssi.chat

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.util.UUID
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AgentWindowHistoryInstrumentedTest {
    private val context = ApplicationProvider.getApplicationContext<Context>()

    @Test fun windowDraftDoesNotCreateFormalConversationUntilFirstMessage() {
        val key = "window-draft-${UUID.randomUUID()}"
        val store = AgentTranscriptStore(context, key)
        val database = AgentConversationDatabase(context)
        val draft = store.createConversation(privateMode = true)
        try {
            store.prepareConversationPaging()
            store.prepareForWindow(draft.id)
            AgentWindowStateStore(context).save(key, draft.id, AgentWindowDraft("Unsent text"))
            val recreated = AgentTranscriptStore(context, key)
            assertEquals(draft.id, recreated.activeConversation().id)
            assertEquals("Unsent text", AgentWindowStateStore(context).load(key, draft.id).text)
            assertNull("No formal row may be created for a window", database.read(draft.id))
            assertNotNull(database.readWindowDraft(draft.id))
            val countBefore = database.count()
            assertTrue(recreated.renameConversation(draft.id, "Named draft"))
            assertTrue(recreated.setPinned(draft.id, true))
            assertEquals(countBefore, database.count())
            assertFalse(recreated.conversations(true).any { it.id == draft.id })
            assertTrue(recreated.append(AgentTranscriptRole.USER, "First message", conversationId = draft.id))
            assertEquals(countBefore + 1, database.count())
            assertNotNull(database.read(draft.id))
            assertNull(database.readWindowDraft(draft.id))
            assertTrue(recreated.renameConversation(draft.id, "New session"))
            assertTrue(recreated.conversationPage(AgentConversationStatus.ACTIVE, pageSize = 500).items.any { it.id == draft.id })
            assertTrue(recreated.archiveConversation(draft.id))
            assertTrue(recreated.conversationPage(AgentConversationStatus.ARCHIVED, pageSize = 500).items.any { it.id == draft.id })
        } finally {
            store.deleteConversation(draft.id)
            database.close()
        }
    }

    @Test fun processAndAssistantUpsertsPromoteOnlyTheirOwnDraft() {
        val key = "window-draft-upsert-${UUID.randomUUID()}"
        val first = AgentTranscriptStore(context, "$key-a")
        val second = AgentTranscriptStore(context, "$key-b")
        val database = AgentConversationDatabase(context)
        val a = first.createConversation(privateMode = true)
        val b = second.createConversation(privateMode = true)
        try {
            first.prepareForWindow(a.id)
            second.prepareForWindow(b.id)
            assertNull(database.read(a.id))
            assertNull(database.read(b.id))
            assertTrue(second.upsert(AgentTranscriptRole.PROCESS, "Task started", "task-start", conversationId = b.id))
            assertNotNull(database.read(b.id))
            assertNull(database.read(a.id))
            assertTrue(first.upsert(AgentTranscriptRole.ASSISTANT, "Result", "result", conversationId = a.id))
            assertNotNull(database.read(a.id))
            assertEquals(a.id, first.activeConversation().id)
            assertEquals(b.id, second.activeConversation().id)
        } finally {
            first.deleteConversation(a.id)
            second.deleteConversation(b.id)
            database.close()
        }
    }

    @Test fun legacyEmptyRowsMoveToDraftStorageAndPagingNeedsNoVisibilityFilter() {
        val name = "window_draft_migration_${UUID.randomUUID()}.db"
        val database = AgentConversationDatabase(context, name)
        try {
            val rows = List(230) { index ->
                AgentConversation("item-$index", "New session", 1L, index.toLong(),
                    pinned = index % 7 == 0, createdByAgent = index == 229)
            }
            val entries = rows.filterIndexed { index, _ -> index % 9 == 0 }.mapTo(mutableSetOf()) { it.id }
            assertTrue(database.upsertAll(rows))
            database.prepareWindowDrafts { entries }
            val expected = rows.filter { it.id in entries || it.createdByAgent }
                .sortedWith(compareByDescending<AgentConversation> { it.pinned }.thenByDescending { it.updatedAt })
            assertEquals(expected.size, database.count())
            assertNull(database.read("item-1"))
            assertEquals(rows[1], database.readWindowDraft("item-1"))
            val result = mutableListOf<AgentConversation>()
            var cursor: AgentConversationPageCursor? = null
            do {
                val page = database.page(AgentConversationStatus.ACTIVE, cursor, 7)
                assertTrue(page.items.isNotEmpty())
                result += page.items
                cursor = page.nextCursor
            } while (page.hasMore)
            assertEquals(expected.map { it.id }, result.map { it.id })
            database.saveWindowDraft(rows[1].copy(title = "Renamed draft"))
            assertEquals(expected.size, database.count())
            assertNotNull(database.promoteWindowDraft("item-1"))
            assertNull(database.promoteWindowDraft("item-1"))
            assertEquals(expected.size + 1, database.count())
            assertNull(database.readWindowDraft("item-1"))
        } finally {
            database.close()
            context.deleteDatabase(name)
        }
    }

    @Test fun versionFourAndInterimVersionFiveBothMigrateWithoutLosingSelection() {
        for (version in listOf(4, 5)) {
            val name = "window_draft_upgrade_${UUID.randomUUID()}.db"
            val draft = AgentConversation("legacy-window", "New session", 1L, 1L)
            AgentConversationDatabase(context, name).use { database ->
                database.upsert(draft)
                database.setActiveConversationId(draft.id)
                database.writableDatabase.execSQL("DROP TABLE ${AgentConversationDatabase.TABLE_WINDOW_DRAFTS}")
                if (version == 5) database.writableDatabase.execSQL(
                    "CREATE TABLE agent_conversation_history_drafts (conversation_id TEXT PRIMARY KEY NOT NULL)")
                database.writableDatabase.version = version
            }
            try {
                AgentConversationDatabase(context, name).use { database ->
                    database.prepareWindowDrafts { emptySet() }
                    assertEquals(draft.id, database.activeConversationId())
                    assertNull(database.read(draft.id))
                    assertEquals(draft, database.readWindowDraft(draft.id))
                    assertEquals(0, database.count())
                }
            } finally { context.deleteDatabase(name) }
        }
    }

    @Test fun reopeningPromotesCommittedFirstMessageButNotEmptyDrafts() {
        val name = "window_draft_recovery_${UUID.randomUUID()}.db"
        val sent = AgentConversation("sent", "New session", 1L, 1L)
        val empty = sent.copy(id = "empty")
        AgentConversationDatabase(context, name).use { database ->
            database.prepareWindowDrafts { emptySet() }
            database.saveWindowDraft(sent)
            database.saveWindowDraft(empty)
            assertEquals(0, database.count())
        }
        try {
            AgentConversationDatabase(context, name).use { database ->
                database.prepareWindowDrafts { setOf(sent.id) }
                assertEquals(listOf(sent.id), database.readAll().map { it.id })
                assertNull(database.readWindowDraft(sent.id))
                assertEquals(empty, database.readWindowDraft(empty.id))
            }
        } finally { context.deleteDatabase(name) }
    }

    @Test fun anotherWindowPromotesSharedDraftWithoutStealingSelectionOrOverwritingMetadata() {
        val key = "window-draft-shared-${UUID.randomUUID()}"
        val first = AgentTranscriptStore(context, "$key-a")
        val second = AgentTranscriptStore(context, "$key-b")
        val draft = first.createConversation(privateMode = true)
        var next: AgentConversation? = null
        try {
            first.prepareForWindow(draft.id)
            assertTrue(second.switchConversation(draft.id))
            second.renameConversation(draft.id, "Shared draft title")
            first.append(AgentTranscriptRole.PROCESS, "Started", conversationId = draft.id)
            assertEquals("Shared draft title", second.activeConversation().title)
            assertEquals("Shared draft title", first.activeConversation().title)
            val nextDraft = first.createConversation(privateMode = true)
            next = nextDraft
            second.append(AgentTranscriptRole.ASSISTANT, "Completed", conversationId = draft.id)
            assertEquals(nextDraft.id, first.activeConversation().id)
            assertEquals(draft.id, second.activeConversation().id)
            assertEquals(2, second.list(draft.id).size)
        } finally {
            first.deleteConversation(draft.id)
            next?.let { first.deleteConversation(it.id) }
        }
    }
}

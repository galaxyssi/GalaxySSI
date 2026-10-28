package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AgentConversationRecallDeviceTest {
    @Test fun encryptedSourcePagingIsScopedBeforeCurrentTurnAndSurvivesReopen() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val name = "context-recall-${UUID.randomUUID()}.db"
        val longText = "Initial requirements.\n" + "Background details. ".repeat(1000) +
            "\nMiddle: online PhD in AI, no residency.\n" + "More details. ".repeat(1000) + "\nTail: include tuition."
        fun row(id: String, conversation: String = "research", text: String = id) = AgentTranscriptEntry(
            id, AgentTranscriptRole.USER, text, 1L, conversationId = conversation, turnId = id)
        try {
            AgentTranscriptEntryDatabase(context, name).use { database ->
                database.insert(row("first", text = longText))
                repeat(80) { database.insert(row("older-$it")) }
                database.insert(row("current"))
                database.insert(row("future"))
                database.insert(row("foreign", "another"))
                val boundary = requireNotNull(database.historyBoundary("research", "current"))
                assertTrue(database.historyContains("research", "first", boundary))
                assertFalse(database.historyContains("research", "current", boundary))
                assertFalse(database.historyContains("research", "future", boundary))
                assertFalse(database.historyContains("research", "foreign", boundary))
                assertNull(database.historyBoundary("another", "current"))
                var before: Long? = boundary
                val ids = mutableListOf<String>()
                do {
                    val page = database.listConversationPage("research", before, 16)
                    ids += page.entries.map { it.id }
                    before = page.nextBeforeSequence
                } while (before != null)
                assertEquals(81, ids.size)
                assertEquals(81, ids.distinct().size)
                database.writableDatabase.execSQL("DROP INDEX transcript_entries_conversation_sequence")
                database.writableDatabase.version = 2
            }
            AgentTranscriptEntryDatabase(context, name).use { database ->
                val plan = database.readableDatabase.rawQuery(
                    "EXPLAIN QUERY PLAN SELECT entry_id FROM transcript_entries WHERE conversation_id = ? AND sequence < ? ORDER BY sequence DESC LIMIT 16",
                    arrayOf("research", "10000")).use { cursor ->
                    buildString { while (cursor.moveToNext()) append(cursor.getString(3)) }
                }
                assertTrue(plan, plan.contains("transcript_entries_conversation_sequence"))
                val text = StringBuilder()
                var offset = 0
                do {
                    val page = requireNotNull(database.textChunkPage("first", offset, 1))
                    text.append(page.chunks.joinToString(""))
                    offset = page.nextOffset
                } while (!page.done)
                assertEquals(longText, text.toString())
            }
        } finally { context.deleteDatabase(name) }
    }
}

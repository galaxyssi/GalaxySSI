package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AgentReplyReadWatermarkDeviceTest {
    @Test fun latestPageReadsOlderReplyWithoutLoadingHistoryOrClearingFutureReply() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val database = AgentTranscriptEntryDatabase.shared(context)
        val store = AgentTranscriptStore(context)
        val id = "watermark-${UUID.randomUUID()}"
        val other = "$id-other"
        fun reply(key: String, conversation: String = id) = AgentTranscriptEntry("$id-$key",
            AgentTranscriptRole.ASSISTANT, "Answer", 1, key, conversation, "$id-turn")
        try {
            val old = reply("old")
            assertTrue(database.insert(old))
            AgentReplyUnreadStore.record(context, old)
            repeat(240) { index ->
                assertTrue(database.insert(reply("progress-$index").copy(role = AgentTranscriptRole.PROCESS)))
            }
            val page = database.listConversationPage(id, pageSize = 100)
            assertTrue(page.hasMore)
            assertFalse(page.entries.any { it.id == old.id })
            val future = reply("future")
            val foreign = reply("foreign", other)
            assertTrue(database.insert(future))
            assertTrue(database.insert(foreign))
            AgentReplyUnreadStore.record(context, future)
            AgentReplyUnreadStore.record(context, foreign)
            assertEquals(1, store.readRepliesThrough(id, requireNotNull(page.newestSequence), setOf("old", "future", "foreign")))
            assertEquals(setOf("future"), AgentReplyUnreadStore.snapshot(context)[id])
            assertEquals(setOf("foreign"), AgentReplyUnreadStore.snapshot(context)[other])
            assertEquals(0, store.readRepliesThrough(id, requireNotNull(page.newestSequence), setOf("old", "future")))
        } finally {
            database.deleteConversation(id)
            database.deleteConversation(other)
            AgentReplyUnreadStore.remove(context, id)
            AgentReplyUnreadStore.remove(context, other)
        }
    }
}

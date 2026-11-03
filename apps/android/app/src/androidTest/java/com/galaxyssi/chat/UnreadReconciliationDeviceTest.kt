package com.galaxyssi.chat

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.util.UUID

@RunWith(AndroidJUnit4::class)
class UnreadReconciliationDeviceTest {
    private val context = ApplicationProvider.getApplicationContext<Context>()

    @Test fun indexedLookupHonorsConversationAndTokenPrecedence() {
        val name = "unread-index-${UUID.randomUUID()}.db"
        val db = AgentTranscriptEntryDatabase(context, name)
        try {
            val keyed = AgentTranscriptEntry("keyed", AgentTranscriptRole.ASSISTANT, "Answer", 1L,
                "final:key", "one", "keyed-turn")
            val turned = keyed.copy(id = "turned", dedupeKey = "", turnId = "turn")
            val bare = keyed.copy(id = "bare", dedupeKey = "", turnId = "")
            listOf(keyed, turned, bare).forEach { assertTrue(db.insert(it)) }
            for (token in listOf("final:key", "turn", "bare")) {
                assertTrue(db.containsUnreadToken("one", token))
                assertFalse(db.containsUnreadToken("two", token))
            }
            for (token in listOf("keyed", "keyed-turn", "turned", "missing")) {
                assertFalse(db.containsUnreadToken("one", token))
            }
            assertTrue(db.deleteById(keyed.id))
            assertFalse(db.containsUnreadToken("one", "final:key"))
        } finally {
            db.close()
            context.deleteDatabase(name)
        }
    }

    @Test fun orphanCleanupPreservesRealFailuresAndReplies() {
        val store = AgentTranscriptStore(context, "unread-reconcile-${UUID.randomUUID()}")
        val conversation = store.createConversation("Unread reconciliation", privateMode = true)
        val orphanId = "unread-orphan-${UUID.randomUUID()}"
        try {
            store.append(AgentTranscriptRole.ASSISTANT, "Delivery failed", "delivery-failed:123",
                conversationId = conversation.id)
            store.append(AgentTranscriptRole.ASSISTANT, "Answer", "final:answer",
                conversationId = conversation.id)
            AgentReplyUnreadStore.record(context, AgentTranscriptEntry("orphan", AgentTranscriptRole.ASSISTANT,
                "Orphan", 1L, "final:orphan", orphanId))
            AgentReplyUnreadStore.record(context, AgentTranscriptEntry("deleted", AgentTranscriptRole.ASSISTANT,
                "Deleted entry", 1L, "final:deleted", conversation.id))
            store.prepareConversationPaging()
            assertFalse(AgentReplyUnreadStore.hasUnread(context, orphanId))
            assertEquals(setOf("delivery-failed:123", "final:answer"),
                AgentReplyUnreadStore.snapshot(context)[conversation.id])
            assertEquals(0, store.reconcileUnreadReplies())
        } finally {
            store.deleteConversation(conversation.id)
            AgentReplyUnreadStore.remove(context, orphanId)
        }
    }

    @Test fun deletingAnUnreadMessageDoesNotReadOtherMessages() {
        val store = AgentTranscriptStore(context, "unread-delete-${UUID.randomUUID()}")
        val conversation = store.createConversation("Unread deletion", privateMode = true)
        val textPrefix = "unread-delete-text-${UUID.randomUUID()}-"
        try {
            for (key in listOf("first", "second", "third")) {
                store.append(AgentTranscriptRole.ASSISTANT, textPrefix + key, key, conversationId = conversation.id)
            }
            val first = store.list(conversation.id).first { it.dedupeKey == "first" }
            assertTrue(store.deleteEntry(first.id))
            assertEquals(2, AgentReplyUnreadStore.count(context, conversation.id))
            assertTrue(store.deleteByDedupeKey(conversation.id, "second"))
            assertEquals(setOf("third"), AgentReplyUnreadStore.snapshot(context)[conversation.id])
            assertEquals(1, store.removeExactText(textPrefix + "third"))
            assertFalse(AgentReplyUnreadStore.hasUnread(context, conversation.id))
        } finally {
            store.deleteConversation(conversation.id)
        }
    }

    @Test fun cleanupOnlyDiscardsSnapshotTokensAndPreservesNewArrivals() {
        val id = "unread-concurrent-${UUID.randomUUID()}"
        fun entry(key: String) = AgentTranscriptEntry(key, AgentTranscriptRole.ASSISTANT, key, 1L, key, id)
        try {
            AgentReplyUnreadStore.record(context, entry("old"))
            val snapshot = AgentReplyUnreadStore.snapshot(context).getValue(id)
            AgentReplyUnreadStore.record(context, entry("new"))
            assertEquals(1, AgentReplyUnreadStore.discard(context, id, snapshot))
            assertEquals(setOf("new"), AgentReplyUnreadStore.snapshot(context)[id])
        } finally {
            AgentReplyUnreadStore.remove(context, id)
        }
    }
}

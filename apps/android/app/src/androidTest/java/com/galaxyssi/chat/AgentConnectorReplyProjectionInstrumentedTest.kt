package com.galaxyssi.chat

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.util.UUID
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AgentConnectorReplyProjectionInstrumentedTest {
    private val context get() = ApplicationProvider.getApplicationContext<Context>()

    @Test fun alreadySavedReplyRepairsMissingUsageWithoutDuplicatingText() {
        val store = AgentTranscriptStore(context, "projection-${UUID.randomUUID()}")
        val conversation = store.createConversation(privateMode = true)
        val turn = "turn-${UUID.randomUUID()}"
        val reply = AgentConnectorResponse(17, "contact", "Saved reply", conversation.id, turn, "task",
            inputTokens = 20, outputTokens = 10, costMicros = 3, executionGeneration = 1)
        try {
            store.append(AgentTranscriptRole.USER, "Question", conversationId = conversation.id, turnId = turn)
            val key = AgentFinalResponseIdentity.dedupeKey(turn, 17, "task")
            store.upsert(AgentTranscriptRole.ASSISTANT, reply.content, key,
                conversationId = conversation.id, turnId = turn, taskId = "task")
            assertEquals(0L, store.conversation(conversation.id)?.inputTokens)
            assertFalse(store.persistConnectorReply(conversation.id, turn, "task", reply))
            val reopened = AgentTranscriptStore(context, "reopened-${UUID.randomUUID()}")
            assertFalse(reopened.persistConnectorReply(conversation.id, turn, "task", reply))
            assertEquals(1, reopened.list(conversation.id).count { it.dedupeKey == key })
            assertEquals(20L, reopened.conversation(conversation.id)?.inputTokens)
            assertEquals(10L, reopened.conversation(conversation.id)?.outputTokens)
            assertEquals(3L, reopened.conversation(conversation.id)?.costMicros)
        } finally { store.deleteConversation(conversation.id) }
    }

    @Test fun blankReplyCannotCommitUsageOrReplaceExistingAnswer() {
        val store = AgentTranscriptStore(context, "blank-projection-${UUID.randomUUID()}")
        val conversation = store.createConversation(privateMode = true)
        val turn = "turn-${UUID.randomUUID()}"
        val reply = AgentConnectorResponse(19, "contact", " ", conversation.id, turn, "task", inputTokens = 99)
        try {
            store.append(AgentTranscriptRole.USER, "Question", conversationId = conversation.id, turnId = turn)
            assertTrue(runCatching { store.persistConnectorReply(conversation.id, turn, "task", reply) }.isFailure)
            assertEquals(0L, store.conversation(conversation.id)?.inputTokens)
            assertFalse(store.list(conversation.id).any { it.role == AgentTranscriptRole.ASSISTANT })
        } finally { store.deleteConversation(conversation.id) }
    }
}

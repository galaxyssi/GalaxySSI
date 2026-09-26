package com.galaxyssi.chat

import android.os.Bundle
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test

class AgentDeliveryFailureStatusDeviceTest {
    @Test fun reportedFailureIsNotAnimatedAndRemainsDurablyFailed() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val title = InstrumentationRegistry.getArguments().getString("reportedTitle")
        assumeTrue(!title.isNullOrBlank())
        val context = instrumentation.targetContext
        val transcript = AgentTranscriptStore(context)
        val conversation = transcript.conversations().single { it.title == title }
        val latest = requireNotNull(transcript.previewEntry(conversation.latestMessageEntryId))
        val workspace = requireNotNull(ConversationHubAgentStatusPolicy.workspace(conversation.id, latest,
            EncryptedAgentWorkspaceStore(context).list()))
        val state = ConversationHubAgentStatusPolicy.resolve(workspace, latest, false)
        instrumentation.sendStatus(0, Bundle().apply {
            putString("stream", "reported_status=$state workspace=${workspace.status} " +
                "reply_kind=${latest.dedupeKey.substringBefore(':')} " +
                "bound_terminal=${AgentDeliveryFailureRecorder.terminalFailure(context, workspace) != null}\n")
        })
        assertEquals(ConversationHubAgentStatus.FAILED, state)
        assertFalse(state.animated)
        assertEquals(AgentWorkspaceStatus.FAILED, workspace.status)
    }

    @Test fun tenOtherTasksKeepRunningAndFailureProjectionIsReadOnly() {
        val failure = AgentTranscriptEntry("a", AgentTranscriptRole.ASSISTANT, "failed", 20,
            dedupeKey = "delivery-failed:123", conversationId = "c", turnId = "t", taskId = "t")
        val old = AgentWorkspace("t", "s", "c", "t", status = AgentWorkspaceStatus.WAITING_RESPONSE,
            createdAtMillis = 10, eventJournal = listOf(AgentWorkspaceEvent(
                kind = AgentTaskEventKinds.RECOVERY_WAITING_RESPONSE, timestampMillis = 30)))
        repeat(10_000) { assertEquals(ConversationHubAgentStatus.FAILED,
            ConversationHubAgentStatusPolicy.resolve(old, failure, false)) }
        assertEquals(AgentWorkspaceStatus.WAITING_RESPONSE, old.status)
        repeat(10) { index ->
            val id = "active-$index"
            val active = old.copy(workspaceId = id, taskId = id, conversationId = id)
            val question = failure.copy(role = AgentTranscriptRole.USER, dedupeKey = "", turnId = id,
                taskId = id, conversationId = id)
            assertEquals(ConversationHubAgentStatus.RECONNECTING,
                ConversationHubAgentStatusPolicy.resolve(active, question, false))
        }
    }
}

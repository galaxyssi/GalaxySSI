package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class ConversationHubAgentStatusTest {
    private val question = AgentTranscriptEntry("q", AgentTranscriptRole.USER, "Question", 10,
        conversationId = "c", turnId = "t", taskId = "t")
    private val answer = question.copy(id = "a", role = AgentTranscriptRole.ASSISTANT, dedupeKey = "assistant-final:t")
    private fun workspace(status: AgentWorkspaceStatus) = AgentWorkspace("t", "s", "c", "t", status = status)
    private fun resolve(status: AgentWorkspaceStatus, reply: AgentTranscriptEntry = question, unread: Boolean = false) =
        ConversationHubAgentStatusPolicy.resolve(workspace(status), reply, unread)

    @Test fun activeStatesNeverLookCompletedEvenWithOlderUnreadReplies() {
        assertEquals(ConversationHubAgentStatus.QUEUED, resolve(AgentWorkspaceStatus.QUEUED, unread = true))
        assertEquals(ConversationHubAgentStatus.RUNNING, resolve(AgentWorkspaceStatus.RUNNING, unread = true))
        assertEquals(ConversationHubAgentStatus.WAITING_RESPONSE, resolve(AgentWorkspaceStatus.WAITING_RESPONSE))
    }
    @Test fun completionMustWaitForDeliveredReply() {
        assertEquals(ConversationHubAgentStatus.DELIVERING, resolve(AgentWorkspaceStatus.COMPLETED, unread = true))
    }
    @Test fun deliveredUnreadReplyUsesCheckAndReadReplyUsesBubble() {
        assertEquals(ConversationHubAgentStatus.COMPLETE_UNREAD, resolve(AgentWorkspaceStatus.COMPLETED, answer, true))
        assertEquals(ConversationHubAgentStatus.READ, resolve(AgentWorkspaceStatus.COMPLETED, answer, false))
    }
    @Test fun failureIsNotTurnedIntoSuccessByErrorReply() {
        assertEquals(ConversationHubAgentStatus.FAILED, resolve(AgentWorkspaceStatus.FAILED, answer, true))
        assertEquals(ConversationHubAgentStatus.BLOCKED, resolve(AgentWorkspaceStatus.BLOCKED, answer, true))
    }
    @Test fun pauseConfirmationAndStopAreDistinct() {
        assertEquals(ConversationHubAgentStatus.PAUSED, resolve(AgentWorkspaceStatus.PAUSED))
        assertEquals(ConversationHubAgentStatus.WAITING_CONFIRMATION, resolve(AgentWorkspaceStatus.WAITING_CONFIRMATION))
        assertEquals(ConversationHubAgentStatus.CANCELLED, resolve(AgentWorkspaceStatus.CANCELLED))
    }
    @Test fun missingWorkspaceDoesNotClaimAnUnansweredQuestionIsRead() {
        assertEquals(ConversationHubAgentStatus.WAITING_RESPONSE,
            ConversationHubAgentStatusPolicy.resolve(null, question, false))
    }
    @Test fun historicalRepliesRemainReadWithoutNewUnreadEvidence() {
        assertEquals(ConversationHubAgentStatus.READ, ConversationHubAgentStatusPolicy.resolve(null, answer, false))
        assertEquals(ConversationHubAgentStatus.COMPLETE_UNREAD, ConversationHubAgentStatusPolicy.resolve(null, answer, true))
    }
    @Test fun workspaceMustMatchBothConversationAndCurrentTurn() {
        val correct = workspace(AgentWorkspaceStatus.RUNNING)
        val other = correct.copy(conversationId = "other", updatedAtMillis = 99)
        val old = correct.copy(workspaceId = "old", taskId = "old", updatedAtMillis = 100)
        assertEquals(correct, ConversationHubAgentStatusPolicy.workspace("c", question, listOf(other, old, correct)))
        assertNull(ConversationHubAgentStatusPolicy.workspace("c", question, listOf(other, old)))
    }
    @Test fun reconnectionIsNotCompletion() {
        val reconnecting = workspace(AgentWorkspaceStatus.WAITING_RESPONSE).copy(eventJournal = listOf(
            AgentWorkspaceEvent(kind = AgentTaskEventKinds.RECOVERY_WAITING_RESPONSE)))
        assertEquals(ConversationHubAgentStatus.RECONNECTING,
            ConversationHubAgentStatusPolicy.resolve(reconnecting, question, false))
    }
    @Test fun progressAfterRecoveryRestoresNormalWaitingState() {
        val active = workspace(AgentWorkspaceStatus.WAITING_RESPONSE).copy(eventJournal = listOf(
            AgentWorkspaceEvent(kind = AgentTaskEventKinds.RECOVERY_WAITING_RESPONSE),
            AgentWorkspaceEvent(kind = AgentTaskEventKinds.PROGRESS)))
        assertEquals(ConversationHubAgentStatus.WAITING_RESPONSE,
            ConversationHubAgentStatusPolicy.resolve(active, question, false))
    }
    @Test fun onlyActiveStatesAnimate() {
        assertTrue(ConversationHubAgentStatus.RUNNING.animated)
        assertFalse(ConversationHubAgentStatus.COMPLETE_UNREAD.animated)
        assertFalse(ConversationHubAgentStatus.READ.animated)
        assertFalse(ConversationHubAgentStatus.FAILED.animated)
    }
}

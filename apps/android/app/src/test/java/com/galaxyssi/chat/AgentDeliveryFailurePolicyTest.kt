package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class AgentDeliveryFailurePolicyTest {
    private val workspace = AgentWorkspace("turn", "session", "conversation", "turn",
        status = AgentWorkspaceStatus.WAITING_RESPONSE, createdAtMillis = 10)
    private val failure = AgentTranscriptEntry("failure", AgentTranscriptRole.ASSISTANT, "not delivered", 20,
        dedupeKey = "delivery-failed:123", conversationId = "conversation", turnId = "turn", taskId = "turn")

    @Test fun exactFailureIsTerminalButNotSuccess() {
        assertEquals(123L, AgentDeliveryFailurePolicy.sourceMessageId(failure))
        assertTrue(AgentTaskTerminalReplyPolicy.isTerminalReply(failure))
        assertTrue(AgentTaskTerminalReplyPolicy.hasTerminalReply(listOf(failure), "turn"))
        assertTrue(AgentDeliveryFailurePolicy.matches(workspace, failure))
        assertEquals(ConversationHubAgentStatus.FAILED,
            ConversationHubAgentStatusPolicy.resolve(workspace, failure, true))
    }

    @Test fun malformedAndStreamingFailuresCannotEndATask() {
        listOf("delivery-failed:", "delivery-failed:turn", "delivery-failed:0", "delivery-failed:-1")
            .forEach { assertNull(AgentDeliveryFailurePolicy.sourceMessageId(failure.copy(dedupeKey = it))) }
        assertNull(AgentDeliveryFailurePolicy.sourceMessageId(failure.copy(role = AgentTranscriptRole.PROCESS)))
        assertNull(AgentDeliveryFailurePolicy.sourceMessageId(failure.copy(id = "agent-stream-turn")))
    }

    @Test fun otherConversationTurnTaskAndEarlierAttemptAreUntouched() {
        listOf(failure.copy(conversationId = "other"), failure.copy(turnId = "other", taskId = "other"),
            failure.copy(timestampMillis = 9), failure.copy(turnId = ""))
            .forEach { assertFalse(AgentDeliveryFailurePolicy.matches(workspace, it)) }
        assertFalse(AgentDeliveryFailurePolicy.matches(workspace.copy(taskId = "child"),
            failure.copy(taskId = "other-child")))
    }

    @Test fun parentHandoffFailureCanCarryExecutorTaskId() {
        assertTrue(AgentDeliveryFailurePolicy.matches(workspace, failure.copy(taskId = "remote-task")))
    }

    @Test fun explicitResumeWinsButLateRecoveryProgressDoesNotReviveFailure() {
        assertFalse(AgentDeliveryFailurePolicy.matches(workspace.copy(eventJournal = listOf(
            AgentWorkspaceEvent(kind = AgentTaskEventKinds.RESUMED, timestampMillis = 30))), failure))
        assertTrue(AgentDeliveryFailurePolicy.matches(workspace.copy(eventJournal = listOf(
            AgentWorkspaceEvent(kind = AgentTaskEventKinds.RECOVERY_WAITING_RESPONSE, timestampMillis = 30))), failure))
    }

    @Test fun failuresNeverOverrideUserControlledOrCancelledStates() {
        val states = mapOf(AgentWorkspaceStatus.PAUSED to ConversationHubAgentStatus.PAUSED,
            AgentWorkspaceStatus.WAITING_CONFIRMATION to ConversationHubAgentStatus.WAITING_CONFIRMATION,
            AgentWorkspaceStatus.CANCELLED to ConversationHubAgentStatus.CANCELLED)
        states.forEach { (status, expected) -> assertEquals(expected,
            ConversationHubAgentStatusPolicy.resolve(workspace.copy(status = status), failure, false)) }
    }

    @Test fun failedDeliveryDoesNotLookSuccessfulWhenExecutionWasCompleted() {
        assertEquals(ConversationHubAgentStatus.FAILED, ConversationHubAgentStatusPolicy.resolve(
            workspace.copy(status = AgentWorkspaceStatus.COMPLETED), failure, true))
        assertEquals(ConversationHubAgentStatus.FAILED, ConversationHubAgentStatusPolicy.resolve(null, failure, true))
    }
}

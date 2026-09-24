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

    @Test fun committedFinalReplyReconcilesStaleActiveStates() {
        listOf(AgentWorkspaceStatus.CREATED, AgentWorkspaceStatus.QUEUED,
            AgentWorkspaceStatus.RUNNING, AgentWorkspaceStatus.WAITING_RESPONSE).forEach { status ->
            assertEquals(ConversationHubAgentStatus.READ, resolve(status, answer))
            assertEquals(ConversationHubAgentStatus.COMPLETE_UNREAD, resolve(status, answer, true))
        }
    }
    @Test fun lateProgressOrRecoveryCannotReviveDeliveredReply() {
        listOf(AgentTaskEventKinds.PROGRESS, AgentTaskEventKinds.RUNNING,
            AgentTaskEventKinds.RECOVERY_WAITING_RESPONSE).forEach { kind ->
            val stale = workspace(AgentWorkspaceStatus.WAITING_RESPONSE).copy(
                updatedAtMillis = 100,
                eventJournal = listOf(AgentWorkspaceEvent(kind = kind, timestampMillis = 100)))
            assertEquals(ConversationHubAgentStatus.READ,
                ConversationHubAgentStatusPolicy.resolve(stale, answer, false))
        }
    }
    @Test fun deliveredReplyDoesNotOverrideExplicitUserOrFailureStates() {
        val expected = mapOf(AgentWorkspaceStatus.PAUSED to ConversationHubAgentStatus.PAUSED,
            AgentWorkspaceStatus.WAITING_CONFIRMATION to ConversationHubAgentStatus.WAITING_CONFIRMATION,
            AgentWorkspaceStatus.BLOCKED to ConversationHubAgentStatus.BLOCKED,
            AgentWorkspaceStatus.FAILED to ConversationHubAgentStatus.FAILED,
            AgentWorkspaceStatus.CANCELLED to ConversationHubAgentStatus.CANCELLED)
        expected.forEach { (status, state) -> assertEquals(state, resolve(status, answer, true)) }
    }
    @Test fun streamAndUnclassifiedAssistantMessagesDoNotEndExecution() {
        listOf(answer.copy(id = "agent-stream-preview-t"),
            answer.copy(id = "agent-stream-t"), answer.copy(dedupeKey = ""),
            answer.copy(dedupeKey = "approval:t"), answer.copy(dedupeKey = "remote-approval:t"),
            answer.copy(dedupeKey = "delivery-failed:t"), answer.copy(dedupeKey = "task-watchdog-timeout:t"),
            answer.copy(role = AgentTranscriptRole.PROCESS)).forEach { entry ->
            assertEquals(ConversationHubAgentStatus.RUNNING, resolve(AgentWorkspaceStatus.RUNNING, entry))
        }
    }
    @Test fun finalFromAnotherConversationOrTaskCannotEndCurrentTask() {
        listOf(answer.copy(conversationId = "other"), answer.copy(conversationId = ""),
            answer.copy(taskId = "previous-task"), answer.copy(taskId = "", turnId = "old-turn"),
            answer.copy(taskId = "", turnId = "")).forEach { entry ->
            assertEquals(ConversationHubAgentStatus.RUNNING, resolve(AgentWorkspaceStatus.RUNNING, entry))
        }
    }
    @Test fun legacyFinalWithTurnButNoTaskCanReconcileOnlyMatchingWorkspace() {
        assertEquals(ConversationHubAgentStatus.READ,
            resolve(AgentWorkspaceStatus.RUNNING, answer.copy(taskId = "")))
    }
    @Test fun canonicalWholeTurnReplyReconcilesParentWithDifferentExecutorTaskId() {
        val remoteFinal = answer.copy(taskId = "executor-task",
            dedupeKey = AgentFinalResponseIdentity.dedupeKey("t"))
        assertEquals(ConversationHubAgentStatus.READ, resolve(AgentWorkspaceStatus.RUNNING, remoteFinal))
        assertEquals(ConversationHubAgentStatus.COMPLETE_UNREAD,
            resolve(AgentWorkspaceStatus.WAITING_RESPONSE, remoteFinal, true))
    }
    @Test fun executorTaskResultCannotPretendToBeWholeTurnFinal() {
        listOf("result:executor-task", "assistant-final:task:executor-task", "assistant-final:turn:other-turn")
            .forEach { key ->
                assertEquals(ConversationHubAgentStatus.RUNNING, resolve(AgentWorkspaceStatus.RUNNING,
                    answer.copy(taskId = "executor-task", dedupeKey = key)))
            }
    }
    @Test fun wholeTurnFinalCannotEndAnotherChildWorkspaceInSameTurn() {
        val child = workspace(AgentWorkspaceStatus.RUNNING).copy(taskId = "child-task")
        assertEquals(ConversationHubAgentStatus.RUNNING, ConversationHubAgentStatusPolicy.resolve(child,
            answer.copy(taskId = "other-child", dedupeKey = AgentFinalResponseIdentity.dedupeKey("t")), false))
    }
    @Test fun previousAttemptReplyCannotEndNewerWorkspace() {
        val newer = workspace(AgentWorkspaceStatus.RUNNING).copy(createdAtMillis = 20)
        assertEquals(ConversationHubAgentStatus.RUNNING,
            ConversationHubAgentStatusPolicy.resolve(newer, answer, false))
    }
    @Test fun explicitResumeAfterFinalRemainsRunningUntilAnotherFinal() {
        val resumed = workspace(AgentWorkspaceStatus.RUNNING).copy(eventJournal = listOf(
            AgentWorkspaceEvent(kind = AgentTaskEventKinds.RESUMED, timestampMillis = 20)))
        assertEquals(ConversationHubAgentStatus.RUNNING,
            ConversationHubAgentStatusPolicy.resolve(resumed, answer, false))
        assertEquals(ConversationHubAgentStatus.READ,
            ConversationHubAgentStatusPolicy.resolve(resumed, answer.copy(timestampMillis = 30), false))
    }
    @Test fun cancellationInFlightIsNotTurnedIntoSuccessfulCompletion() {
        val cancelling = workspace(AgentWorkspaceStatus.RUNNING).copy(cancellationRequested = true)
        assertEquals(ConversationHubAgentStatus.RUNNING,
            ConversationHubAgentStatusPolicy.resolve(cancelling, answer, false))
    }
    @Test fun persistedReplyRemainsReadWhenWorkspaceIsEvicted() {
        assertEquals(ConversationHubAgentStatus.READ, resolve(AgentWorkspaceStatus.RUNNING, answer))
        assertEquals(ConversationHubAgentStatus.READ, ConversationHubAgentStatusPolicy.resolve(null, answer, false))
    }
    @Test fun newQuestionInSameConversationRemainsActive() {
        val next = question.copy(id = "q2", taskId = "t2", turnId = "t2", timestampMillis = 30)
        val current = workspace(AgentWorkspaceStatus.RUNNING).copy(workspaceId = "t2", taskId = "t2", createdAtMillis = 30)
        val selected = ConversationHubAgentStatusPolicy.workspace("c", next,
            listOf(workspace(AgentWorkspaceStatus.RUNNING), current))
        assertEquals(current, selected)
        assertEquals(ConversationHubAgentStatus.RUNNING, ConversationHubAgentStatusPolicy.resolve(selected, next, true))
    }
    @Test fun allExistingTerminalReplyFormatsAreSupportedWithoutParsingText() {
        listOf("assistant-final:", "result:", "direct-system:", "fast-local:", "skill-command:", "skill-result:")
            .forEach { prefix ->
                assertEquals(ConversationHubAgentStatus.READ,
                    resolve(AgentWorkspaceStatus.RUNNING, answer.copy(dedupeKey = prefix + "t",
                        text = "", textLength = 100, textChunkCount = 1)))
            }
    }
    @Test fun listResolutionDoesNotMutateWorkspaceOrItsJournal() {
        val original = workspace(AgentWorkspaceStatus.RUNNING).copy(eventJournal = listOf(
            AgentWorkspaceEvent(kind = AgentTaskEventKinds.PROGRESS, message = "Planning")))
        val snapshot = original.copy()
        repeat(10_000) {
            assertEquals(ConversationHubAgentStatus.READ,
                ConversationHubAgentStatusPolicy.resolve(original, answer, false))
        }
        assertEquals(snapshot, original)
    }
}

package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class AgentCompletedReplyRecoveryTest {
    private val response = AgentConnectorResponse(12, "peer", "Answer", "conversation", "turn", "remote-task")
    private val identity = AgentConnectorResponseIdentity("conversation", "remote-task", "turn")
    private val loop = AgentExecutionLoop.create { 1_000L }.apply {
        start("turn", AgentExecutionLoopBudget())
        transition(AgentExecutionLoopPhase.VERIFY)
        transition(AgentExecutionLoopPhase.FINALIZE)
    }.snapshot!!
    private val session = AgentSessionSnapshot("session", AgentPhase.COMPLETED, "Identify the image",
        ScreenContext("Fixture", pageTitle = "Fixture"), null, emptyList(), AgentActionResult("answer", true, "Answer", mapOf(
            "source_message_id" to "12", "contact_id" to "peer", "conversation_id" to "conversation",
            "turn_id" to "turn", "remote_task_id" to "remote-task", "awaiting_response" to "false")),
        executionLoopSnapshot = loop, processInstanceId = "previous-process", updatedAtMillis = 1_000L)

    @Test fun acceptedAnswerCanBeCommittedWithoutModelReplay() = assertTrue(matches())
    @Test fun failedProviderCannotUseCommitRecovery() = assertFalse(matches(response.copy(success = false)))
    @Test fun cancelledSessionIsNeverRecovered() = assertFalse(matches(session = session.copy(phase = AgentPhase.CANCELLED)))
    @Test fun unfinishedActionIsNotACompletedAnswer() = assertFalse(matches(session = session.copy(phase = AgentPhase.EXECUTING)))
    @Test fun anotherConversationCannotReceiveTheAnswer() = assertFalse(matches(response.copy(conversationId = "other")))
    @Test fun anotherTurnCannotReceiveTheAnswer() = assertFalse(matches(response.copy(turnId = "other")))
    @Test fun anotherRemoteTaskCannotReceiveTheAnswer() = assertFalse(matches(response.copy(taskId = "other")))
    @Test fun anotherPeerCannotReceiveTheAnswer() = assertFalse(matches(response.copy(contactId = "other")))
    @Test fun anotherSourceCannotReuseTheAnswer() = assertFalse(matches(response.copy(sourceMessageId = 13)))
    @Test fun anotherGenerationCannotReuseTheAnswer() = assertFalse(matches(response.copy(executionGeneration = 2)))
    @Test fun missingIdentityIsNotGuessed() = assertFalse(matches(response.copy(turnId = "")))
    @Test fun previousProcessOnlyFinishesTheSavedAnswer() = assertFalse(AgentSessionInterruptionPolicy.wasInterrupted(session))
    @Test fun previousProcessStillPausesUnfinishedWork() = assertTrue(AgentSessionInterruptionPolicy.wasInterrupted(
        session.copy(phase = AgentPhase.EXECUTING)))
    @Test fun missingSuccessfulAnswerIsNotFinalizationRecovery() = assertFalse(matches(session = session.copy(lastActionResult = null)))

    @Test fun olderReloadCannotRollFinalizationBackToVerification() {
        assertFalse(AgentSessionReloadPolicy.shouldRestore(loop, loop.copy(revision = loop.revision - 1, phase = AgentExecutionLoopPhase.VERIFY)))
        assertFalse(AgentSessionReloadPolicy.shouldRestore(loop, loop.copy(phase = AgentExecutionLoopPhase.VERIFY)))
    }
    @Test fun reloadRequiresTheSameTaskAndMonotonicRevision() {
        assertTrue(AgentSessionReloadPolicy.shouldRestore(null, loop))
        assertTrue(AgentSessionReloadPolicy.shouldRestore(loop, loop))
        assertTrue(AgentSessionReloadPolicy.shouldRestore(loop, loop.copy(revision = loop.revision + 1, phase = AgentExecutionLoopPhase.LEARN)))
        assertFalse(AgentSessionReloadPolicy.shouldRestore(loop, loop.copy(taskId = "other")))
        assertFalse(AgentSessionReloadPolicy.shouldRestore(loop, null))
    }
    @Test fun pageReloadCannotReopenTerminalTasks() {
        assertFalse(AgentSessionReloadPolicy.shouldRestore(loop.copy(phase = AgentExecutionLoopPhase.CANCELLED),
            loop.copy(revision = loop.revision + 1)))
    }
    private fun failedWorkspace() = AgentWorkspace("workspace", "session", "conversation", "turn",
        status = AgentWorkspaceStatus.FAILED, eventJournal = listOf(
            AgentWorkspaceEvent(1, "agent.loop.finalize"),
            AgentWorkspaceEvent(2, AgentTaskEventKinds.FAILED, "Invalid Agent loop transition from VERIFY to LEARN")))

    @Test fun legacyFinalizationFailureCanFinishAfterReopening() {
        assertTrue(AgentCompletedReplyRecovery.failedDuringFinalization(failedWorkspace()))
        assertTrue(AgentCompletedReplyRecovery.failedDuringFinalization(
            failedWorkspace().copy(status = AgentWorkspaceStatus.WAITING_RESPONSE)))
    }
    @Test fun cancellationAndManualPauseAreNotReopened() {
        assertFalse(AgentCompletedReplyRecovery.failedDuringFinalization(failedWorkspace().copy(cancellationRequested = true)))
        assertFalse(AgentCompletedReplyRecovery.failedDuringFinalization(failedWorkspace().copy(status = AgentWorkspaceStatus.CANCELLED)))
        assertFalse(AgentCompletedReplyRecovery.failedDuringFinalization(failedWorkspace().copy(status = AgentWorkspaceStatus.PAUSED)))
    }
    @Test fun unrelatedFailuresAndMissingFinalizationEvidenceAreNotRetried() {
        val failed = failedWorkspace()
        assertFalse(AgentCompletedReplyRecovery.failedDuringFinalization(failed.copy(eventJournal =
            failed.eventJournal + AgentWorkspaceEvent(3, AgentTaskEventKinds.FAILED, "Provider unavailable"))))
        assertFalse(AgentCompletedReplyRecovery.failedDuringFinalization(failed.copy(eventJournal = failed.eventJournal.drop(1))))
    }
    private fun matches(response: AgentConnectorResponse = this.response, session: AgentSessionSnapshot = this.session) =
        AgentCompletedReplyRecovery.matches(session, response, identity)
}

package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class AgentInitialPlanningRecoveryPolicyTest {
    private val workspace = AgentWorkspace("workspace", "owner", "conversation", "turn", status = AgentWorkspaceStatus.RUNNING)
    private val reference = AgentInitialPlanningReference("runtime", "conversation", "turn", "hash")
    private fun session() = AgentSessionSnapshot("runtime", AgentPhase.PLANNING, "Recover planning",
        ScreenContext("Test", pageTitle = "Test"), null, emptyList(), null,
        executionLoopSnapshot = AgentExecutionLoop.create().also { it.start("turn", AgentExecutionLoopBudget()) }.snapshot,
        processInstanceId = "previous-process", pendingPlanning = reference, updatedAtMillis = 1L)

    @Test fun initialPlanningWithoutAPlanIsRecoverable() {
        assertEquals(AgentLongTaskRecoveryMode.INITIAL_PLANNING,
            AgentLongTaskRecoveryPolicy.decide(workspace, session())?.mode)
    }
    @Test fun coldBootPauseRetainsTheOriginalReference() {
        val paused = AgentColdBootRecoveryPolicy.pauseSession(session(), AgentProcessIdentity.instanceId, 2L, "Restart")
        assertEquals(reference, paused.pendingPlanning)
        assertEquals(AgentLongTaskRecoveryMode.INITIAL_PLANNING,
            AgentLongTaskRecoveryPolicy.decide(workspace.copy(status = AgentWorkspaceStatus.PAUSED), paused)?.mode)
    }
    @Test fun missingReferenceCannotInventPlanningWork() {
        assertNull(AgentLongTaskRecoveryPolicy.decide(workspace, session().copy(pendingPlanning = null)))
    }
    @Test fun scopeMismatchCannotRestoreAnotherConversationOrTurn() {
        listOf(reference.copy(sessionId = "other"), reference.copy(conversationId = "other"),
            reference.copy(turnId = "other")).forEach {
            assertNull(AgentLongTaskRecoveryPolicy.decide(workspace, session().copy(pendingPlanning = it)))
        }
    }
    @Test fun activeOwnerAndUserPauseAreNotAutomaticallyResumed() {
        assertNull(AgentLongTaskRecoveryPolicy.decide(workspace, session(), setOf(workspace.workspaceId)))
        assertNull(AgentLongTaskRecoveryPolicy.decide(workspace,
            session().copy(lastActionResult = AgentActionResult("agent-paused", true, "Paused"))))
        assertNull(AgentLongTaskRecoveryPolicy.decide(workspace,
            session().copy(processInstanceId = AgentProcessIdentity.instanceId)))
    }
    @Test fun terminalWorkspacesAndCancelledTasksStayTerminal() {
        AgentWorkspaceStatus.entries.filter { it.isTerminal }.forEach {
            assertNull(AgentLongTaskRecoveryPolicy.decide(workspace.copy(status = it), session()))
        }
        assertNull(AgentLongTaskRecoveryPolicy.decide(workspace.copy(cancellationRequested = true), session()))
    }
    @Test fun explicitModelFailureDoesNotBecomeAnAutomaticRetry() {
        val original = session()
        assertNull(AgentLongTaskRecoveryPolicy.decide(workspace,
            original.copy(executionLoopSnapshot = original.executionLoopSnapshot!!.copy(phase = AgentExecutionLoopPhase.FAILED))))
        assertNull(AgentLongTaskRecoveryPolicy.decide(workspace, original.copy(phase = AgentPhase.FAILED)))
    }
}

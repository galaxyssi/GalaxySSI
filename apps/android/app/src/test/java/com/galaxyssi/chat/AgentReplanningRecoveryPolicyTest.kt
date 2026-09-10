package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class AgentReplanningRecoveryPolicyTest {
    private val workspace = AgentWorkspace("workspace", "owner", "conversation", "turn", status = AgentWorkspaceStatus.RUNNING)
    private val reference = AgentPlanningReference("runtime", "conversation", "turn", "hash", "plan", 7)
    private val action = AgentAction("done", AgentActionKind.CALL_NATIVE_TOOL, "test.read", AgentRisk.LOW,
        AgentActionStatus.COMPLETED, "Done", result = "preserved")
    private val plan = AgentPlan("Continue", ScreenContext("Test", pageTitle = "Test"), emptyList(), listOf(action),
        planId = "plan", revision = 7)
    private fun session() = AgentSessionSnapshot("runtime", AgentPhase.PLANNING, "Continue", plan.screen,
        plan, emptyList(), null, executionLoopSnapshot = AgentExecutionLoop.create().also {
            it.start("turn", AgentExecutionLoopBudget()) }.snapshot,
        processInstanceId = "previous-process", pendingPlanning = reference, updatedAtMillis = 1)

    @Test fun completedBaseDoesNotFinishAnInterruptedReplan() {
        assertEquals(AgentLongTaskRecoveryMode.REPLANNING, AgentLongTaskRecoveryPolicy.decide(workspace, session())?.mode)
    }
    @Test fun changedScopeAndRevisionCannotFallThroughToOrdinaryActionRecovery() {
        listOf(reference.copy(sessionId = "other"), reference.copy(conversationId = "other"), reference.copy(turnId = "other"),
            reference.copy(basePlanId = "other"), reference.copy(baseRevision = 8)).forEach {
            val saved = session().copy(pendingPlanning = it,
                currentPlan = plan.copy(actions = listOf(action.copy(status = AgentActionStatus.RUNNING))))
            assertNull(AgentLongTaskRecoveryPolicy.decide(workspace, saved))
        }
    }
    @Test fun coldBootKeepsTheModelBaseGraphImmutable() {
        val saved = session().copy(currentPlan = plan.copy(actions = listOf(action.copy(status = AgentActionStatus.RUNNING))))
        val paused = AgentColdBootRecoveryPolicy.pauseSession(saved, AgentProcessIdentity.instanceId, 2, "Restart")
        assertEquals(saved.currentPlan, paused.currentPlan)
        assertEquals(reference, paused.pendingPlanning)
        assertEquals(AgentLongTaskRecoveryMode.REPLANNING, AgentLongTaskRecoveryPolicy.decide(workspace, paused)?.mode)
    }
    @Test fun initialPlanningCannotClaimAnExistingPlan() {
        assertFalse(AgentInitialPlanningRecoveryPolicy.belongsTo(workspace, session()))
        assertFalse(AgentReplanningRecoveryPolicy.belongsTo(workspace, session().copy(pendingPlanning = reference.copy(
            basePlanId = "", baseRevision = 0))))
    }
    @Test fun activeOwnersAndManualPauseAreNotAutomaticallyResumed() {
        assertNull(AgentLongTaskRecoveryPolicy.decide(workspace, session(), setOf("workspace")))
        assertNull(AgentLongTaskRecoveryPolicy.decide(workspace,
            session().copy(lastActionResult = AgentActionResult("agent-paused", true, "Paused"))))
        assertNull(AgentLongTaskRecoveryPolicy.decide(workspace,
            session().copy(processInstanceId = AgentProcessIdentity.instanceId)))
    }
    @Test fun cancelledAndTerminalWorkAreNotResumed() {
        AgentWorkspaceStatus.entries.filter { it.isTerminal }.forEach {
            assertNull(AgentLongTaskRecoveryPolicy.decide(workspace.copy(status = it), session()))
        }
        assertNull(AgentLongTaskRecoveryPolicy.decide(workspace.copy(cancellationRequested = true), session()))
        assertNull(AgentLongTaskRecoveryPolicy.decide(workspace, session().copy(currentPlan = null)))
    }
}

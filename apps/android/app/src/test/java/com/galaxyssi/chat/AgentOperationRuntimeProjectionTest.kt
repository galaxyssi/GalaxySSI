package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class AgentOperationRuntimeProjectionTest {
    private val goal = "Modify the existing report and verify it"
    private val saved = AgentDeviceOperation("conversation", kind = "agent", goal = goal,
        status = "completed", sourceTurnId = "turn", sourceSessionId = "runtime", updatedAt = 10)
    private val action = AgentAction("node", AgentActionKind.DRAFT_PLAN, "task-complete", AgentRisk.LOW,
        AgentActionStatus.COMPLETED, "Verified result", mapOf(INTERNAL_CONVERSATION_ID to "conversation",
            INTERNAL_TURN_ID to "turn"))
    private val plan = AgentPlan(goal, ScreenContext("Test", pageTitle = "Test"), emptyList(), listOf(action), planId = "plan")
    private fun snapshot(phase: AgentPhase = AgentPhase.COMPLETED, loop: AgentExecutionLoopPhase = AgentExecutionLoopPhase.COMPLETED) =
        AgentSessionSnapshot("runtime", phase, goal, plan.screen, plan, emptyList(),
            AgentActionResult("node", true, "Verified result"), executionLoopSnapshot = AgentExecutionLoopSnapshot(
                "turn", loop, AgentExecutionLoopBudget(), AgentExecutionLoopUsage(), lastProgressAtMillis = 20,
                startedAtMillis = 1, updatedAtMillis = 20), processInstanceId = AgentProcessIdentity.instanceId, updatedAtMillis = 20)
    private fun project(state: AgentSessionSnapshot?) = AgentOperationRuntimeProjection.project(saved, state)

    @Test fun actualExecutionStateReplacesAnOldPlanCompletionFlag() {
        for ((phase, loop) in listOf(AgentPhase.PLANNING to AgentExecutionLoopPhase.PLAN,
            AgentPhase.EXECUTING to AgentExecutionLoopPhase.ACT, AgentPhase.VERIFYING to AgentExecutionLoopPhase.VERIFY,
            AgentPhase.WAITING_RESPONSE to AgentExecutionLoopPhase.WAITING_RESPONSE,
            AgentPhase.WAITING_CONFIRMATION to AgentExecutionLoopPhase.WAITING_CONFIRMATION)) {
            assertEquals(phase.name.lowercase(), project(snapshot(phase, loop)).status)
        }
    }

    @Test fun terminalAndPausedStatesAreNotInferredFromTheLastSuccessfulAction() {
        for ((phase, loop) in listOf(AgentPhase.CANCELLED to AgentExecutionLoopPhase.CANCELLED,
            AgentPhase.PAUSED to AgentExecutionLoopPhase.PAUSED, AgentPhase.FAILED to AgentExecutionLoopPhase.FAILED,
            AgentPhase.BLOCKED to AgentExecutionLoopPhase.BLOCKED)) {
            assertEquals(phase.name.lowercase(), project(snapshot(phase, loop)).status)
        }
    }

    @Test fun loopControlStateWinsWhileTheSessionPhaseIsCatchingUp() {
        for ((loop, status) in listOf(AgentExecutionLoopPhase.CANCELLED to "cancelled",
            AgentExecutionLoopPhase.PAUSED to "paused", AgentExecutionLoopPhase.FAILED to "failed",
            AgentExecutionLoopPhase.BLOCKED to "blocked")) {
            assertEquals(status, project(snapshot(AgentPhase.EXECUTING, loop)).status)
        }
    }

    @Test fun cancellationRemainsOwnedAfterClearingThePlanAndGoal() {
        val state = snapshot(AgentPhase.CANCELLED, AgentExecutionLoopPhase.CANCELLED).copy(currentGoal = "", currentPlan = null)
        val projected = project(state)
        assertEquals("cancelled", projected.status)
        assertEquals(goal, projected.goal)
        val context = AgentConversationContext("conversation", "", listOf(AgentTranscriptEntry("user", AgentTranscriptRole.USER,
            goal, 1, conversationId = "conversation", turnId = "turn")), false)
        assertNull(AgentSupervisedProjectContinuationPolicy.scopedOperation(context, projected))
        assertNull(AgentSupervisedProjectContinuationPolicy.mergedGoal("continue", context, operation = projected))
    }

    @Test fun missingOrUnreadableSessionDoesNotReuseAnOldCompletedClaim() {
        assertEquals("unknown", project(null).status)
        assertTrue(project(null).evidence.contains("missing_session"))
    }

    @Test fun mismatchedTurnOrRuntimeCannotProvideState() {
        val state = snapshot()
        for (invalid in listOf(state.copy(sessionId = "other"), state.copy(executionLoopSnapshot =
            state.executionLoopSnapshot!!.copy(taskId = "other")), state.copy(executionLoopSnapshot = null))) {
            assertEquals("unknown", project(invalid).status)
        }
    }

    @Test fun foreignAndMixedPlanScopesAreRejected() {
        for (foreign in listOf(action.copy(parameters = action.parameters + (INTERNAL_CONVERSATION_ID to "other")),
            action.copy(parameters = action.parameters + (INTERNAL_TURN_ID to "other")))) {
            assertEquals("unknown", project(snapshot().copy(currentPlan = plan.copy(actions = listOf(foreign)))).status)
            assertEquals("unknown", project(snapshot().copy(currentPlan = plan.copy(actions = listOf(action, foreign)))).status)
        }
    }

    @Test fun olderSessionCannotOverwriteNewerPlanContext() {
        assertEquals("unknown", project(snapshot().copy(updatedAtMillis = 9)).status)
    }

    @Test fun activeProcessDeathIsNotPresentedAsOngoingExecution() {
        val state = snapshot(AgentPhase.EXECUTING, AgentExecutionLoopPhase.ACT).copy(processInstanceId = "old-process")
        assertEquals("interrupted", project(state).status)
    }

    @Test fun remoteWaitSurvivesProcessChangeWithoutInventingRemoteFailure() {
        val state = snapshot(AgentPhase.WAITING_RESPONSE, AgentExecutionLoopPhase.WAITING_RESPONSE).copy(processInstanceId = "old")
        assertEquals("waiting_response", project(state).status)
    }

    @Test fun completedSessionNeedsCompletedLoopActionsAndVerifiedReceipt() {
        assertEquals("completed", project(snapshot()).status)
        assertEquals("finalizing", project(snapshot(loop = AgentExecutionLoopPhase.FINALIZE)).status)
        for (result in listOf(null, AgentActionResult("node", false, "Failed"),
            AgentActionResult("agent-resumed", true, "Task resumed"),
            AgentActionResult("node", true, "Accepted", mapOf("business_success_verified" to "false")))) {
            assertEquals("unverified", project(snapshot().copy(lastActionResult = result)).status)
        }
        for (status in AgentActionStatus.entries.filter { it != AgentActionStatus.COMPLETED }) {
            assertEquals("unverified", project(snapshot().copy(currentPlan = plan.copy(actions = listOf(action.copy(status = status))))).status)
        }
    }

    @Test fun planOnlyCompletionIsNotBusinessCompletion() {
        assertEquals("planned_not_executed", project(snapshot().copy(taskExecutionMode = AgentTaskExecutionMode.PLAN_ONLY)).status)
    }

    @Test fun permissionWaitingRequiresTheMatchingPersistedGate() {
        val pending = AgentRuntimePermissionContinuation("runtime", "conversation", "turn", "plan", 1, "node",
            listOf("android.permission.READ_CALENDAR"))
        val state = snapshot(AgentPhase.BLOCKED, AgentExecutionLoopPhase.BLOCKED).copy(
            currentPlan = plan.copy(actions = listOf(action.copy(status = AgentActionStatus.PROPOSED))),
            lastActionResult = pending.result(false))
        assertEquals("waiting_permission", project(state).status)
        for (invalid in listOf(pending.copy(turnId = "other"), pending.copy(conversationId = "other"), pending.copy(revision = 2))) {
            assertEquals("blocked", project(state.copy(lastActionResult = invalid.result(false))).status)
        }
    }

    @Test fun evidenceIsAReferencedSummaryNotAnUnboundedDuplicateReceipt() {
        val state = snapshot().copy(lastActionResult = AgentActionResult("node", true, "x".repeat(20000)))
        val projected = project(state)
        assertEquals(saved.id, projected.id)
        assertEquals("runtime", projected.sourceSessionId)
        assertEquals(20L, projected.updatedAt)
        assertTrue(projected.evidence.length < 1800)
        assertTrue(projected.evidence.contains("summary_only=true"))
        assertTrue(projected.evidence.contains("action_id=node"))
        assertEquals(20000, state.lastActionResult!!.message.length)
    }

    @Test fun repeatedReadsArePureAndDoNotCreateAnotherExecutionOrChangeTimestamps() {
        val state = snapshot()
        assertEquals(project(state), project(state))
        assertEquals("completed", saved.status)
        assertEquals(10L, saved.updatedAt)
        assertEquals("completed", project(state).status)
    }

    @Test fun legacyRecordRequiresExactPersistedPlanScopeWithoutGuessingOwner() {
        val legacy = saved.copy(sourceSessionId = "")
        assertEquals("completed", AgentOperationRuntimeProjection.project(legacy, snapshot()).status)
        assertEquals("unknown", AgentOperationRuntimeProjection.project(legacy, snapshot().copy(currentPlan = null)).status)
    }

    @Test fun dedicatedTimerContextRemainsUntouched() {
        val timer = saved.copy(kind = "timer", status = "waiting_accessibility", seconds = 60)
        assertEquals(timer, AgentOperationRuntimeProjection.project(timer, snapshot()))
    }
}

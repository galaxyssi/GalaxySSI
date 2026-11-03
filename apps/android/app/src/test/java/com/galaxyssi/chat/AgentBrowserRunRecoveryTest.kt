package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class AgentBrowserRunRecoveryTest {
    private val workspace = AgentWorkspace("supervised-run", "run-owner", "conversation", "turn",
        status = AgentWorkspaceStatus.RUNNING)
    private val scope = "a".repeat(64)
    private val record = AgentBrowserUserRequest(AgentBrowserUserRequest.key(scope, "browser"), "generation", scope,
        "runtime-session", "conversation", "turn", "caller",
        AgentWorkspaceScope.id("conversation", "runtime-session"), "browser", "page", "handoff", "returned",
        taskId = "turn", modelLoopId = "original-loop")
    private fun session() = AgentSessionSnapshot("runtime-session", AgentPhase.PLANNING, "Continue collecting",
        ScreenContext("Test", pageTitle = "Test"), null, emptyList(), null,
        executionLoopSnapshot = AgentExecutionLoop.create().also { it.start("turn", AgentExecutionLoopBudget()) }.snapshot,
        processInstanceId = AgentProcessIdentity.instanceId, updatedAtMillis = 1,
        pendingPlanning = AgentPlanningReference("runtime-session", "conversation", "turn", "input-hash"))
    private fun bound() = AgentBrowserRunRecoveryPolicy.bind(record, listOf(workspace)) { session() }
    private fun decide(record: AgentBrowserUserRequest = bound(), workspace: AgentWorkspace = this.workspace,
        session: AgentSessionSnapshot = session(), active: Set<String> = emptySet()) =
        AgentBrowserRunRecoveryPolicy.decision(record, workspace, session, active)

    @Test fun `run binding is not the file workspace or runtime session identity`() {
        val bound = bound()
        assertEquals("supervised-run", bound.runWorkspaceId)
        assertEquals("run-owner", bound.runSessionId)
        assertNotEquals(bound.workspaceId, bound.runWorkspaceId)
        assertNotEquals(bound.sessionId, bound.runSessionId)
        assertEquals(bound, AgentBrowserUserRequest.fromJson(bound.toJson()))
    }

    @Test fun `ambiguous or unrelated owners never invent a recoverable run`() {
        val second = workspace.copy(workspaceId = "another-run")
        assertEquals(record, AgentBrowserRunRecoveryPolicy.bind(record, listOf(workspace, second)) { session() })
        assertEquals(record, AgentBrowserRunRecoveryPolicy.bind(record, listOf(workspace)) { null })
        assertEquals(record, AgentBrowserRunRecoveryPolicy.bind(record, listOf(workspace)) {
            session().copy(sessionId = "another-runtime") })
        assertEquals(record, AgentBrowserRunRecoveryPolicy.bind(record, listOf(workspace.copy(taskId = "other"))) { session() })
        assertEquals(record.copy(modelLoopId = ""), AgentBrowserRunRecoveryPolicy.bind(record.copy(modelLoopId = ""),
            listOf(workspace)) { session() })
        assertNull(decide(record = record))
    }

    @Test fun `a collaboration member cannot inherit the ordinary parent planner recovery`() {
        val member = record.copy(collaborationSourceMessageId = 101)
        assertEquals(member, AgentBrowserRunRecoveryPolicy.bind(member, listOf(workspace)) { session() })
        assertFalse(AgentBrowserRunRecoveryPolicy.matches(bound().copy(collaborationSourceMessageId = 101), workspace, session()))
        assertNull(decide(record = bound().copy(collaborationSourceMessageId = 101)))
    }

    @Test fun `returned event resumes the saved planner without requiring process death`() {
        assertNull(AgentLongTaskRecoveryPolicy.decide(workspace, session()))
        assertEquals(AgentLongTaskRecoveryMode.INITIAL_PLANNING, decide()?.mode)
        assertEquals(AgentLongTaskRecoveryMode.INITIAL_PLANNING,
            decide(session = session().copy(processInstanceId = "previous-process"))?.mode)
        assertEquals(AgentLongTaskRecoveryMode.INITIAL_PLANNING,
            decide(session = session().copy(phase = AgentPhase.PAUSED))?.mode)
    }

    @Test fun `active original owner must settle before a second recovery can claim it`() {
        assertNull(decide(active = setOf(workspace.workspaceId)))
        assertNotNull(decide(active = setOf("independent-run")))
        assertNull(decide(record = bound().copy(state = "active")))
        assertNull(decide(record = bound().copy(runWakeAcknowledged = true)))
    }

    @Test fun `cancel pause and terminal evidence forbid automatic revival`() {
        AgentWorkspaceStatus.entries.filter { it.isTerminal }.forEach {
            assertNull(decide(workspace = workspace.copy(status = it)))
        }
        assertNull(decide(workspace = workspace.copy(cancellationRequested = true)))
        listOf(AgentPhase.COMPLETED, AgentPhase.FAILED, AgentPhase.CANCELLED).forEach {
            assertNull(decide(session = session().copy(phase = it)))
        }
        assertNull(decide(session = session().copy(lastActionResult = AgentActionResult("agent-paused", true, "User paused"))))
        assertNull(decide(session = session().copy(executionLoopSnapshot =
            session().executionLoopSnapshot!!.copy(phase = AgentExecutionLoopPhase.FAILED))))
    }

    @Test fun `changed task conversation run or file scope cannot consume another return`() {
        listOf(bound().copy(taskId = "other"), bound().copy(turnId = "other"), bound().copy(sessionId = "other"),
            bound().copy(conversationId = "other"), bound().copy(runWorkspaceId = "other"),
            bound().copy(runSessionId = "other"), bound().copy(workspaceId = "other")).forEach {
            assertNull(decide(record = it))
        }
        assertNull(decide(session = session().copy(pendingPlanning = null)))
        assertNull(decide(session = session().copy(pendingPlanning = session().pendingPlanning!!.copy(turnId = "other"))))
        assertNull(decide(session = session().copy(pendingPlanning = session().pendingPlanning!!.copy(inputSha256 = "new-input"))))
        assertNull(decide(record = bound().copy(runPlanningBinding = "")))
    }

    @Test fun `replanning resumes the exact saved base revision not a fresh goal`() {
        val plan = AgentPlan("Continue", session().currentScreen, emptyList(), emptyList(), planId = "base", revision = 7)
        val replan = session().copy(currentPlan = plan,
            pendingPlanning = session().pendingPlanning!!.copy(basePlanId = "base", baseRevision = 7))
        val originalReplan = AgentBrowserRunRecoveryPolicy.bind(record, listOf(workspace)) { replan }
        assertEquals(AgentLongTaskRecoveryMode.REPLANNING, decide(record = originalReplan, session = replan)?.mode)
        assertNull(decide(record = originalReplan, session = replan.copy(currentPlan = plan.copy(revision = 8))))
        assertNull(decide(record = originalReplan, session = replan.copy(pendingPlanning = replan.pendingPlanning!!.copy(
            inputSha256 = "new-replan"))))
    }

    @Test fun `wake acknowledgement is monotonic and cannot change owner bindings`() {
        val pending = bound()
        val acknowledged = pending.copy(runWakeAcknowledged = true)
        assertTrue(pending.pendingRunWake)
        assertFalse(acknowledged.pendingRunWake)
        assertTrue(pending.permitsSameGeneration(acknowledged))
        assertFalse(acknowledged.permitsSameGeneration(pending))
        assertFalse(pending.copy(state = "active").permitsSameGeneration(acknowledged.copy(state = "active")))
        assertFalse(pending.permitsSameGeneration(pending.copy(runWorkspaceId = "other")))
        assertFalse(pending.permitsSameGeneration(pending.copy(runSessionId = "other")))
        assertFalse(pending.permitsSameGeneration(pending.copy(runPlanningBinding = "other")))
    }

    @Test fun `generic startup recovery leaves a durable event wait dormant until its exact return`() {
        val waiting = session().copy(phase = AgentPhase.PAUSED,
            lastActionResult = AgentActionResult("agent-event-wait", true, "Waiting for browser control",
                metadata = mapOf("model_loop_wait_event" to "event")), processInstanceId = "previous-process",
            executionLoopSnapshot = session().executionLoopSnapshot!!.copy(phase = AgentExecutionLoopPhase.PAUSED))
        assertNull(AgentLongTaskRecoveryPolicy.decide(workspace, waiting))
        assertEquals(AgentLongTaskRecoveryMode.INITIAL_PLANNING, decide(session = waiting)?.mode)
        assertFalse(AgentSessionInterruptionPolicy.wasInterrupted(waiting))
    }

    @Test fun `an interrupted host resumes the exact saved planner but not a cancelled or manually paused task`() {
        val interrupted = bound().copy(state = "active", hostProcessId = "previous-host")
            .afterHostRestart("current-host")
        assertEquals(AgentLongTaskRecoveryMode.INITIAL_PLANNING, decide(record = interrupted)?.mode)
        assertTrue(decide(record = interrupted)!!.reason.contains("unconfirmed"))
        assertNull(decide(record = interrupted.copy(runWakeAcknowledged = true)))
        assertNull(decide(record = interrupted, workspace = workspace.copy(cancellationRequested = true)))
        assertNull(decide(record = interrupted,
            session = session().copy(lastActionResult = AgentActionResult("agent-paused", true, "User paused"))))
        assertNull(decide(record = interrupted, active = setOf(workspace.workspaceId)))
    }

    @Test fun `committed observation is monotonic but does not itself consume the pending wake`() {
        val pending = bound()
        val observed = pending.copy(modelObservationCommitted = true)
        assertTrue(pending.permitsSameGeneration(observed))
        assertFalse(observed.permitsSameGeneration(pending))
        assertTrue(observed.pendingRunWake)
        assertFalse(record.copy(state = "active").permitsSameGeneration(record.copy(state = "active", modelObservationCommitted = true)))
        assertEquals(observed, AgentBrowserUserRequest.fromJson(observed.toJson()))
    }
}

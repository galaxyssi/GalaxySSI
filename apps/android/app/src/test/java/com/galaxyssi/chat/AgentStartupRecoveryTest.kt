package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class AgentStartupRecoveryTest {
    private val screen = ScreenContext(foregroundApp = "GalaxySSI", pageTitle = "Agent")
    private val journal = object : AgentPlanNodeJournal {
        override fun start(key: AgentPlanNodeKey) = Unit
        override fun record(key: AgentPlanNodeKey, observation: AgentPlanNodeObservation) = Unit
        override fun read(key: AgentPlanNodeKey): AgentPlanNodeObservation? = null
    }
    private fun session(owner: String = "old") = AgentSessionSnapshot(
        sessionId = "session", phase = AgentPhase.EXECUTING, currentGoal = "Continue",
        currentScreen = screen, currentPlan = AgentPlan(goal = "Continue", screen = screen,
            steps = emptyList(), actions = emptyList(), confirmationRequired = false),
        auditTrail = emptyList(), lastActionResult = null, processInstanceId = owner,
        updatedAtMillis = 1L
    )
    private fun workspace(id: String = "task") = AgentWorkspace(
        workspaceId = id, sessionId = "session", conversationId = "conversation", taskId = id,
        status = AgentWorkspaceStatus.RUNNING
    )
    private fun recover(workspaces: AgentWorkspaceStore, sessions: Map<String, AgentSessionStore>,
                        active: Set<String> = emptySet()): Int =
        AgentColdBootRecoveryCoordinator.pauseInterruptedTasks(workspaces, sessions::getValue,
            InMemoryAgentSessionStore(), journal, { active }, "current", 10L, "Restarted")

    @Test fun oldProcessReconcilesBeforeDispatchAndRepeatedWakeDoesNotPauseAgain() {
        val store = InMemoryAgentWorkspaceStore(listOf(workspace()))
        val state = InMemoryAgentSessionStore().apply { save(session()) }
        var dispatched = 0
        val sequence = AgentStartupRecoverySequence(
            reconcile = { recover(store, mapOf("task" to state)) },
            dispatch = {
                assertEquals(AgentPhase.PAUSED, state.load()?.phase)
                assertNotNull(AgentLongTaskRecoveryPolicy.decide(store.find("task")!!, state.load()))
                dispatched++
            })
        sequence.run()
        val checkpoint = state.load()
        sequence.run()
        assertEquals(checkpoint, state.load())
        assertEquals(1, store.find("task")!!.eventJournal.size)
        assertEquals(2, dispatched)
    }

    @Test fun currentProcessAndActiveWorkspacesAreNotInterruptedByLateBootWork() {
        val store = InMemoryAgentWorkspaceStore(listOf(workspace("current"), workspace("active")))
        val current = InMemoryAgentSessionStore().apply { save(session("current")) }
        val active = InMemoryAgentSessionStore().apply { save(session()) }
        assertEquals(0, recover(store, mapOf("current" to current, "active" to active), setOf("active")))
        assertEquals(AgentPhase.EXECUTING, current.load()?.phase)
        assertEquals(AgentPhase.EXECUTING, active.load()?.phase)
        assertTrue(store.list().all { it.eventJournal.isEmpty() })
    }

    @Test fun failedReconciliationPreventsDispatchAndNextWakeRetries() {
        var writes = 0
        var dispatches = 0
        val sequence = AgentStartupRecoverySequence(
            reconcile = { if (++writes == 1) error("Storage unavailable") },
            dispatch = { dispatches++ })
        assertThrows(IllegalStateException::class.java) { sequence.run() }
        assertEquals(0, dispatches)
        sequence.run()
        assertEquals(1, dispatches)
    }

    @Test fun terminalAndExplicitlyPausedSessionsCannotResumeFromStaleWorkspace() {
        val interrupted = AgentActionResult("agent-interrupted", false, "Previous interruption")
        listOf(AgentPhase.COMPLETED, AgentPhase.CANCELLED, AgentPhase.FAILED).forEach { phase ->
            val snapshot = session().copy(phase = phase, lastActionResult = interrupted)
            val store = InMemoryAgentWorkspaceStore(listOf(workspace()))
            val state = InMemoryAgentSessionStore().apply { save(snapshot) }
            assertEquals(0, recover(store, mapOf("task" to state)))
            assertNull(AgentLongTaskRecoveryPolicy.decide(workspace(), snapshot))
            assertEquals(snapshot, state.load())
        }
        val paused = session().copy(phase = AgentPhase.PAUSED,
            lastActionResult = AgentActionResult("agent-paused", true, "Paused by user"))
        assertFalse(AgentColdBootRecoveryPolicy.belongsToPreviousProcess(paused, "current"))
        assertNull(AgentLongTaskRecoveryPolicy.decide(workspace(), paused))
    }

    @Test fun cancellationRequestedDoesNotMutateSession() {
        val state = InMemoryAgentSessionStore().apply { save(session()) }
        val store = InMemoryAgentWorkspaceStore(listOf(workspace().copy(cancellationRequested = true)))
        assertEquals(0, recover(store, mapOf("task" to state)))
        assertEquals(AgentPhase.EXECUTING, state.load()?.phase)
    }

    @Test fun concreteIntegrityErrorSurvivesStartupReconciliation() {
        val error = AgentActionResult("active-plan-recovery", false, "Missing encrypted plan page",
            mapOf("active_plan_recovery_error" to "true"))
        val state = session().copy(currentPlan = null, phase = AgentPhase.PAUSED, lastActionResult = error)
        assertEquals(error, AgentColdBootRecoveryPolicy.pauseSession(state, "current", 2L, "Restart").lastActionResult)
    }

    @Test fun distinctWorkspacesWithTheSameJavaHashHaveIndependentDurableWork() {
        assertEquals("Aa".hashCode(), "BB".hashCode())
        assertNotEquals(AgentLongTaskRecoveryScheduler.uniqueWorkName("Aa"),
            AgentLongTaskRecoveryScheduler.uniqueWorkName("BB"))
        assertEquals(AgentLongTaskRecoveryScheduler.uniqueWorkName("Aa"),
            AgentLongTaskRecoveryScheduler.uniqueWorkName("Aa"))
    }
}

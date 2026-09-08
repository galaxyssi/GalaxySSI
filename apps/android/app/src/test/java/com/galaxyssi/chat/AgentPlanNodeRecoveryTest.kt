package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class AgentPlanNodeRecoveryTest {
    private val screen = ScreenContext(foregroundApp = "", pageTitle = "")
    private val first = action("first")
    private val second = action("second")
    private val plan = AgentPlan("Test goal", screen, emptyList(), listOf(first, second), planId = "plan")
        .addCheckpoint(AgentExecutionContinuity.checkpointBefore(first, screen, 1))
        .addCheckpoint(AgentExecutionContinuity.checkpointBefore(second, screen, 1))

    @Test fun `returned sibling remains observable while unknown sibling is interrupted`() {
        val store = MemoryJournal()
        val key = key(first)
        store.record(key, AgentPlanNodeObservation(result(first), false))
        val restored = AgentPlanNodeRecovery.restore(session(), store).currentPlan!!.recoverInterruptedExecution()
        assertEquals(AGENT_NODE_OBSERVATION_PENDING, restored.actions[0].evidence)
        assertEquals(AgentActionStatus.RUNNING, restored.actions[0].status)
        assertEquals(AGENT_INTERRUPTED_EXECUTION_EVIDENCE, restored.actions[1].evidence)
        assertEquals(AgentActionStatus.FAILED, restored.actions[1].status)
    }

    @Test fun `verified node still resumes normal finalization instead of completing entire goal`() {
        val store = MemoryJournal()
        store.record(key(first), AgentPlanNodeObservation(result(first), true, "observed"))
        val restored = AgentPlanNodeRecovery.restore(session(), store)
        assertEquals(AgentPhase.EXECUTING, restored.phase)
        assertEquals(AGENT_NODE_OBSERVATION_PENDING, restored.currentPlan!!.actions[0].evidence)
    }

    @Test fun `all parallel results survive independently of lastActionResult`() {
        val store = MemoryJournal()
        plan.actions.forEach { store.record(key(it), AgentPlanNodeObservation(result(it), false)) }
        val restored = AgentPlanNodeRecovery.restore(session(), store)
        assertEquals(2, restored.currentPlan!!.actions.count { it.evidence == AGENT_NODE_OBSERVATION_PENDING })
        assertNull(AgentInterruptedDispatchRecoveryPolicy.completedAction(restored.currentPlan, restored.lastActionResult))
    }

    @Test fun `result in different conversation cannot recover this node`() {
        val store = MemoryJournal()
        store.record(key(first).copy(conversationId = "another"), AgentPlanNodeObservation(result(first), true))
        assertEquals(session(), AgentPlanNodeRecovery.restore(session(), store))
    }

    @Test fun `new checkpoint does not reuse old attempt output`() {
        val store = MemoryJournal()
        store.record(key(first), AgentPlanNodeObservation(result(first), true))
        val retry = plan.addCheckpoint(AgentExecutionContinuity.checkpointBefore(first, screen, 1))
        val snapshot = session().copy(currentPlan = retry)
        assertEquals(snapshot, AgentPlanNodeRecovery.restore(snapshot, store))
    }

    @Test fun `changed node specification is not satisfied by an old output`() {
        val changed = first.copy(parameters = first.parameters + ("input_json" to "different"))
        assertNotEquals(key(first), AgentPlanNodeKey.from("session", plan, changed))
    }

    @Test fun `pending dependency edits do not invalidate unchanged running node`() {
        val revised = plan.copy(revision = 2, actions = plan.actions + action("later"))
        assertEquals(key(first), AgentPlanNodeKey.from("session", revised, first))
    }

    @Test fun `wrong action output is rejected`() {
        val store = MemoryJournal()
        store.record(key(first), AgentPlanNodeObservation(result(second), true))
        assertThrows(IllegalArgumentException::class.java) { AgentPlanNodeRecovery.restore(session(), store) }
    }

    @Test fun `corrupt observation pauses with real failure without crashing startup`() {
        val store = MemoryJournal()
        store.record(key(first), AgentPlanNodeObservation(result(second), true))
        val restored = AgentPlanNodeRecovery.restoreOrReport(session(), store)
        assertEquals(AgentPhase.PAUSED, restored.phase)
        assertTrue(restored.lastActionResult!!.message.contains("another node"))
        assertEquals("true", restored.lastActionResult!!.metadata["plan_node_recovery_error"])
        val paused = AgentColdBootRecoveryPolicy.pauseSession(restored, "new", 10, "Restarted")
        assertEquals(restored.lastActionResult, paused.lastActionResult)
    }

    @Test fun `previously pending but corrupt observation is not scheduled for another failing replay`() {
        val pending = session().copy(currentPlan = plan.copy(actions = listOf(
            first.copy(evidence = AGENT_NODE_OBSERVATION_PENDING), second)))
        val store = MemoryJournal()
        store.record(key(first), AgentPlanNodeObservation(result(second), true))
        val restored = AgentPlanNodeRecovery.restoreOrReport(pending, store)
        assertEquals(AgentActionStatus.FAILED, restored.currentPlan!!.actions.first().status)
        assertEquals(AGENT_INTERRUPTED_EXECUTION_EVIDENCE, restored.currentPlan!!.actions.first().evidence)
    }

    @Test fun `cancelled and completed sessions are never resurrected`() {
        val store = MemoryJournal()
        store.record(key(first), AgentPlanNodeObservation(result(first), true))
        listOf(AgentPhase.CANCELLED, AgentPhase.COMPLETED).forEach { phase ->
            val snapshot = session().copy(phase = phase)
            assertEquals(snapshot, AgentPlanNodeRecovery.restore(snapshot, store))
        }
    }

    @Test fun `failed verified observation preserves actual failure`() {
        val failure = AgentPlanNodeObservation(result(first).copy(success = false, message = "Disk full"), true, "disk")
        val restored = AgentPlanNodeRecovery.applyVerified(plan, first, failure)
        assertEquals(AgentActionStatus.FAILED, restored.actions.first().status)
        assertEquals("Disk full", restored.actions.first().result)
        assertFalse(restored.verificationResults.single().success)
    }

    @Test fun `accepted asynchronous dispatch stays waiting rather than completed`() {
        val queued = AgentPlanNodeObservation(result(first).copy(metadata = mapOf("awaiting_response" to "true")), true)
        assertEquals(AgentActionStatus.WAITING_RESPONSE,
            AgentPlanNodeRecovery.applyVerified(plan, first, queued).actions.first().status)
    }

    @Test fun `raw return cannot be used as verification`() {
        assertThrows(IllegalArgumentException::class.java) {
            AgentPlanNodeRecovery.applyVerified(plan, first, AgentPlanNodeObservation(result(first), false))
        }
    }

    @Test fun `cold boot keeps durable pending observations instead of replacing them with interruption failures`() {
        val store = MemoryJournal()
        store.record(key(first), AgentPlanNodeObservation(result(first), false))
        val restored = AgentPlanNodeRecovery.restore(session(), store)
        val paused = AgentColdBootRecoveryPolicy.pauseSession(restored, "new", 10, "Restarted")
        assertEquals(AgentPhase.PAUSED, paused.phase)
        assertEquals(AGENT_NODE_OBSERVATION_PENDING, paused.currentPlan!!.actions.first().evidence)
    }

    private fun action(id: String) = AgentAction(id, AgentActionKind.CALL_NATIVE_TOOL, "test",
        AgentRisk.LOW, AgentActionStatus.RUNNING, "Test action", mapOf(
            INTERNAL_CONVERSATION_ID to "conversation", INTERNAL_TURN_ID to "turn"))
    private fun key(action: AgentAction) = requireNotNull(AgentPlanNodeKey.from("session", plan, action))
    private fun result(action: AgentAction) = AgentActionResult(action.id, true, "Result ${action.id}")
    private fun session() = AgentSessionSnapshot("session", AgentPhase.EXECUTING, plan.goal,
        screen, plan, emptyList(), null, updatedAtMillis = 1)

    private class MemoryJournal : AgentPlanNodeJournal {
        val entries = mutableMapOf<AgentPlanNodeKey, AgentPlanNodeObservation>()
        override fun start(key: AgentPlanNodeKey) = Unit
        override fun record(key: AgentPlanNodeKey, observation: AgentPlanNodeObservation) { entries[key] = observation }
        override fun read(key: AgentPlanNodeKey) = entries[key]
    }
}

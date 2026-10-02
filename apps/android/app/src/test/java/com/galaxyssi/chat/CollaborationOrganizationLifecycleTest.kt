package com.galaxyssi.chat

import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test

class CollaborationOrganizationLifecycleTest {
    private fun record(): AgentTeamExecutionRecord {
        val initial = CollaborationGoalLoop.initial(listOf("lead", "author").map { id ->
            AgentTeamMember("fixture", if (id == "lead") AgentDeliveryMode.RESPOND else AgentDeliveryMode.OBSERVE,
                instanceId = id, context = mapOf("collaboration_group_id" to "group"))
        }, "Original goal")
        val worker = initial[1].copy(instanceId = "worker", deliveryMode = AgentDeliveryMode.OBSERVE,
            objective = "Read the fixture", context = initial[1].context + mapOf(CollaborationGoalLoop.ROSTER to "false",
                CollaborationGoalLoop.WORK_ID to "read", CollaborationResearchWorkflow.STAGE to "EXECUTE"))
        val final = initial[0].copy(instanceId = "final", dependsOnAgentIds = setOf("worker"),
            context = initial[0].context + (CollaborationGoalLoop.ROSTER to "false"))
        return AgentTeamExecutionRecord(AgentTeamDefinition("team", "fixture",
            initial.map { it.copy(deliveryMode = AgentDeliveryMode.IGNORE) } + worker + final, primaryInstanceId = "final"),
            AgentRunRequest("group", "turn", "task", runId = "run", goal = "Original goal"))
    }

    private fun result(sequence: Long, id: String = "worker", status: AgentSubagentStatus = AgentSubagentStatus.SUCCEEDED) =
        AgentSubagentEvent(sequence, "run", id, AgentSubagentEventKinds.CHILD_SUCCEEDED, childStatus = status,
            result = AgentSubagentChildResult("run", id, "run", 1, status, output = "Saved fixture output",
                provenance = AgentSubagentProvenance("agent-team", "team", "run", mapOf("instance_id" to id, "agent_id" to "fixture"))))

    private fun terminal(sequence: Long = 4, status: AgentSubagentRunStatus = AgentSubagentRunStatus.SUCCEEDED) =
        AgentSubagentEvent(sequence, "run", kind = AgentSubagentEventKinds.SUPERVISOR_SUCCEEDED, runStatus = status)

    @Test fun newerRunningKeepsGoalHistorySnapshotAndRecoveryInAgreement(): Unit = runBlocking {
        val running = AgentSubagentEvent(2, "run", "worker", AgentSubagentEventKinds.CHILD_RUNNING,
            childStatus = AgentSubagentStatus.RUNNING)
        val input = record().copy(events = listOf(result(1), running, result(3, "final"), terminal()))
        for (events in listOf(input.events, input.events.reversed())) {
            val current = input.copy(events = events)
            assertTrue(CollaborationGoalLoop.finishedWork(current).isEmpty())
            assertTrue(CollaborationGoalLoop.finishedAuthors(current).isEmpty())
            assertFalse(CollaborationTeamOrganizationHistory.capture(current).checkpoint.settled)
            assertNull(CollaborationGoalLoop.advance(current, "final", Long.MAX_VALUE, true))
        }
        val store = InMemoryAgentTeamExecutionStore()
        store.create(input.definition, input.request)
        input.events.forEach { store.append(it) }
        assertEquals(AgentTeamExecutionState.INTERRUPTED, store.snapshot("run")!!.state)
        assertEquals(AgentSubagentStatus.RUNNING, store.snapshot("run")!!.members.single { it.memberId == "worker" }.status)
        assertNull(store.resumeCheckpoint("run"))
    }

    @Test fun foreignSuccessDoesNotHideCurrentLocalFailure(): Unit = runBlocking {
        val foreign = result(1).let { event -> event.copy(result = event.result!!.copy(
            provenance = event.result.provenance.copy(sourceId = "foreign-team"))) }
        val input = record().copy(events = listOf(foreign, result(2, status = AgentSubagentStatus.FAILED), result(3, "final"), terminal()))
        val projection = CollaborationTeamOrganizationProjection.current(input)
        assertTrue(projection.safeToApply && projection.settled)
        assertEquals(AgentSubagentStatus.FAILED, projection.verifiedResults.getValue("worker").status)
        assertTrue(CollaborationGoalLoop.finishedWork(input).isEmpty())
        val history = CollaborationTeamOrganizationHistory.capture(input)
        assertEquals(CollaborationTeamOrganization.Outcome.FAILED, history.checkpoint.observations.single().outcome)
        val store = InMemoryAgentTeamExecutionStore()
        store.create(input.definition, input.request)
        input.events.forEach { store.append(it) }
        assertEquals(AgentSubagentStatus.FAILED, store.resumeCheckpoint("run")!!.completed.getValue("worker").status)
    }

    @Test fun conflictingResultsNeverAdvanceOrResumeAsArbitrarySuccess(): Unit = runBlocking {
        val input = record().copy(events = listOf(result(1), result(2, status = AgentSubagentStatus.FAILED), result(3, "final"), terminal()))
        assertFalse(CollaborationTeamOrganizationProjection.current(input).safeToApply)
        assertTrue(runCatching { CollaborationGoalLoop.finishedWork(input) }.isFailure)
        assertNull(CollaborationGoalLoop.advance(input, "final", Long.MAX_VALUE, true))
        val store = InMemoryAgentTeamExecutionStore()
        store.create(input.definition, input.request)
        input.events.forEach { store.append(it) }
        assertEquals(AgentTeamExecutionState.INTERRUPTED, store.snapshot("run")!!.state)
        assertNull(store.resumeCheckpoint("run"))
    }

    @Test fun laterCancellationWinsRegardlessOfStoredListOrder() {
        val input = record().copy(events = listOf(result(1), result(2, "final"), terminal(20, AgentSubagentRunStatus.CANCELLED), terminal(3)))
        assertEquals(AgentSubagentRunStatus.CANCELLED, CollaborationTeamOrganizationProjection.current(input).terminal)
        assertNull(CollaborationGoalLoop.advance(input, "final", Long.MAX_VALUE, true))
        assertFalse(CollaborationTeamOrganizationHistory.capture(input).checkpoint.settled)
    }

    @Test fun traceTailCompactionCannotEraseConflictingOriginalResults(): Unit = runBlocking {
        val input = record()
        val store = InMemoryAgentTeamExecutionStore()
        store.create(input.definition, input.request)
        store.append(result(1))
        store.append(result(2, status = AgentSubagentStatus.FAILED))
        repeat(550) { index -> store.append(AgentSubagentEvent(index + 3L, "run", "final",
            AgentSubagentEventKinds.CHILD_QUEUED, childStatus = AgentSubagentStatus.QUEUED)) }
        val saved = store.records().single()
        assertEquals(2, saved.events.count { it.result != null })
        assertEquals(setOf("worker"), CollaborationTeamOrganizationProjection.current(saved).conflicts)
        assertNull(store.resumeCheckpoint("run"))
    }
}

package com.galaxyssi.chat

import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CollaborationCandidateRuntimeIntegrationTest {
    private class Rows : CollaborationWorkspaceRows {
        val data = sortedMapOf<String, String>()
        override fun read(key: String) = data[key]
        override fun commit(values: Map<String, String>) { data.putAll(values) }
        override fun page(prefix: String, after: String, limit: Int) = data.keys.filter { it.startsWith(prefix) && it > after }.take(limit)
    }

    @Test fun twoRoutesValidateRepairAndRecheckBeforeUnrelatedWorkFinishes() = runBlocking {
        withTimeout(15_000) {
            val fixture = CandidateRuntimeFixture(Rows(), Rows())
            val record = fixture.record()
            val store = InMemoryAgentTeamExecutionStore().apply { candidateWorkspace = { fixture.workspace } }
            val slowStarted = CompletableDeferred<Unit>()
            val releaseSlow = CompletableDeferred<Unit>()
            val settled = CompletableDeferred<Unit>()
            val enrolled = AtomicBoolean()
            val operations = CopyOnWriteArrayList<String>()
            val calls = CopyOnWriteArrayList<String>()
            AgentTeamExecutionRuntime(store, AgentSubagentLimits(maxConcurrency = 3), onSnapshot = {
                val saved = store.records().singleOrNull()
                val state = saved?.request?.context?.get(CollaborationCandidateEvolution.STATE)?.toString()
                if (state != null && CollaborationCandidateVerificationState.read(state).length() == 2 &&
                    !CollaborationCandidateEvolution.pending(state)) settled.complete(Unit)
            }).use { runtime ->
                val handle = runtime.start(record.definition, record.request) { execution ->
                    val member = execution.member
                    calls += member.memberId
                    when {
                        member.memberId == "producer" -> { slowStarted.await(); AgentSubagentOutput(fixture.produce()) }
                        member.memberId == "slow" -> { slowStarted.complete(Unit); releaseSlow.await(); AgentSubagentOutput("unrelated-result") }
                        CollaborationLiveGraph.planner(member) -> AgentSubagentOutput(fixture.expansion(!enrolled.getAndSet(true)))
                        member.context.containsKey(CollaborationCandidateEvolution.TASK) -> {
                            assertFalse("Candidate work must not wait for the slow member", releaseSlow.isCompleted)
                            val task = JSONObject(member.context.getValue(CollaborationCandidateEvolution.TASK))
                            val operation = task.getString("operation")
                            val revision = task.getJSONObject("target").getInt("revision")
                            val reviewer = task.getString("member")
                            operations += "$reviewer:$operation:$revision"
                            val persisted = store.records().single()
                            assertTrue(persisted.definition.members.contains(member))
                            assertTrue(persisted.definition.members.single { it.memberId == "final" }.dependsOnAgentIds.contains(member.memberId))
                            val phase = if (reviewer == "reviewer-a" && revision == 1) "refuted" else "supported"
                            AgentSubagentOutput(fixture.execute(member, phase))
                        }
                        member.memberId == "final" -> {
                            assertTrue(settled.isCompleted && releaseSlow.isCompleted)
                            AgentSubagentOutput(fixture.assessment())
                        }
                        else -> error("Unexpected fixture dispatch")
                    }
                }
                try {
                    settled.await()
                    assertFalse(calls.contains("final"))
                    assertEquals(setOf("reviewer-a:review:1", "reviewer-b:review:1", "editor:revise:1", "reviewer-a:review:2"), operations.toSet())
                    releaseSlow.complete(Unit)
                    assertEquals(AgentSubagentRunStatus.SUCCEEDED, handle.await().subagentResult.status)
                    assertEquals(calls.size, calls.distinct().size)
                    val saved = store.records().single()
                    val a = fixture.targets.getValue("a")
                    assertEquals("Full original a", fixture.workspace.read(fixture.access.copy(round = 5), a.getString("object_id"), 1)!!
                        .getJSONObject("body").getString("content"))
                    assertNotNull(fixture.workspace.read(fixture.access.copy(round = 5), a.getString("object_id"), 2))
                    val planners = saved.definition.members.filter(CollaborationLiveGraph::planner)
                    val intermediates = saved.definition.members.filter { it.context.containsKey(CollaborationCandidateEvolution.TASK) }
                        .filter { JSONObject(it.context.getValue(CollaborationCandidateEvolution.TASK)).let { task ->
                            task.getString("member") == "editor" || task.getString("member") == "reviewer-a" && task.getJSONObject("target").getInt("revision") == 1 } }
                    assertTrue(planners.none { planner -> intermediates.any { planner.context[CollaborationLiveGraph.SOURCES].orEmpty().contains(it.memberId) } })
                    assertEquals("continue", store.snapshot(record.request.runId)?.goalDisposition)
                } finally { releaseSlow.complete(Unit); handle.cancel() }
            }
        }
    }

    @Test fun durablePauseAndStopRetainEnrollmentWithoutAppendingDispatches() = runBlocking {
        for (control in listOf(AgentTeamUserControl.PAUSE, AgentTeamUserControl.STOP)) {
            val fixture = CandidateRuntimeFixture(Rows(), Rows())
            val record = fixture.record()
            var currentControl = control
            val store = InMemoryAgentTeamExecutionStore().apply {
                candidateWorkspace = { fixture.workspace }; candidateControl = { currentControl }
            }
            store.create(record.definition, record.request)
            complete(store, "producer", fixture.produce(), 1)
            val first = store.expandResearchGraph(record.request.runId, "final", setOf("producer"), 2)!!
            val planner = first.definition.members.single(CollaborationLiveGraph::planner)
            complete(store, planner.memberId, fixture.expansion(true), 2)
            val completed = setOf("producer", planner.memberId)
            val held = store.expandResearchGraph(record.request.runId, "final", completed, 3)!!
            assertTrue(held.definition.members.none { it.context.containsKey(CollaborationCandidateEvolution.TASK) })
            assertTrue(CollaborationCandidateEvolution.pending(held.request.context[CollaborationCandidateEvolution.STATE].toString()))
            currentControl = AgentTeamUserControl.RUN
            val resumed = store.expandResearchGraph(record.request.runId, "final", completed, 4, candidateAdmission = 1)!!
            assertEquals(1, resumed.definition.members.count { it.context.containsKey(CollaborationCandidateEvolution.TASK) })
            val admitted = store.expandResearchGraph(record.request.runId, "final", completed, 5, candidateAdmission = 1)!!
            assertEquals(2, admitted.definition.members.count { it.context.containsKey(CollaborationCandidateEvolution.TASK) })
            assertEquals(admitted.definition, store.expandResearchGraph(record.request.runId, "final", completed, 6)!!.definition)
        }
    }

    @Test fun missingWorkspaceRetainsExactRequestsUntilAvailable() = runBlocking {
        val fixture = CandidateRuntimeFixture(Rows(), Rows())
        val record = fixture.record()
        val store = InMemoryAgentTeamExecutionStore()
        store.candidateWorkspace = { error("Transient workspace initialization failure") }
        store.create(record.definition, record.request)
        complete(store, "producer", fixture.produce(), 1)
        val first = store.expandResearchGraph(record.request.runId, "final", setOf("producer"), 2)!!
        val planner = first.definition.members.single(CollaborationLiveGraph::planner)
        complete(store, planner.memberId, fixture.expansion(true), 2)
        val completed = setOf("producer", planner.memberId)
        val held = store.expandResearchGraph(record.request.runId, "final", completed, 3)!!
        assertEquals(2, CollaborationCandidateVerificationState.checkpoint(held.request.context[CollaborationCandidateEvolution.STATE].toString()).pendingRequests.length())
        store.candidateWorkspace = { fixture.workspace }
        val resumed = store.expandResearchGraph(record.request.runId, "final", completed, 4)!!
        assertEquals(2, resumed.definition.members.count { it.context.containsKey(CollaborationCandidateEvolution.TASK) })
        val codec = Class.forName("com.galaxyssi.chat.AgentTeamExecutionCodec")
        val instance = codec.getDeclaredField("INSTANCE").apply { isAccessible = true }.get(null)
        val encoded = requireNotNull(codec.getDeclaredMethod("encode", List::class.java).apply { isAccessible = true }
            .invoke(instance, store.records())).toString()
        @Suppress("UNCHECKED_CAST")
        val decoded = (codec.getDeclaredMethod("decode", String::class.java).apply { isAccessible = true }
            .invoke(instance, encoded) as List<AgentTeamExecutionRecord>).single()
        assertEquals(store.records().single(), decoded)
        val reopened = InMemoryAgentTeamExecutionStore().apply { candidateWorkspace = { fixture.workspace } }
        reopened.create(decoded.definition, decoded.request)
        decoded.events.forEach { reopened.append(it) }
        assertEquals(resumed.definition, reopened.expandResearchGraph(record.request.runId, "final", completed, 5)!!.definition)
        assertTrue(decoded.definition.members.filter { it.context.containsKey(CollaborationCandidateEvolution.TASK) }
            .all { JSONObject(it.context.getValue(CollaborationCandidateEvolution.TASK)).getJSONObject("target").getInt("revision") == 1 })
    }

    @Test fun ordinaryResearchDoesNotOpenTheCandidateDatabase() {
        val fixture = CandidateRuntimeFixture(Rows(), Rows())
        val record = fixture.record()
        assertEquals(record, CollaborationLiveGraph.update(record, emptySet(), 1,
            candidateWorkspace = { error("No candidate enrollment or pending checkpoint") }))
    }

    private suspend fun complete(store: AgentTeamExecutionStore, id: String, output: String, sequence: Long) {
        store.append(AgentSubagentEvent(sequence, "candidate-run", id, AgentSubagentEventKinds.CHILD_SUCCEEDED,
            childStatus = AgentSubagentStatus.SUCCEEDED, result = AgentSubagentChildResult("candidate-run", id, "candidate-run", 1,
                AgentSubagentStatus.SUCCEEDED, output)))
    }
}

package com.galaxyssi.chat

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CollaborationWorkGraphTest {
    private fun work(id: String, member: String = "person-1", vararg dependencies: String) = JSONObject()
        .put("id", id).put("member", member).put("stage", "EXECUTE").put("assignment", "Produce $id")
        .put("depends_on", JSONArray(dependencies.toList()))
    private fun assessment(jobs: List<JSONObject>) = JSONObject().put("format", CollaborationGoalLoop.FORMAT)
        .put("summary", "Improve and independently check the shared artifact").put("decision", "continue")
        .put("criteria", JSONArray().put(JSONObject().put("id", "c").put("requirement", "Verified artifact")
            .put("status", "open").put("evidence", JSONArray())))
        .put("work", JSONArray(jobs)).put("blockers", JSONArray())
    private fun team(): AgentTeamDefinition {
        val people = (0..3).map { AgentTeamMember("provider", instanceId = "person-$it",
            deliveryMode = if (it == 0) AgentDeliveryMode.RESPOND else AgentDeliveryMode.OBSERVE,
            context = mapOf("collaboration_group_id" to "group")) }
        return AgentTeamDefinition("team", "provider", CollaborationGoalLoop.initial(people, "Research"), primaryInstanceId = "person-0")
    }
    private fun request() = AgentRunRequest("group", "turn", "task", runId = "run", goal = "Research")

    @Test fun rejectsCyclesUnknownDependenciesDuplicateIdsAndSelfReview() {
        assertTrue(CollaborationWorkGraph.compile(listOf(work("a", "person-1", "b"), work("b", "person-2", "a")), emptySet()).error.isNotBlank())
        assertTrue(CollaborationWorkGraph.compile(listOf(work("a", "person-1", "missing")), emptySet()).error.isNotBlank())
        assertTrue(CollaborationWorkGraph.compile(listOf(work("a"), work("a")), emptySet()).error.isNotBlank())
        assertTrue(CollaborationWorkGraph.compile(listOf(work("a"), work("review", "person-1", "a").put("independent_review", true)), emptySet()).error.isNotBlank())
        assertTrue(CollaborationWorkGraph.compile(listOf(work("a", "person-1", "a")), emptySet()).error.isNotBlank())
    }

    @Test fun completedDependenciesAreNotScheduledAgain() {
        val review = work("review", "person-2", "done")
        val plan = CollaborationWorkGraph.compile(listOf(review), setOf("done"))
        assertEquals("", plan.error)
        assertEquals(1, plan.work.size)
        assertEquals("[\"done\"]", CollaborationWorkGraph.completedDependencies(review, setOf("done")))
    }

    @Test fun acceptsLargeAcyclicGraphWithoutRecursiveStackOrStepCeiling() {
        val items = (0..2048).map { index -> if (index == 0) work("item-0") else work("item-$index", "person-1", "item-${index - 1}") }
        val plan = CollaborationWorkGraph.compile(items, emptySet())
        assertEquals("", plan.error)
        assertEquals(2049, plan.work.size)
    }

    @Test fun independentReviewUsesSavedAuthorRatherThanNewModelAttribution() {
        val review = work("review", "person-2", "done").put("independent_review", true)
        val authors = mapOf("done" to "person-1")
        assertEquals("", CollaborationWorkGraph.compile(listOf(review), setOf("done"), authors).error)
        val selfReview = work("review", "person-1", "done").put("independent_review", true)
        assertTrue(CollaborationWorkGraph.compile(listOf(work("done", "forged-author"), selfReview), setOf("done"), authors).error.isNotBlank())
        assertTrue(CollaborationWorkGraph.compile(listOf(review), setOf("done")).error.isNotBlank())
    }

    @Test fun reviewerStartsBeforeUnrelatedSlowMemberFinishes() = runBlocking {
        withTimeout(10_000) {
            val jobs = listOf(work("producer"), work("slow", "person-3"),
                work("review", "person-2", "producer").put("stage", "VERIFY").put("independent_review", true))
            val slowStarted = CompletableDeferred<Unit>()
            val reviewStarted = CompletableDeferred<Unit>()
            val releaseSlow = CompletableDeferred<Unit>()
            var calls = 0
            val store = InMemoryAgentTeamExecutionStore()
            AgentTeamExecutionRuntime(store, AgentSubagentLimits(maxConcurrency = 2)).use { runtime ->
                val worker = AgentTeamMemberWorker { execution ->
                    if (execution.member.deliveryMode == AgentDeliveryMode.RESPOND) {
                        calls++
                        AgentSubagentOutput(assessment(if (calls == 1) jobs else emptyList()).toString())
                    } else {
                        when (execution.member.context[CollaborationGoalLoop.WORK_ID]) {
                            "slow" -> { slowStarted.complete(Unit); releaseSlow.await() }
                            "producer" -> slowStarted.await()
                            "review" -> {
                                assertEquals(1, execution.handoff.dependencies.size)
                                assertTrue(execution.handoff.dependencies.single().output.contains("producer"))
                                assertFalse(releaseSlow.isCompleted)
                                reviewStarted.complete(Unit)
                            }
                        }
                        AgentSubagentOutput("Result of ${execution.member.context[CollaborationGoalLoop.WORK_ID]}")
                    }
                }
                runtime.start(team(), request(), worker).await()
                assertTrue(store.advanceGoal("run", "person-0", System.currentTimeMillis()))
                val handle = runtime.resume(requireNotNull(store.resumeCheckpoint("run")), worker)
                reviewStarted.await()
                releaseSlow.complete(Unit)
                handle.await()
                assertEquals(2, calls)
            }
        }
    }

    @Test fun failedProducerBlocksSuccessDependentButDiagnosticStillExecutes() = runBlocking {
        val jobs = listOf(work("producer"), work("review", "person-2", "producer"),
            work("diagnose", "person-3", "producer").put("dependency_policy", "terminal"))
        val ran = mutableSetOf<String>()
        val store = InMemoryAgentTeamExecutionStore()
        AgentTeamExecutionRuntime(store).use { runtime ->
            val worker = AgentTeamMemberWorker { execution ->
                if (execution.member.deliveryMode == AgentDeliveryMode.RESPOND) AgentSubagentOutput(assessment(jobs).toString())
                else {
                    val id = execution.member.context.getValue(CollaborationGoalLoop.WORK_ID)
                    synchronized(ran) { ran += id }
                    check(id != "producer") { "Producer failed" }
                    assertEquals(AgentSubagentStatus.FAILED, execution.handoff.dependencies.single().status)
                    AgentSubagentOutput("Failure diagnosed")
                }
            }
            runtime.start(team(), request(), worker).await()
            store.advanceGoal("run", "person-0", System.currentTimeMillis())
            val result = runtime.resume(requireNotNull(store.resumeCheckpoint("run")), worker).await()
            assertEquals(setOf("producer", "diagnose"), ran)
            assertTrue(result.snapshot.members.any { it.status == AgentSubagentStatus.SKIPPED })
        }
    }

    @Test fun invalidGraphReturnsPlannerFeedbackWithoutDispatchingPartialWork() = runBlocking {
        val store = InMemoryAgentTeamExecutionStore()
        AgentTeamExecutionRuntime(store).use { runtime ->
            runtime.start(team(), request()) { AgentSubagentOutput(assessment(listOf(work("safe"), work("bad", "person-2", "missing"))).toString()) }.await()
            store.advanceGoal("run", "person-0", System.currentTimeMillis())
            val checkpoint = requireNotNull(store.resumeCheckpoint("run"))
            assertEquals(1, checkpoint.definition.members.count { it.deliveryMode != AgentDeliveryMode.IGNORE })
            assertTrue(checkpoint.request.context[CollaborationWorkGraph.FEEDBACK].toString().contains("dependency"))
        }
    }
}

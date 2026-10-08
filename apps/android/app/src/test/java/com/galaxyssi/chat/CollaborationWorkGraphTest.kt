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

    @Test fun reviewTargetsSeparateTheSubjectFromReviewersOwnTestData() {
        val jobs = listOf(work("model", "person-1"), work("probes", "person-2"),
            work("check", "person-2", "model", "probes").put("independent_review", true)
                .put("review_targets", JSONArray().put("model")))
        val plan = CollaborationWorkGraph.compile(jobs, emptySet())
        assertEquals("", plan.error)
        assertEquals(setOf("model", "probes"), CollaborationWorkGraph.dependencies(plan.work.last()))
        assertEquals(setOf("model"), CollaborationReviewTargets.read(plan.work.last()))
        assertEquals(setOf("model"), CollaborationReviewTargets.read(CollaborationReviewTargets.restore(
            JSONObject(jobs.last().toString()).apply { remove("review_targets") }, CollaborationReviewTargets.context(jobs.last()))))
        val baseline = JSONObject(jobs.last().toString()).apply { remove("review_targets") }
        val failure = CollaborationWorkGraph.compile(jobs.dropLast(1) + baseline, emptySet()).error
        assertTrue(failure.contains("check")); assertTrue(failure.contains("probes"))
        assertTrue(failure.contains("review_targets")); assertTrue(failure.contains("author=person-2"))
        assertNotEquals(CollaborationTeamOrganization.signature(baseline), CollaborationTeamOrganization.signature(jobs.last()))
    }

    @Test fun explicitTargetsCannotBypassKnownAuthorsOrDependencyAccess() {
        val review = work("check", "person-2", "model", "probes").put("independent_review", true)
            .put("review_targets", JSONArray().put("model"))
        val finished = setOf("model", "probes")
        assertEquals("", CollaborationWorkGraph.compile(listOf(review), finished,
            mapOf("model" to "person-1", "probes" to "person-2")).error)
        for (authors in listOf(emptyMap(), mapOf("model" to "person-2", "probes" to "person-1"))) {
            assertTrue(CollaborationWorkGraph.compile(listOf(work("model", "forged-author"), review), finished, authors).error.isNotBlank())
        }
        val bad: List<Any> = listOf(JSONArray(), JSONArray().put("unknown"), JSONArray().put("model").put("model"),
            JSONArray().put(12), JSONArray().put(""), "model", JSONObject.NULL)
        for (targets in bad) {
            val changed = JSONObject(review.toString()).put("review_targets", targets)
            assertTrue(targets.toString(), CollaborationWorkGraph.compile(listOf(work("model"), work("probes", "person-2"), changed), emptySet()).error.isNotBlank())
        }
        assertTrue(CollaborationWorkGraph.compile(listOf(JSONObject(review.toString()).put("independent_review", false)), finished).error.isNotBlank())
        assertTrue(CollaborationWorkGraph.compile(listOf(JSONObject(review.toString()).put("independent_review", "true")), finished).error.isNotBlank())
    }

    @Test fun goalContinuationRetainsBothInputsAndTargetAcrossCheckpoint() = runBlocking {
        val jobs = listOf(work("model", "person-1"), work("probes", "person-2"),
            work("check", "person-2", "model", "probes").put("independent_review", true)
                .put("review_targets", JSONArray().put("model"))
                .put(CollaborationDataDependencies.FIELD, CollaborationDataDependencies.array(mapOf("model" to "Frozen candidate"))))
        val store = InMemoryAgentTeamExecutionStore()
        AgentTeamExecutionRuntime(store).use { runtime ->
            runtime.start(team(), request()) { AgentSubagentOutput(assessment(jobs).toString()) }.await()
            assertTrue(store.advanceGoal("run", "person-0", System.currentTimeMillis()))
            val checkpoint = requireNotNull(store.resumeCheckpoint("run"))
            val check = checkpoint.definition.members.single { it.context[CollaborationGoalLoop.WORK_ID] == "check" }
            assertEquals("[\"model\"]", check.context[CollaborationReviewTargets.CONTEXT])
            assertTrue(isPersistedAgentTeamContextKey(CollaborationReviewTargets.CONTEXT))
            assertTrue(isPersistedAgentTeamContextKey(CollaborationDataDependencies.CONTEXT))
            assertEquals(mapOf("model" to "Frozen candidate"), CollaborationDataDependencies.from(check))
            assertEquals(2, check.dependsOnAgentIds.size)
            var checked = false
            runtime.resume(checkpoint) { execution ->
                if (execution.member.context[CollaborationGoalLoop.WORK_ID] == "check") {
                    assertEquals(setOf("Result of model", "Result of probes"), execution.handoff.dependencies.map { it.output }.toSet())
                    checked = true
                }
                AgentSubagentOutput(if (execution.member.deliveryMode == AgentDeliveryMode.RESPOND) assessment(emptyList()).toString()
                    else "Result of ${execution.member.context[CollaborationGoalLoop.WORK_ID]}")
            }.await()
            assertTrue(checked)
        }
    }

    @Test fun completedRepairIdsAreDiagnosedInsteadOfSilentlyDiscarded() {
        val error = CollaborationWorkGraph.reusedRequestError(listOf(work("restore-report"),
            work("verify-report", "person-2", "restore-report")), setOf("restore-report", "verify-report"))
        assertTrue(error.contains("COMPLETED_DISPATCH_REUSED"))
        assertTrue(error.contains("repair_of"))
        assertTrue(error.contains("does NOT prove delivery"))
    }

    @Test fun repairUsesNewAttemptAndPreservesOriginalBusinessReference() {
        val repair = work("restore-report-repair").put("repair_of", "restore-report")
            .put("repair_reason", "Saved response has no published workspace version")
        val verify = work("verify-report-repair", "person-2", "restore-report-repair").put("independent_review", true)
        val plan = CollaborationWorkGraph.compile(listOf(repair, verify), setOf("restore-report", "verify-report"))
        assertEquals("", plan.error)
        assertEquals(2, plan.work.size)
        assertEquals("restore-report", plan.work.first().getString("repair_of"))
        assertTrue(CollaborationWorkGraph.compile(listOf(work("repair").put("repair_of", "unknown")
            .put("repair_reason", "Missing")), setOf("done")).error.isNotBlank())
        assertTrue(CollaborationWorkGraph.compile(listOf(work("repair").put("repair_of", "done")), setOf("done")).error.isNotBlank())
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

    @Test fun incompleteDeliveryCanBeRepairedWithoutRepeatingOriginalExecution() = runBlocking {
        val store = InMemoryAgentTeamExecutionStore()
        val calls = mutableListOf<String>()
        var assessments = 0
        AgentTeamExecutionRuntime(store).use { runtime ->
            val worker = AgentTeamMemberWorker { execution ->
                if (execution.member.deliveryMode == AgentDeliveryMode.RESPOND) {
                    assessments++
                    val jobs = when (assessments) {
                        1, 2 -> listOf(work("report"))
                        3 -> {
                            assertTrue(execution.request.context[CollaborationWorkGraph.FEEDBACK].toString().contains("COMPLETED_DISPATCH_REUSED"))
                            listOf(work("report-repair").put("repair_of", "report").put("repair_reason", "Missing formal delivery"))
                        }
                        else -> emptyList()
                    }
                    AgentSubagentOutput(assessment(jobs).toString())
                } else {
                    val id = execution.member.context.getValue(CollaborationGoalLoop.WORK_ID)
                    calls += id
                    if (id == "report-repair") assertEquals("report", execution.member.context[CollaborationWorkGraph.REPAIR_OF])
                    AgentSubagentOutput("Saved partial result; not scientifically accepted")
                }
            }
            runtime.start(team(), request(), worker).await()
            var now = System.currentTimeMillis()
            repeat(3) {
                now += 3_600_000
                val primary = store.snapshot("run")!!.primaryMemberId
                assertTrue(store.advanceGoal("run", primary, now))
                runtime.resume(requireNotNull(store.resumeCheckpoint("run")), worker).await()
            }
            assertEquals(listOf("report", "report-repair"), calls)
            assertTrue(store.advanceGoal("run", store.snapshot("run")!!.primaryMemberId, now + 3_600_000))
            assertTrue(store.resumeCheckpoint("run")!!.request.context[CollaborationWorkGraph.FEEDBACK].toString().contains("NO_EXECUTABLE_WORK"))
        }
    }
}

package com.galaxyssi.chat

import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CollaborationResearchWorkflowTest {
    private fun team(researchers: Int = 3): AgentTeamDefinition {
        val people = (0..researchers).map { index -> AgentTeamMember(agentId = "codex",
            instanceId = "person-$index", role = if (index == 0) "Coordinator" else "Researcher",
            deliveryMode = if (index == 0) AgentDeliveryMode.RESPOND else AgentDeliveryMode.OBSERVE,
            context = mapOf("collaboration_group_id" to "group", "collaboration_name" to "Person $index")) }
        return AgentTeamDefinition(teamId = "research-team", primaryAgentId = "codex", primaryInstanceId = "person-0",
            members = CollaborationResearchWorkflow.expand(people, "Design a verifiable solution"))
    }
    private fun request() = AgentRunRequest("group", "turn", "task", runId = "research-run", goal = "Design a verifiable solution")
    private fun artifact(summary: String) = JSONObject().put("format", CollaborationResearchArtifact.FORMAT)
        .put("summary", summary).put("candidates", JSONArray()).put("findings", JSONArray()).put("questions", JSONArray())
    private fun work(member: String = "person-1", stage: String = "EXECUTE") = JSONObject()
        .put("member", member).put("stage", stage).put("assignment", "Produce and verify the actual artifact")
    private fun assessment(decision: String = "continue", jobs: Int = 1): JSONObject = JSONObject()
        .put("format", CollaborationGoalLoop.FORMAT).put("summary", "Evidence-backed progress")
        .put("decision", decision).put("criteria", JSONArray().put(JSONObject().put("id", "artifact")
            .put("requirement", "Verified artifact").put("status", if (decision == "achieved") "met" else "open")
            .put("evidence", JSONArray(if (decision == "achieved") listOf("tool:verified-artifact") else emptyList<String>()))))
        .put("work", JSONArray((0 until jobs).map { work().put("id", "work-$it") })).put("blockers", JSONArray())

    @Test fun initialGraphOnlyAsksCoordinatorToPlanAndRetainsAllPeople() = runBlocking {
        val definition = team(15)
        assertEquals(16, definition.members.size)
        assertEquals(1, definition.members.count { it.deliveryMode != AgentDeliveryMode.IGNORE })
        assertEquals(definition, requireNotNull(AgentTeamDispatchSpecCodec.decode(
            AgentTeamDispatchSpecCodec.encode(AgentTeamDispatchSpec(definition, "research-run")))).definition)
        val store = InMemoryAgentTeamExecutionStore()
        AgentTeamExecutionRuntime(store).use { runtime ->
            val calls = AtomicInteger()
            val result = runtime.start(definition, request()) {
                calls.incrementAndGet(); AgentSubagentOutput(assessment().toString())
            }.await()
            assertEquals(1, calls.get())
            assertEquals("continue", result.snapshot.goalDisposition)
            assertEquals(AgentTeamExecutionState.INTERRUPTED, result.snapshot.state)
            assertEquals("Evidence-backed progress", result.snapshot.finalOutput)
        }
    }

    @Test fun moreThanOneThousandBatchesKeepSameGoalAndNeverReplayCompletedWork() = runBlocking {
        val store = InMemoryAgentTeamExecutionStore()
        val completed = hashSetOf<String>()
        var assessments = 0
        val worker = AgentTeamMemberWorker { context ->
            if (context.member.deliveryMode == AgentDeliveryMode.RESPOND) {
                assessments++
                val plan = assessment(if (assessments > 1001) "achieved" else "continue", if (assessments > 1001) 0 else 1)
                if (assessments <= 1001) plan.getJSONArray("work").getJSONObject(0).put("id", "iteration-$assessments")
                AgentSubagentOutput(plan.toString())
            } else {
                assertTrue("Completed side effect must not replay", completed.add(context.request.runId))
                AgentSubagentOutput(artifact("Verified actual artifact").toString())
            }
        }
        AgentTeamExecutionRuntime(store).use { runtime ->
            var result = runtime.start(team(), request(), worker).await()
            repeat(1001) {
                assertEquals("continue", result.snapshot.goalDisposition)
                val oldPrimary = result.snapshot.primaryMemberId
                assertTrue(store.advanceGoal("research-run", oldPrimary, System.currentTimeMillis()))
                assertFalse("CAS makes duplicate scheduling harmless", store.advanceGoal("research-run", oldPrimary, System.currentTimeMillis()))
                val checkpoint = requireNotNull(store.resumeCheckpoint("research-run"))
                assertEquals(request().runId, checkpoint.request.runId)
                assertEquals(request().taskId, checkpoint.request.taskId)
                assertEquals(request().goal, checkpoint.request.goal)
                result = runtime.resume(checkpoint, worker).await()
            }
            assertEquals(1001, completed.size)
            assertEquals(1002, assessments)
            assertEquals("continue", result.snapshot.goalDisposition)
            assertEquals(AgentTeamExecutionState.INTERRUPTED, result.snapshot.state)
            assertTrue("A textual success claim must schedule acceptance repair", store.advanceGoal("research-run", result.snapshot.primaryMemberId, Long.MAX_VALUE))
        }
    }

    @Test fun moreThanSixtyFourWorkItemsStillUseBoundedLiveConcurrency() = runBlocking {
        val store = InMemoryAgentTeamExecutionStore()
        val active = AtomicInteger()
        val peak = AtomicInteger()
        var coordinatorCalls = 0
        AgentTeamExecutionRuntime(store, AgentSubagentLimits(maxConcurrency = 3)).use { runtime ->
            val worker = AgentTeamMemberWorker { context ->
                if (context.member.deliveryMode == AgentDeliveryMode.RESPOND) {
                    coordinatorCalls++
                    AgentSubagentOutput(assessment(if (coordinatorCalls == 1) "continue" else "achieved",
                        if (coordinatorCalls == 1) 80 else 0).toString())
                } else {
                    val running = active.incrementAndGet()
                    peak.updateAndGet { maxOf(it, running) }
                    delay(2); active.decrementAndGet()
                    AgentSubagentOutput(artifact("Evidence").toString())
                }
            }
            runtime.start(team(), request(), worker).await()
            assertTrue(store.advanceGoal("research-run", "person-0", System.currentTimeMillis()))
            val checkpoint = requireNotNull(store.resumeCheckpoint("research-run"))
            assertEquals(81, checkpoint.definition.members.count { it.deliveryMode != AgentDeliveryMode.IGNORE })
            val result = runtime.resume(checkpoint, worker).await()
            assertEquals("continue", result.snapshot.goalDisposition)
            assertTrue(peak.get() in 2..3)
        }
    }

    @Test fun cannotFinishWithoutEvidenceOrByDroppingOrWeakeningCriteria() {
        val prior = assessment().getJSONArray("criteria").toString()
        val done = assessment("achieved", 0)
        assertEquals("continue", CollaborationGoalLoop.disposition(done.toString(), prior))
        assertEquals("achieved", CollaborationGoalLoop.disposition(done.toString(), prior, acceptanceVerified = true))
        done.getJSONArray("criteria").getJSONObject(0).put("evidence", JSONArray())
        assertEquals("continue", CollaborationGoalLoop.disposition(done.toString(), prior))
        val changed = assessment("achieved", 0)
        changed.getJSONArray("criteria").getJSONObject(0).put("requirement", "Only write a plan")
        assertEquals("continue", CollaborationGoalLoop.disposition(changed.toString(), prior))
        changed.getJSONArray("criteria").getJSONObject(0).put("id", "different")
        assertEquals("continue", CollaborationGoalLoop.disposition(changed.toString(), prior))
    }

    @Test fun labBlockDoesNotStopExecutableComputation() {
        val blocked = assessment("blocked", 1).put("blockers", JSONArray().put(JSONObject()
            .put("kind", "resource").put("reason", "No authorized lab").put("resume_when", "Lab access granted")))
        assertEquals("continue", CollaborationGoalLoop.disposition(blocked.toString()))
        blocked.put("work", JSONArray())
        assertEquals("continue", CollaborationGoalLoop.disposition(blocked.toString()))
        val blocker = blocked.getJSONArray("blockers").getJSONObject(0)
        blocker.put("alternatives", JSONArray().put(JSONObject().put("option", "Public lab")
            .put("status", "needs_approval").put("result", "Requires account and authorized sample submission")
            .put("evidence", JSONArray().put("source:lab-access"))))
        assertEquals("blocked", CollaborationGoalLoop.disposition(blocked.toString(), "[]", setOf(CollaborationResourceRecovery.workId(blocker))))
        blocked.put("blockers", JSONArray())
        assertEquals("continue", CollaborationGoalLoop.disposition(blocked.toString()))
    }

    @Test fun blockedGoalWaitsForWakeupRatherThanFinishingOrPollingTheModel() = runBlocking {
        val store = InMemoryAgentTeamExecutionStore()
        AgentTeamExecutionRuntime(store).use { runtime ->
            val blocked = assessment("blocked", 0).put("blockers", JSONArray().put(JSONObject()
                .put("kind", "resource").put("reason", "No authorized lab").put("resume_when", "Lab access granted")
                .put("alternatives", JSONArray().put(JSONObject().put("option", "Public platform").put("status", "needs_approval")
                    .put("result", "Requires permission").put("evidence", JSONArray().put("source:access"))))))
            val worker = AgentTeamMemberWorker { AgentSubagentOutput(blocked.toString()) }
            assertEquals("continue", runtime.start(team(), request(), worker).await().snapshot.goalDisposition)
            assertTrue(store.advanceGoal("research-run", "person-0", System.currentTimeMillis()))
            val result = runtime.resume(requireNotNull(store.resumeCheckpoint("research-run")), worker).await()
            assertEquals("blocked", result.snapshot.goalDisposition)
            assertEquals(AgentTeamExecutionState.INTERRUPTED, result.snapshot.state)
            assertFalse(store.advanceGoal("research-run", result.snapshot.primaryMemberId, Long.MAX_VALUE))
            assertTrue(store.advanceGoal("research-run", result.snapshot.primaryMemberId, System.currentTimeMillis(), true))
            assertNotNull(store.resumeCheckpoint("research-run"))
        }
    }

    @Test fun temporaryNetworkOrCapacityBlockerRemainsAutomaticallyRetryable() {
        listOf("connectivity", "provider", "capacity").forEach { kind ->
            val blocked = assessment("blocked", 0).put("blockers", JSONArray().put(JSONObject()
                .put("kind", kind).put("reason", "Temporarily unavailable").put("resume_when", "Connection returns")))
            assertEquals("continue", CollaborationGoalLoop.disposition(blocked.toString()))
        }
    }

    @Test fun malformedOrPlainTextFinalIsReplannedNotAccepted() = runBlocking {
        val store = InMemoryAgentTeamExecutionStore()
        AgentTeamExecutionRuntime(store).use { runtime ->
            val result = runtime.start(team(), request()) { AgentSubagentOutput("The review is finished; design remains undone.") }.await()
            assertEquals("continue", result.snapshot.goalDisposition)
            assertTrue(store.advanceGoal("research-run", "person-0", 10_000))
            val next = requireNotNull(store.snapshot("research-run"))
            assertTrue(next.nextGoalAttemptAtMillis > 10_000)
            assertEquals(1, requireNotNull(store.resumeCheckpoint("research-run")).definition.members.count { it.deliveryMode != AgentDeliveryMode.IGNORE })
        }
    }

    @Test fun invalidAssigneeNeverDispatchesPartialWork() = runBlocking {
        val store = InMemoryAgentTeamExecutionStore()
        val plan = assessment().put("work", JSONArray().put(work()).put(work("outsider")))
        AgentTeamExecutionRuntime(store).use { runtime ->
            runtime.start(team(), request()) { AgentSubagentOutput(plan.toString()) }.await()
            assertTrue(store.advanceGoal("research-run", "person-0", 10_000))
            val checkpoint = requireNotNull(store.resumeCheckpoint("research-run"))
            assertEquals(1, checkpoint.definition.members.count { it.deliveryMode != AgentDeliveryMode.IGNORE })
        }
    }

    @Test fun duplicateCompletedWorkIsNotExecutedAgain() = runBlocking {
        val store = InMemoryAgentTeamExecutionStore()
        var executions = 0
        AgentTeamExecutionRuntime(store).use { runtime ->
            val worker = AgentTeamMemberWorker {
                if (it.member.deliveryMode == AgentDeliveryMode.RESPOND) AgentSubagentOutput(assessment().toString())
                else { executions++; AgentSubagentOutput(artifact("Executed").toString()) }
            }
            runtime.start(team(), request(), worker).await()
            store.advanceGoal("research-run", "person-0", 10_000)
            val completed = runtime.resume(requireNotNull(store.resumeCheckpoint("research-run")), worker).await()
            assertTrue(store.advanceGoal("research-run", completed.snapshot.primaryMemberId, 20_000))
            val repair = requireNotNull(store.resumeCheckpoint("research-run"))
            assertEquals(1, repair.definition.members.count { it.deliveryMode != AgentDeliveryMode.IGNORE })
            assertEquals(1, executions)
            assertTrue(repair.request.context[CollaborationGoalLoop.FINISHED_WORK].toString().contains("work-0"))
        }
    }

    @Test fun oldRoundResponseCannotAttachToNewRoundOfSameProvider() = runBlocking {
        val store = InMemoryAgentTeamExecutionStore()
        AgentTeamExecutionRuntime(store).use { runtime ->
            runtime.start(team(), request()) { AgentSubagentOutput("Malformed assessment") }.await()
            assertTrue(store.advanceGoal("research-run", "person-0", 10_000))
            val old = AgentManagedResponseRecord(ownerRunId = stableAgentTeamMemberRunId("research-run", "person-0"),
                supervisorRunId = "research-run", agentId = "codex", deliveryMode = AgentDeliveryMode.RESPOND,
                sourceMessageId = 123L, contactId = "codex", state = AgentManagedResponseState.COMPLETED,
                response = AgentConnectorResponse(123L, "codex", assessment("achieved", 0).toString()))
            assertFalse(store.applyLateResponse(old))
            assertEquals("", store.snapshot("research-run")?.finalOutput)
        }
    }

    @Test fun earlierBatchEvidenceIsAccessibleButCurrentIndependentWorkIsNot() {
        val earlier = JSONObject().put("turn_id", "turn").put("goal_round", 3L)
        assertTrue(CollaborationResearchArchive.visible(earlier, "turn", 4L))
        assertFalse(CollaborationResearchArchive.visible(earlier, "turn", 3L))
        assertFalse(CollaborationResearchArchive.visible(earlier, "turn", 2L))
        assertFalse(CollaborationResearchArchive.visible(JSONObject().put("turn_id", "turn"), "turn", 4L))
        assertTrue(CollaborationResearchArchive.visible(earlier, "different-turn", 0L))
    }

    @Test fun failedProviderDoesNotMarkGoalAchieved() = runBlocking {
        val store = InMemoryAgentTeamExecutionStore()
        AgentTeamExecutionRuntime(store).use { runtime ->
            val result = runtime.start(team(), request()) { error("Provider unavailable") }.await()
            assertEquals("continue", result.snapshot.goalDisposition)
            assertTrue(store.advanceGoal("research-run", "person-0", 10_000))
        }
    }

    @Test fun legacyResearchDoesNotRestartOnUpgrade() = runBlocking {
        val store = InMemoryAgentTeamExecutionStore()
        val legacy = team().let { it.copy(members = it.members.map { member -> member.copy(context = member.context - CollaborationGoalLoop.ENABLED) }) }
        AgentTeamExecutionRuntime(store).use { runtime ->
            val result = runtime.start(legacy, request()) { AgentSubagentOutput("Legacy final result") }.await()
            assertEquals(AgentTeamExecutionState.SUCCEEDED, result.snapshot.state)
            assertFalse(store.advanceGoal("research-run", "person-0", Long.MAX_VALUE))
        }
    }

    @Test fun autoKeepsSimpleTasksCheapAndRespectsExplicitMode() {
        val people = (0..2).map { AgentRequestedMember("codex", "Person $it", persistentInstanceId = "p$it", collaborationGroupId = "group") }
        assertFalse(CollaborationResearchWorkflow.enabled("What is 17 times 23?", people))
        assertTrue(CollaborationResearchWorkflow.enabled("Design a better plan", people))
        assertFalse(CollaborationResearchWorkflow.enabled("Design a plan", people.map { it.copy(collaborationWorkflow = "PARALLEL") }))
        assertTrue(CollaborationResearchWorkflow.enabled("Compare these", people.map { it.copy(collaborationWorkflow = "RESEARCH") }))
        assertFalse(CollaborationResearchWorkflow.enabled("Research", people.map { it.copy(collaborationGroupId = "") }))
        assertTrue(CollaborationResearchWorkflow.enabled("Research", people.take(2)))
        assertTrue(CollaborationResearchWorkflow.enabled("继续", people))
    }

    @Test fun targetedQuestionsRemainScopedAndIdempotent() {
        val definition = team()
        val sender = definition.members[1].copy(context = definition.members[1].context + (CollaborationResearchWorkflow.STAGE to "EXECUTE"))
        val output = artifact("Finding").put("requests", JSONArray().put(JSONObject()
            .put("to", JSONArray(listOf("person-2", "person-3", "outsider")))
            .put("question", "Can you falsify this?").put("candidate_id", "C1"))).toString()
        val messages = CollaborationDirectedDiscussion.messages(definition, request(), sender, output)
        assertEquals(setOf("person-2", "person-3"), messages.map { it.toInstanceId }.toSet())
        val mailbox = InMemoryAgentTeamMailbox()
        repeat(3) { messages.forEach(mailbox::append) }
        assertEquals(2, mailbox.messages("research-run").size)
    }

    @Test fun malformedArtifactsArePreservedAsUnverifiedNotes() {
        val raw = "Unverified proposal"
        val parsed = requireNotNull(CollaborationResearchArtifact.decode(CollaborationResearchArtifact.handoff(raw, CollaborationResearchStage.VERIFY)))
        assertTrue(parsed.getBoolean("unstructured"))
        assertEquals(raw, parsed.getString("summary"))
        assertEquals(raw, CollaborationResearchArtifact.handoff(raw, CollaborationResearchStage.DELIVER))
    }

    @Test fun groupWorkflowRoundTripsWithoutChangingMemberSettings() {
        val group = CollaborationGroup("group", listOf(CollaborationMember(name = "Turing", agentId = "codex", providerLabel = "Codex")), workflow = CollaborationWorkflow.RESEARCH)
        assertEquals(group, CollaborationGroupCodec.decode(CollaborationGroupCodec.encode(group)))
        assertEquals("RESEARCH", group.requested(emptyList()).single().collaborationWorkflow)
    }
}

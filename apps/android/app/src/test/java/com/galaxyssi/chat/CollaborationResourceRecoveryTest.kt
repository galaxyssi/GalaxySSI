package com.galaxyssi.chat

import kotlinx.coroutines.runBlocking
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CollaborationResourceRecoveryTest {
    private fun blocker(kind: String = "resource") = JSONObject().put("id", "lab-access").put("kind", kind)
        .put("reason", "No authorized experimental platform").put("resume_when", "Authorized platform is connected")
    private fun assessment(blocker: JSONObject = blocker()) = JSONObject().put("format", CollaborationGoalLoop.FORMAT)
        .put("summary", "Physical verification remains unavailable").put("decision", "blocked")
        .put("criteria", JSONArray().put(JSONObject().put("id", "experiment").put("requirement", "Real experiment")
            .put("verification", "physical").put("status", "open").put("evidence", JSONArray())))
        .put("work", JSONArray()).put("blockers", JSONArray().put(blocker))
    private fun people() = CollaborationGoalLoop.initial(listOf(
        AgentTeamMember("fixture", AgentDeliveryMode.RESPOND, instanceId = "lead"),
        AgentTeamMember("fixture", AgentDeliveryMode.OBSERVE, instanceId = "worker")
    ).map { it.copy(context = mapOf("collaboration_group_id" to "group")) }, "Real experiment")
    private fun definition() = AgentTeamDefinition("team", "fixture", people(), primaryInstanceId = "lead")
    private fun request() = AgentRunRequest("group", "turn", "task", runId = "run", goal = "Real experiment")

    @Test fun resourceAndPermissionBlocksFirstRequireActualResolutionWork() {
        listOf("resource", "permission").forEach { kind ->
            val block = blocker(kind)
            assertEquals("continue", CollaborationGoalLoop.disposition(assessment(block).toString()))
            val jobs = CollaborationResourceRecovery.jobs(JSONArray().put(block), people(), "lead", emptySet())
            assertEquals(1, jobs.size)
            assertEquals("worker", jobs.first().getString("member"))
            assertEquals("EXPLORE", jobs.first().getString("stage"))
            assertTrue(jobs.first().getString("assignment").contains("Simulation never counts as a physical experiment"))
            assertTrue(jobs.first().getString("assignment").contains("Do not buy"))
            assertTrue(CollaborationResourceRecovery.jobs(JSONArray().put(block), people(), "lead",
                setOf(CollaborationResourceRecovery.workId(block))).isEmpty())
        }
    }

    @Test fun modelClaimedAlternativesWithoutHostRecordedExecutionDoNotStopResearch() {
        val block = blocker().put("alternatives", JSONArray().put(JSONObject().put("option", "Simulation")
            .put("status", "not_applicable").put("result", "Cannot establish actual physical activity")
            .put("evidence", JSONArray().put("artifact:feasibility-report"))))
        val raw = assessment(block).toString()
        assertEquals("continue", CollaborationGoalLoop.disposition(raw))
        assertEquals("blocked", CollaborationGoalLoop.disposition(raw, "[]", setOf(CollaborationResourceRecovery.workId(block))))
        block.getJSONArray("alternatives").getJSONObject(0).put("status", "available")
        assertEquals("continue", CollaborationGoalLoop.disposition(assessment(block).toString(), "[]", setOf(CollaborationResourceRecovery.workId(block))))
    }

    @Test fun physicalCriterionCannotBeMetBySimulationOrWeakenedIntoComputationalCriterion() {
        val report = assessment().put("blockers", JSONArray()).put("decision", "achieved")
        val criterion = report.getJSONArray("criteria").getJSONObject(0)
        criterion.put("status", "met").put("evidence_kind", "simulation").put("evidence", JSONArray().put("artifact:simulation"))
        assertEquals("continue", CollaborationGoalLoop.disposition(report.toString()))
        val frozen = report.getJSONArray("criteria").toString()
        criterion.put("verification", "computational")
        assertEquals("continue", CollaborationGoalLoop.disposition(report.toString(), frozen))
        criterion.put("verification", "physical").put("evidence_kind", "observed")
        assertEquals("achieved", CollaborationGoalLoop.disposition(report.toString(), frozen))
    }

    @Test fun actualRecoveryNodeIsScheduledAndSuccessfulCheckIsNotRepeated() = runBlocking {
        val store = InMemoryAgentTeamExecutionStore()
        AgentTeamExecutionRuntime(store).use { runtime ->
            val worker = AgentTeamMemberWorker { AgentSubagentOutput(assessment().toString()) }
            runtime.start(definition(), request(), worker).await()
            assertTrue(store.advanceGoal("run", "lead", 1000))
            val checkpoint = store.resumeCheckpoint("run")!!
            val job = checkpoint.definition.members.first { it.deliveryMode == AgentDeliveryMode.OBSERVE }
            assertEquals(CollaborationResourceRecovery.workId(blocker()), job.context[CollaborationGoalLoop.WORK_ID])
            val result = runtime.resume(checkpoint, worker).await()
            // Missing alternative evidence keeps the coordinator revising, but doesn't redo completed discovery.
            assertEquals("continue", result.snapshot.goalDisposition)
            assertTrue(store.advanceGoal("run", result.snapshot.primaryMemberId, 2000))
            val repair = store.resumeCheckpoint("run")!!
            assertEquals(1, repair.definition.members.count { it.deliveryMode != AgentDeliveryMode.IGNORE })
            assertTrue(repair.request.context[CollaborationGoalLoop.RETRY_AT].toString().toLong() > 2000)
        }
    }

    @Test fun failedRecoveryIsRetriedWithBackoffInsteadOfFastLoopOrFalseCompletion() = runBlocking {
        val store = InMemoryAgentTeamExecutionStore()
        AgentTeamExecutionRuntime(store).use { runtime ->
            val worker = AgentTeamMemberWorker {
                if (it.member.deliveryMode == AgentDeliveryMode.RESPOND) AgentSubagentOutput(assessment().toString())
                else error("Network disconnected")
            }
            runtime.start(definition(), request(), worker).await()
            store.advanceGoal("run", "lead", 1000)
            val failed = runtime.resume(store.resumeCheckpoint("run")!!, worker).await()
            assertEquals("continue", failed.snapshot.goalDisposition)
            assertTrue(store.advanceGoal("run", failed.snapshot.primaryMemberId, 2000))
            val retry = store.resumeCheckpoint("run")!!
            assertEquals(2, retry.definition.members.count { it.deliveryMode != AgentDeliveryMode.IGNORE })
            assertTrue(retry.request.context[CollaborationGoalLoop.RETRY_AT].toString().toLong() > 2000)
        }
    }
}

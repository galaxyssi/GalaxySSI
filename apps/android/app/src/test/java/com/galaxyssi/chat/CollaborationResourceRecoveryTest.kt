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
        assertEquals("continue", CollaborationGoalLoop.disposition(report.toString(), frozen))
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
            val feedback = JSONObject(repair.request.context.getValue(CollaborationResourceRecovery.FEEDBACK).toString())
            val observation = feedback.getJSONArray("observations").getJSONObject(0)
            assertEquals("assessment_needs_repair", observation.getString("record_status"))
            assertTrue(observation.getBoolean("resolution_work_completed"))
            assertEquals("blockers[0].alternatives", observation.getJSONArray("issues").getJSONObject(0).getString("path"))
            assertEquals(assessment().getJSONArray("criteria").toString(), repair.request.context[CollaborationGoalLoop.CRITERIA])
        }
    }

    @Test fun feedbackDistinguishesUnfinishedExplorationFromInvalidAssessmentWithoutChangingDisposition() {
        val block = blocker()
        val raw = assessment(block).toString()
        val before = block.toString()
        fun observation(finished: Set<String>) = JSONObject(CollaborationResourceRecovery.feedback(JSONArray().put(block), finished))
            .getJSONArray("observations").getJSONObject(0)
        assertEquals("resolution_not_completed", observation(emptySet()).getString("record_status"))
        val finished = setOf(CollaborationResourceRecovery.workId(block))
        assertEquals("assessment_needs_repair", observation(finished).getString("record_status"))
        assertEquals(before, block.toString())
        assertEquals("continue", CollaborationGoalLoop.disposition(raw, "[]", finished))
    }

    @Test fun exactAlternativeFieldProblemsDoNotMasqueradeAsJsonErrors() {
        val block = blocker().put("alternatives", JSONArray().put(JSONObject().put("option", "Local prediction")
            .put("status", "available").put("result", "").put("evidence", JSONArray().put(""))))
        val feedback = JSONObject(CollaborationResourceRecovery.feedback(JSONArray().put(block), setOf(CollaborationResourceRecovery.workId(block))))
        val issues = feedback.getJSONArray("observations").getJSONObject(0).getJSONArray("issues")
        val paths = (0 until issues.length()).map { issues.getJSONObject(it).getString("path") }.toSet()
        assertEquals(setOf("blockers[0].alternatives[0].result", "blockers[0].alternatives[0].status", "blockers[0].alternatives[0].evidence[0]"), paths)
        assertFalse(CollaborationResourceRecovery.hasAlternatives(block))
        assertTrue(feedback.getString("guidance").contains("new work ID"))
        assertTrue(feedback.getString("guidance").contains("No retry-count"))
        assertFalse(feedback.getString("evidence_validation").contains("scientific proof"))
    }

    @Test fun completeBlockingRecordIsNotAClaimOfScientificVerification() {
        val block = blocker().put("alternatives", JSONArray().put(JSONObject().put("option", "Experimental platform")
            .put("status", "needs_approval").put("result", "No authorized connection")
            .put("evidence", JSONArray().put("artifact:capability-audit"))))
        val finished = setOf(CollaborationResourceRecovery.workId(block))
        val feedback = JSONObject(CollaborationResourceRecovery.feedback(JSONArray().put(block), finished))
        assertEquals("blocking_record_complete", feedback.getJSONArray("observations").getJSONObject(0).getString("record_status"))
        assertTrue(CollaborationResourceRecovery.hasAlternatives(block))
        assertTrue(feedback.getString("evidence_validation").contains("not verified"))
        assertEquals("blocked", CollaborationGoalLoop.disposition(assessment(block).toString(), "[]", finished))
        assertEquals("", CollaborationResourceRecovery.feedback(JSONArray().put(blocker("connectivity")), emptySet()))
    }

    @Test fun malformedAlternativesReportTheirExactLocations() {
        val block = blocker().put("resume_when", "").put("alternatives", JSONArray().put("not an object"))
        val issues = JSONObject(CollaborationResourceRecovery.feedback(JSONArray().put(block), emptySet()))
            .getJSONArray("observations").getJSONObject(0).getJSONArray("issues")
        assertEquals("blockers[0].alternatives[0]", issues.getJSONObject(0).getString("path"))
        assertEquals("blockers[0].resume_when", issues.getJSONObject(1).getString("path"))
        assertFalse(CollaborationResourceRecovery.hasAlternatives(block))
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

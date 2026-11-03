package com.galaxyssi.chat

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.util.UUID
import java.util.concurrent.CopyOnWriteArrayList
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** Synthetic worker receipts exercise dispatch policy and encrypted recovery, not model quality or actual delivery. */
@RunWith(AndroidJUnit4::class)
class CollaborationDecisionOwnershipDeviceTest {
    @Test fun plannedChainKeepsItsOwnersAndFinalizesWithoutIncrementalChecks() = runBlocking { verify(false) }

    @Test fun reopeningAfterTheProducerDoesNotReplayItOrAddAnUnneededCoordinator() = runBlocking { verify(true) }

    private suspend fun verify(recoverProducer: Boolean) = withTimeout(45_000) {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val database = AgentEncryptedDatabase(context, "decision-owner-${UUID.randomUUID()}")
        try {
            val store = EncryptedAgentTeamExecutionStore(database)
            val people = (0..2).map { AgentTeamMember("fixture", instanceId = "person-$it",
                deliveryMode = if (it == 0) AgentDeliveryMode.RESPOND else AgentDeliveryMode.OBSERVE,
                context = mapOf("collaboration_group_id" to "decision-owner-fixture")) }
            val definition = AgentTeamDefinition("decision-owner-fixture", "fixture",
                CollaborationGoalLoop.initial(people, "Fixture").map {
                    it.copy(context = it.context + (CollaborationLiveGraph.ENABLED to "1"))
                }, primaryInstanceId = "person-0")
            val request = AgentRunRequest("decision-owner-fixture", "turn", "task", runId = "root",
                goal = "Synthetic authored report, independent review and closing statement. Preserve all evidence.")
            AgentTeamExecutionRuntime(store).use { runtime ->
                runtime.start(definition, request) { AgentSubagentOutput(plan().toString()) }.await()
            }
            assertTrue(store.advanceGoal("root", "person-0", System.currentTimeMillis()))
            val seed = requireNotNull(store.resumeCheckpoint("root"))
            if (recoverProducer) {
                val producer = seed.definition.members.single { it.context[CollaborationGoalLoop.WORK_ID] == "report" }
                val provenance = AgentTeamGraphPlan.build(seed.definition, seed.request).children
                    .single { it.childId == producer.memberId }.provenance
                val result = AgentSubagentChildResult("root", producer.memberId, "root", 1, AgentSubagentStatus.SUCCEEDED,
                    output = artifact("report"), startedAtMillis = 1, completedAtMillis = 2, provenance = provenance)
                store.append(AgentSubagentEvent(seed.lastSequence + 1, "root", producer.memberId,
                    AgentSubagentEventKinds.CHILD_SUCCEEDED, childStatus = result.status, result = result,
                    timestampMillis = 2, provenance = provenance))
                store.expandResearchGraph("root", seed.definition.primaryMemberId, setOf(producer.memberId), 3)
            }
            val reopened = EncryptedAgentTeamExecutionStore(database)
            val checkpoint = requireNotNull(reopened.resumeCheckpoint("root"))
            assertEquals(if (recoverProducer) 1 else 0, checkpoint.completed.size)
            assertFalse(checkpoint.definition.members.any(CollaborationLiveGraph::planner))
            val calls = CopyOnWriteArrayList<String>()
            AgentTeamExecutionRuntime(reopened).use { runtime ->
                val result = runtime.resume(checkpoint) { execution ->
                    assertFalse("The existing successor must own routine handoff", CollaborationLiveGraph.planner(execution.member))
                    val work = execution.member.context[CollaborationGoalLoop.WORK_ID]
                    if (work == null) {
                        calls += "final"
                        AgentSubagentOutput(plan().put("work", JSONArray()).toString())
                    } else {
                        assertFalse(recoverProducer && work == "report")
                        calls += work
                        if (work != "report") {
                            val input = JSONObject(execution.handoff.dependencies.single().output)
                            assertEquals("recorded", input.getJSONObject("delivery_receipt").getString("status"))
                            assertEquals("Still needs downstream checking", input.getJSONArray("questions").getString(0))
                        }
                        AgentSubagentOutput(artifact(work))
                    }
                }.await()
                assertEquals(result.subagentResult.results.joinToString("\n") {
                    "${it.childId}: ${it.status}: ${it.errorMessage}"
                }, AgentSubagentRunStatus.SUCCEEDED, result.subagentResult.status)
            }
            assertEquals(if (recoverProducer) listOf("review", "closing", "final") else
                listOf("report", "review", "closing", "final"), calls.toList())
            assertFalse(requireNotNull(reopened.deliveryCheckpoint("root")).definition.members.any(CollaborationLiveGraph::planner))
        } finally { database.clear() }
    }

    private fun artifact(work: String) = JSONObject().put("format", CollaborationResearchArtifact.FORMAT)
        .put("summary", "Synthetic $work; this is not a real model result")
        .put("questions", JSONArray().put("Still needs downstream checking"))
        .put("workspace_receipt", JSONObject().put("status", "recorded"))
        .put("delivery_receipt", JSONObject().put("status", "recorded")).toString()

    private fun plan() = JSONObject().put("format", CollaborationGoalLoop.FORMAT).put("summary", "Synthetic task graph")
        .put("decision", "continue").put("criteria", JSONArray().put(JSONObject().put("id", "report")
            .put("requirement", "Preserve a report and independent review").put("verification", "documentary")
            .put("status", "open").put("evidence", JSONArray())))
        .put("work", JSONArray().put(job("report", "person-1")).put(job("review", "person-2", "report")
            .put("stage", "VERIFY").put("independent_review", true)).put(job("closing", "person-1", "review")))
        .put("blockers", JSONArray())

    private fun job(id: String, person: String, vararg dependencies: String) = JSONObject().put("id", id)
        .put("member", person).put("stage", "EXECUTE").put("assignment", "Preserve $id evidence")
        .put("depends_on", JSONArray(dependencies.toList()))
}

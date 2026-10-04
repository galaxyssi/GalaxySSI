package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** Only local fixture computation, graph admission and encrypted persistence. No model/tool calls. */
@RunWith(AndroidJUnit4::class)
class CollaborationWorkflowDeviceTest {
    @Test fun workflowGraphAndFailureFeedbackSurviveEncryptedReopen() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val group = "workflow-fixture-${UUID.randomUUID()}"
        val groups = CollaborationGroupStore(context)
        val database = AgentEncryptedDatabase(context, "workflow-fixture-$group")
        groups.update(group) { it.copy(members = listOf("lead", "worker").map { id -> CollaborationMember(id, id, "fixture", "Fixture") }, coordinatorId = "lead") }
        try {
            val workspace = CollaborationResearchWorkspace(context)
            fun access(round: Long) = CollaborationWorkspaceAccess(group, "run", "turn", round, "lead", "lead")
            val spec = JSONObject().put("purpose", "Reuse parsed fixture").put("domain", "fixture").put("bottleneck", "Repeated parsing")
                .put("change_rationale", "Parse once").put("applies_when", "Immutable input").put("avoid_when", "Mutable input")
                .put("risks", "Incorrect cache").put("expected_gain", "Lower parse count").put("falsifier", "Result mismatch")
                .put("dimensions", JSONArray().put("retrieval").put("verification")).put("roles", JSONArray().put("worker").put("reviewer"))
                .put("inputs", JSONArray().put("text")).put("steps", JSONArray()
                    .put(JSONObject().put("id", "parse").put("role", "worker").put("stage", "EXECUTE").put("assignment", "Parse local fixture").put("depends_on", JSONArray()))
                    .put(JSONObject().put("id", "check").put("role", "reviewer").put("stage", "VERIFY").put("assignment", "Check parsed values")
                        .put("depends_on", JSONArray().put("parse")).put("independent_review", true)))
            val raw = JSONObject().put("format", CollaborationResearchArtifact.FORMAT).put("summary", "Local method fixture")
                .put("findings", JSONArray()).put("candidates", JSONArray()).put("workspace", JSONArray().put(JSONObject().put("id", "method")
                    .put("kind", CollaborationWorkflowMethod.KIND).put("title", "Fixture method")
                    .put("body", JSONObject().put("content", "Synthetic method").put(CollaborationWorkflowMethod.KIND, spec)))).toString()
            val receipt = workspace.publish(access(1), raw, 10)
            assertEquals(receipt.toString(), "recorded", receipt.getString("status"))
            val method = receipt.getJSONArray("revisions").getJSONObject(0)
            val goal = "Parse local fixture"
            val members = CollaborationGoalLoop.initial(listOf(AgentTeamMember("fixture", AgentDeliveryMode.RESPOND, instanceId = "lead"),
                AgentTeamMember("fixture", AgentDeliveryMode.OBSERVE, instanceId = "worker")), goal)
            val record = AgentTeamExecutionRecord(AgentTeamDefinition("fixture", "fixture", members, primaryInstanceId = "lead"),
                AgentRunRequest(group, "turn", "fixture", runId = "run", goal = goal))
            val work = CollaborationEvolutionContract.objects(spec, "steps").map { step ->
                JSONObject(step.toString()).apply { remove("role") }.put("member", if (step.getString("role") == "worker") "worker" else "lead")
                    .put(CollaborationWorkflowWork.FIELD, JSONObject().put("execution_id", "local").put("method", method)
                        .put("step_id", step.getString("id")).put("inputs", JSONObject().put("text", "{\"value\":7}")))
            }
            val first = CollaborationWorkflowWork.plan(record, work, { workspace }, access(2))
            val restored = record.copy(request = record.request.copy(context = record.request.context + (CollaborationWorkflowWork.CLAIMS to first.claims)))
            assertEquals(first.claims, CollaborationWorkflowWork.plan(restored, work, { CollaborationResearchWorkspace(context) }, access(3)).claims)
            var baselineCalls = 0
            val baseline = List(4) { JSONObject("{\"value\":7}").also { baselineCalls++ }.getInt("value") }
            var candidateCalls = 0
            val parsed = JSONObject("{\"value\":7}").also { candidateCalls++ }
            val candidate = List(4) { parsed.getInt("value") }
            assertEquals(baseline, candidate); assertEquals(4, baselineCalls); assertEquals(1, candidateCalls)
            val worker = members.last().copy(context = members.last().context + CollaborationWorkflowWork.context(first.work.first()) +
                (CollaborationPredictionWork.TASK to "{\"fixture\":\"saved prediction binding\"}"))
            val executing = restored.copy(definition = restored.definition.copy(members = listOf(members.first(), worker)))
            val failure = AgentSubagentChildResult("run", worker.memberId, "run", 1, AgentSubagentStatus.FAILED, "Fixture failure retained", startedAtMillis = 100, completedAtMillis = 120)
            val feedback = CollaborationWorkflowWork.capture(executing, listOf(failure))
            assertEquals("failed", JSONObject(feedback).getJSONObject(worker.memberId).getString("status"))
            assertFalse(JSONObject(feedback).getJSONObject(worker.memberId).getBoolean("quality_improved"))
            val resumed = executing.copy(request = executing.request.copy(context = executing.request.context + (CollaborationWorkflowWork.OUTCOMES to feedback)))
            assertEquals(feedback, CollaborationWorkflowWork.capture(resumed, listOf(failure.copy(completedAtMillis = 999))))
            val store = EncryptedAgentTeamExecutionStore(database)
            store.create(resumed.definition, resumed.request)
            store.markInterrupted("run", 500)
            val checkpoint = requireNotNull(EncryptedAgentTeamExecutionStore(database).resumeCheckpoint("run"))
            assertEquals(first.claims, checkpoint.request.context[CollaborationWorkflowWork.CLAIMS])
            assertEquals(feedback, checkpoint.request.context[CollaborationWorkflowWork.OUTCOMES])
            assertEquals(worker.context[CollaborationWorkflowWork.TASK], checkpoint.definition.members.last().context[CollaborationWorkflowWork.TASK])
            assertEquals(worker.context[CollaborationPredictionWork.TASK], checkpoint.definition.members.last().context[CollaborationPredictionWork.TASK])
            val incomplete = runCatching { CollaborationWorkflowWork.plan(record, work.take(1), { workspace }, access(3)) }
            assertTrue(incomplete.isFailure)
        } finally { database.clear(); groups.remove(group) }
    }
}

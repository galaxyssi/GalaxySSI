package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** Synthetic measurements only: no provider calls, external actions or edits to existing research. */
@RunWith(AndroidJUnit4::class)
class CollaborationEvolutionDeviceTest {
    private val context = InstrumentationRegistry.getInstrumentation().targetContext

    @Test fun typedInnovationSurvivesReopenAndCloudNativeRecallRemainScoped() = fixture { group ->
        val author = access(group, "author", 1)
        val workspace = CollaborationResearchWorkspace(context)
        val input = raw("idea", "innovation", innovation())
        val receipt = workspace.publish(author, input, 20)
        assertEquals(receipt.toString(), "recorded", receipt.optString("status"))
        assertEquals(receipt.toString(), CollaborationResearchWorkspace(context).publish(author, input).toString())
        val reader = access(group, "reviewer", 2)
        val directory = JSONObject(CollaborationCloudRecall.execute(context, reader, JSONObject().put("mode", "evolution")))
        assertEquals("returned", directory.getString("status"))
        assertEquals(1, directory.getJSONArray("revisions").length())
        assertEquals(0, JSONObject(CollaborationCloudRecall.execute(context, reader.copy(round = 1),
            JSONObject().put("mode", "evolution"))).getJSONArray("revisions").length())
        CollaborationEvidenceLedger(context).bind(AgentTeamDispatchIds.sourceMessageId("evolution:$group"), reader)
        val registry = AgentPhoneNativeToolCatalog.defaultRegistry(context, { ScreenContext(foregroundApp = "", pageTitle = "") })
            .subset { it.id == CollaborationRecallNativeTool.ID }
        val native = registry.invoke(CollaborationRecallNativeTool.ID, mapOf("mode" to "evolution_rules", "offset" to 0),
            AgentNativeToolInvocationContext(conversationId = group, turnId = "turn",
                collaborationSourceMessageId = AgentTeamDispatchIds.sourceMessageId("evolution:$group")))
        assertTrue(native.toJson(), native.isSuccess)
        assertTrue(native.output["content"].toString().contains("capability_gap"))
        assertFalse(native.output["content"].toString().contains("automatically grant"))
    }

    @Test fun realEncryptedEvidenceProducesScopedLessonAndKeepsBaseline() = fixture { group ->
        val workspace = CollaborationResearchWorkspace(context)
        fun publish(person: String, round: Long, id: String, kind: String, body: JSONObject, observations: JSONArray = JSONArray(), now: Long): JSONObject {
            val raw = JSONObject(raw(id, kind, body))
            raw.getJSONArray("workspace").getJSONObject(0).put("observations", observations)
            val result = workspace.publish(access(group, person, round), raw.toString(), now)
            assertEquals(result.toString(), "recorded", result.optString("status"))
            return result.getJSONArray("revisions").getJSONObject(0)
        }
        val baseline = publish("baseline", 1, "baseline", "artifact", JSONObject(), now = 10)
        val idea = publish("author", 1, "idea", "innovation", innovation(), now = 20)
        val cases = JSONArray().put(testCase("target", "target")).put(testCase("old", "regression"))
        val spec = JSONObject().put("innovation", idea).put("baseline", baseline).put("prediction_id", "p1")
            .put("method", "Deterministic fixture").put("environment", "device-fixture").put("budget_unit", "operations").put("budget_limit", 100)
            .put("source", JSONObject().put("origin", "android_native_tool").put("tool", "fixture.benchmark"))
            .put("report_pointer", "/report").put("cases", cases)
        val plan = publish("planner", 2, "plan", "experiment_plan", spec, now = 100)
        val measurements = JSONArray()
        for (case in listOf("target", "old")) for (variant in listOf("baseline", "candidate")) {
            measurements.put(JSONObject().put("case_id", case).put("variant", variant).put("variant_sha256",
                (if (variant == "baseline") baseline else idea).getString("sha256"))
                .put("repetition", 1).put("metric", "score").put("value", if (variant == "candidate") 12 else 10).put("budget_used", 20))
        }
        val output = JSONObject().put("report", JSONObject().put("format", CollaborationEvolutionExperiment.FORMAT)
            .put("plan_sha256", plan.getString("sha256")).put("environment", "device-fixture").put("budget_unit", "operations")
            .put("measurements", measurements).toString())
        val ledger = CollaborationEvidenceLedger(context)
        val observation = ledger.record(access(group, "executor", 3), "synthetic-trial", "fixture.benchmark", "{}", output.toString(),
            200, 201, CollaborationEvidenceOrigin.ANDROID_NATIVE_TOOL)
        fun readOriginal(person: String, round: Long) {
            var offset: Int? = 0
            while (offset != null) offset = ledger.readPage(access(group, person, round), observation.getString("evidence_id"),
                observation.getString("sha256"), offset)!!.next
        }
        readOriginal("analyst", 4)
        val result = publish("analyst", 4, "result", "experiment_result", JSONObject().put("plan", plan)
            .put("interpretation", "Synthetic arithmetic check").put("limitations", "Not a model capability benchmark"), JSONArray().put(observation), 300)
        assertEquals("measured_improvement", result.getJSONObject("host_evolution").getString("state"))
        readOriginal("reviewer", 5)
        val lesson = publish("reviewer", 5, "lesson", "capability_lesson", JSONObject().put("result", result).put("decision", "retain")
            .put("rationale", "Check exact records").put("applies_when", "Synthetic fixture only").put("avoid_when", "Real applications")
            .put("procedure", "Fixture procedure").put("transfer_test", "New trial required").put("rollback", baseline), JSONArray().put(observation), 400)
        assertFalse(lesson.getJSONObject("host_evolution").getBoolean("automatically_installed"))
        val reopened = CollaborationResearchWorkspace(context)
        assertNotNull(reopened.read(access(group, "reviewer", 6), baseline.getString("object_id"), 1))
        assertEquals(4, reopened.browseEvolution(access(group, "reviewer", 6)).revisions.size)
        verifyProcedureReuse(group, lesson)
    }

    private fun verifyProcedureReuse(group: String, lesson: JSONObject) = kotlinx.coroutines.runBlocking {
        val workspace = CollaborationResearchWorkspace(context)
        val author = access(group, "reviewer", 6).copy(nodeId = "skill-publication")
        val spec = JSONObject().put("lesson", lesson).put("name", "Fixture reusable procedure").put("keywords", JSONArray().put("fixture"))
            .put("limitations", "Synthetic test only").put("inputs", JSONArray().put(JSONObject().put("name", "values")
                .put("description", "Synthetic numbers").put("required", true)))
        val receipt = workspace.publish(author, raw("skill", CollaborationProceduralMemory.SKILL, spec), 500)
        assertEquals(receipt.toString(), "recorded", receipt.getString("status"))
        val skill = receipt.getJSONArray("revisions").getJSONObject(0)
        val database = AgentEncryptedDatabase(context, "procedure-fixture-$group")
        val run = "procedure-run-$group"
        fun store() = EncryptedAgentTeamExecutionStore(database, candidateWorkspace = { CollaborationResearchWorkspace(context) })
        fun report(work: JSONArray) = JSONObject().put("format", CollaborationGoalLoop.FORMAT).put("summary", "Synthetic reuse")
            .put("decision", "continue").put("criteria", JSONArray().put(JSONObject().put("id", "fixture")
                .put("requirement", "Compare local fixture").put("status", "open").put("evidence", JSONArray())))
            .put("work", work).put("blockers", JSONArray()).toString()
        try {
            val item = JSONObject().put("id", "reuse-work").put("member", "executor").put("stage", "EXECUTE")
                .put("assignment", "Run the synthetic procedure with new input").put("procedure_use", JSONObject().put("procedure", skill)
                    .put("inputs", JSONObject().put("values", JSONArray().put(2).put(3)))
                    .put("applicability", JSONObject().put("why", "Same fixture").put("conditions_checked", JSONArray().put("Local synthetic values"))
                        .put("remaining_uncertainty", "Not a model capability test")).put("failures", JSONArray()))
            val members = CollaborationGoalLoop.initial(listOf(AgentTeamMember("fixture", AgentDeliveryMode.RESPOND, instanceId = "planner"),
                AgentTeamMember("fixture", AgentDeliveryMode.OBSERVE, instanceId = "executor")), "Compare local fixture").map {
                it.copy(context = it.context + mapOf("collaboration_group_id" to group, CollaborationTeamOrganization.ENABLED to "0")) }
            val definition = AgentTeamDefinition("procedure-team", "fixture", members, primaryInstanceId = "planner")
            val request = AgentRunRequest(group, "new-turn", "task", runId = run, goal = "Compare local fixture", context = mapOf(CollaborationGoalLoop.ROUND to "7"))
            val first = store()
            first.create(definition, request)
            first.append(AgentSubagentEvent(1, run, "planner", AgentSubagentEventKinds.CHILD_SUCCEEDED, childStatus = AgentSubagentStatus.SUCCEEDED,
                result = AgentSubagentChildResult(run, "planner", run, 1, AgentSubagentStatus.SUCCEEDED, report(JSONArray().put(item)))))
            first.append(AgentSubagentEvent(2, run, kind = AgentSubagentEventKinds.SUPERVISOR_SUCCEEDED, runStatus = AgentSubagentRunStatus.SUCCEEDED))
            assertTrue(first.advanceGoal(run, "planner", 1000, true))
            val checkpoint = store().resumeCheckpoint(run)!!
            val selected = checkpoint.definition.members.single { CollaborationProcedureWork.TASK in it.context }
            val seen = mutableListOf<String>()
            AgentTeamExecutionRuntime(store(), AgentSubagentLimits(maxConcurrency = 1)).use { runtime ->
                runtime.resume(checkpoint) { execution ->
                    if (execution.member.memberId != selected.memberId) AgentSubagentOutput(report(JSONArray())) else {
                        seen += execution.member.memberId
                        val binding = JSONObject(execution.member.context.getValue(CollaborationProcedureWork.TASK))
                        assertEquals("Fixture procedure", binding.getString("method"))
                        assertFalse(binding.getBoolean("grants_permissions"))
                        val values = binding.getJSONObject("inputs").getJSONArray("values")
                        val sum = (0 until values.length()).sumOf(values::getInt)
                        assertEquals(5, sum)
                        AgentSubagentOutput("Synthetic method executed with new inputs: $sum")
                    }
                }.await()
            }
            assertEquals(1, seen.size)
            assertTrue(store().advanceGoal(run, checkpoint.definition.primaryMemberId, 5000, true))
            val next = store().resumeCheckpoint(run)!!
            val outcome = JSONObject(next.request.context.getValue(CollaborationProcedureWork.OUTCOMES).toString()).getJSONObject(selected.memberId)
            assertEquals("succeeded", outcome.getString("status")); assertFalse(outcome.getBoolean("capability_verified"))
            assertEquals(skill.getString("sha256"), outcome.getJSONObject("binding").getJSONObject("procedure").getString("sha256"))
            assertTrue(next.definition.members.none { CollaborationProcedureWork.TASK in it.context })
            val reader = access(group, "reviewer", 0).copy(runId = "another-task", turnId = "another-turn")
            val directory = JSONObject(CollaborationCloudRecall.execute(context, reader, JSONObject().put("mode", "evolution")))
            assertTrue(directory.toString().contains("procedure_skill"))
            assertNotNull(CollaborationProceduralMemory.current(CollaborationResearchWorkspace(context), reader, skill))
        } finally { database.clear() }
    }

    private fun fixture(block: (String) -> Unit) {
        val group = "evolution-device-${UUID.randomUUID()}"
        val groups = CollaborationGroupStore(context)
        groups.update(group) { it.copy(members = listOf("author", "reviewer", "planner", "baseline", "executor", "analyst")
            .map { id -> CollaborationMember(id, id, "fixture", "Fixture") }, coordinatorId = "planner") }
        try { block(group) } finally { groups.remove(group) }
    }
    private fun access(group: String, person: String, round: Long) = CollaborationWorkspaceAccess(group, "run", "turn", round, person, person)
    private fun raw(id: String, kind: String, value: JSONObject) = JSONObject().put("format", CollaborationResearchArtifact.FORMAT)
        .put("summary", "Synthetic fixture").put("candidates", JSONArray()).put("findings", JSONArray()).put("workspace", JSONArray().put(
            JSONObject().put("id", id).put("kind", kind).put("title", id).put("body", JSONObject().put("content", "Fixture content").put(kind, value)))).toString()
    private fun innovation() = JSONObject("""{"origin":"limitation","hypothesis":"Cached parsing improves speed","mechanism":"Reuse",
        "difference":"Less repeated parsing","prior_art":"Not searched","novelty_scope":"not_checked","falsifier":"No measured gain",
        "domain":"fixture","applies_when":"Same fixture","risks":"Stale data","alternatives":["Measurement error"],
        "predictions":[{"id":"p1","statement":"Improved score","test":"Paired test"}]}""")
    private fun testCase(id: String, purpose: String) = JSONObject().put("id", id).put("purpose", purpose).put("prediction", "No loss")
        .put("metric", "score").put("direction", "maximize").put("minimum_gain", 1).put("tolerance", 0).put("repetitions", 1)
}

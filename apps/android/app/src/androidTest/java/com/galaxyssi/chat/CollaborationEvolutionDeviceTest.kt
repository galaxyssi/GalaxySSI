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

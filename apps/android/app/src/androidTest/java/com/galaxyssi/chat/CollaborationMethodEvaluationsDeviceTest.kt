package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** Synthetic counterevidence through production publication, encrypted storage and both recall adapters. */
@RunWith(AndroidJUnit4::class)
class CollaborationMethodEvaluationsDeviceTest {
    @Test fun failedComparisonIsAvailableToFutureMethodSelectionWithoutBecomingAnExecutionSuccess() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val group = "method-evaluations-${UUID.randomUUID()}"
        val groups = CollaborationGroupStore(context)
        groups.update(group) { it.copy(members = listOf("author", "executor", "analyst", "reader").map { id ->
            CollaborationMember(id, id, "fixture", "Fixture") }, coordinatorId = "author") }
        try {
            fun access(person: String, round: Long, node: String = person) = CollaborationWorkspaceAccess(group, "run", "turn", round, node, person)
            val workspace = CollaborationResearchWorkspace(context)
            fun publish(id: String, kind: String, spec: JSONObject, round: Long, person: String = "author", refs: JSONArray = JSONArray()): JSONObject {
                val raw = JSONObject().put("format", CollaborationResearchArtifact.FORMAT).put("summary", "Local evaluation fixture")
                    .put("findings", JSONArray()).put("candidates", JSONArray()).put("workspace", JSONArray().put(JSONObject()
                        .put("id", id).put("kind", kind).put("title", id).put("observations", refs)
                        .put("body", JSONObject().put("content", "Synthetic local fixture, not capability evidence").put(kind, spec))))
                val receipt = workspace.publish(access(person, round, id), raw.toString(), round * 100)
                assertEquals(receipt.toString(), "recorded", receipt.getString("status"))
                return receipt.getJSONArray("revisions").getJSONObject(0)
            }
            fun method(assignment: String) = JSONObject().put("purpose", "Parse a fixture").put("domain", "fixture")
                .put("bottleneck", "Repeated work").put("change_rationale", "Investigate reuse").put("applies_when", "Immutable input")
                .put("avoid_when", "Changing input").put("risks", "Stale result").put("expected_gain", "Unknown")
                .put("falsifier", "Incorrect output").put("dimensions", JSONArray().put("verification"))
                .put("roles", JSONArray().put("worker")).put("inputs", JSONArray().put("dataset"))
                .put("steps", JSONArray().put(JSONObject().put("id", "evaluate").put("role", "worker").put("stage", "EXECUTE")
                    .put("assignment", assignment).put("depends_on", JSONArray())))
            val before = publish("before", "workflow_method", method("Parse fresh"), 1)
            val after = publish("after", "workflow_method", method("Reuse cached result"), 1)
            fun idea(method: JSONObject) = JSONObject().put("origin", "limitation").put("hypothesis", "Reuse may help")
                .put("mechanism", "Cache").put("difference", "Skip reparsing").put("prior_art", "Not checked")
                .put("novelty_scope", "not_checked").put("falsifier", "Stale output").put("domain", "fixture")
                .put("applies_when", "Same input").put("risks", "Changed source").put("alternatives", JSONArray().put("Parse fresh"))
                .put("predictions", JSONArray().put(JSONObject().put("id", "p1").put("statement", "Same correctness").put("test", "Local fixture")))
                .put("workflow_method", method)
            val control = publish("control", "innovation", idea(before), 2)
            val candidate = publish("candidate", "innovation", idea(after), 2)
            val dataset = publish("data", "artifact", JSONObject(), 2)
            val cases = JSONArray()
            for (purpose in listOf("target", "regression")) cases.put(JSONObject().put("id", purpose).put("purpose", purpose)
                .put("metric", "correct").put("direction", "maximize").put("minimum_gain", 0).put("tolerance", 0)
                .put("repetitions", 1).put("prediction", "No errors"))
            val plan = publish("plan", "experiment_plan", JSONObject().put("innovation", candidate).put("baseline", control)
                .put("prediction_id", "p1").put("method", "Synthetic comparison").put("environment", "device-fixture")
                .put("budget_unit", "operations").put("budget_limit", 10).put("report_pointer", "").put("cases", cases)
                .put("source", JSONObject().put("origin", "android_native_tool").put("tool", "fixture.compare"))
                .put("workflow_comparison", JSONObject().put("dataset", dataset).put("controlled_conditions", "Same local fixture")
                    .put("quality_oracle", "Known local outputs").put("cost_accounting", "Synthetic operation count")
                    .put("selection_bias", "Disclosed synthetic fixture")), 3)
            val measurements = JSONArray()
            for (purpose in listOf("target", "regression")) for (variant in listOf("baseline", "candidate")) {
                val old = variant == "baseline"
                measurements.put(JSONObject().put("case_id", purpose).put("variant", variant)
                    .put("variant_sha256", (if (old) control else candidate).getString("sha256"))
                    .put("workflow_sha256", (if (old) before else after).getString("sha256"))
                    .put("dataset_sha256", dataset.getString("sha256")).put("metric", "correct").put("repetition", 1)
                    .put("value", if (old) 1 else 0).put("budget_used", 1))
            }
            val report = JSONObject().put("format", CollaborationEvolutionExperiment.FORMAT).put("plan_sha256", plan.getString("sha256"))
                .put("environment", "device-fixture").put("budget_unit", "operations").put("measurements", measurements)
            val ledger = CollaborationEvidenceLedger(context)
            val observation = ledger.record(access("executor", 4), "trial", "fixture.compare", "{}", report.toString(), 400, 401,
                CollaborationEvidenceOrigin.ANDROID_NATIVE_TOOL)
            var offset: Int? = 0
            while (offset != null) offset = ledger.readPage(access("analyst", 5, "result"), observation.getString("evidence_id"),
                observation.getString("sha256"), offset)!!.next
            val result = publish("result", "experiment_result", JSONObject().put("plan", plan).put("interpretation", "Synthetic regression")
                .put("limitations", "Not a real model trial"), 5, "analyst", JSONArray().put(observation))
            publish("review", "capability_lesson", JSONObject().put("result", result).put("decision", "reject")
                .put("rationale", "Counterevidence must remain discoverable").put("applies_when", "No supported scope yet")
                .put("avoid_when", "Changed input").put("procedure", "Investigate cache invalidation")
                .put("transfer_test", "Future fresh cases").put("rollback", control), 6, "reader")
            val future = access("reader", 0).copy(runId = "future", turnId = "future")
            val query = CollaborationMethodEvaluations.selector(after)
            val cloud = JSONObject(CollaborationCloudRecall.execute(context, future, query))
            assertEquals(cloud.toString(), "returned", cloud.getString("status"))
            val records = cloud.getJSONArray("records")
            assertEquals(3, records.length())
            assertTrue((0 until records.length()).map(records::getJSONObject).any { it.optString("measured_state") == "regressed" })
            assertTrue((0 until records.length()).map(records::getJSONObject).any { it.optString("review_decision") == "reject" })
            val source = AgentTeamDispatchIds.sourceMessageId("method-evaluations:$group")
            ledger.bind(source, future)
            val registry = AgentPhoneNativeToolCatalog.defaultRegistry(context, { ScreenContext(foregroundApp = "", pageTitle = "") })
                .subset { it.id == CollaborationRecallNativeTool.ID }
            val native = registry.invoke(CollaborationRecallNativeTool.ID, query.keys().asSequence().associateWith { query.get(it) },
                AgentNativeToolInvocationContext(conversationId = group, turnId = "future", collaborationSourceMessageId = source))
            assertTrue(native.toJson(), native.isSuccess)
            val again = CollaborationResearchWorkspace(context).methodEvaluations(future, after)
            assertEquals(records.toString(), again.getJSONArray("records").toString())
            assertTrue(again.isNull("quality_effect")); assertFalse(again.getBoolean("automatically_adopted"))
            val invalid = JSONObject(query.toString()).put("mode", "workspace")
            assertEquals("failed", JSONObject(CollaborationCloudRecall.execute(context, future, invalid)).getString("status"))
        } finally { groups.remove(group) }
    }
}

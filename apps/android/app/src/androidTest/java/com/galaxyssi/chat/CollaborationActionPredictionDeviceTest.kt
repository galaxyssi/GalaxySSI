package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** Local computation and encrypted persistence only; no provider calls or physical actions. */
@RunWith(AndroidJUnit4::class)
class CollaborationActionPredictionDeviceTest {
    @Test fun forecastLocalActionErrorCorrectionAndTaskBindingSurviveReopen() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val group = "prediction-fixture-${UUID.randomUUID()}"
        val groups = CollaborationGroupStore(context)
        groups.update(group) { it.copy(members = listOf("lead", "worker", "reviewer").map { id -> CollaborationMember(id, id, "fixture", "Fixture") }, coordinatorId = "lead") }
        try {
            val ledger = CollaborationEvidenceLedger(context)
            val workspace = CollaborationResearchWorkspace(context)
            val goal = "Predict local sort correctness"
            fun access(person: String, round: Long, node: String = person) = CollaborationWorkspaceAccess(group, "run", "turn", round, node, person)
            fun publish(id: String, kind: String, value: JSONObject, person: String, round: Long, observations: JSONArray = JSONArray()): JSONObject {
                val raw = JSONObject().put("format", CollaborationResearchArtifact.FORMAT).put("summary", "Local prediction fixture")
                    .put("findings", JSONArray()).put("candidates", JSONArray()).put("workspace", JSONArray().put(JSONObject().put("id", id)
                        .put("kind", kind).put("title", id).put("body", JSONObject().put("content", "Synthetic data").put(kind, value)).put("observations", observations))).toString()
                val receipt = workspace.publish(access(person, round, id), raw, round * 10)
                assertEquals(receipt.toString(), "recorded", receipt.getString("status"))
                return receipt.getJSONArray("revisions").getJSONObject(0)
            }
            val baseline = publish("input", "artifact", JSONObject().put("values", JSONArray().put(3).put(1).put(2)), "lead", 1)
            fun action(id: String, mode: String) = JSONObject().put("id", id).put("mode", mode).put("description", id)
                .put("preconditions", "Local list").put("expected_transition", "Sorted values").put("side_effects", "None")
                .put("reversibility", "Discard result").put("authorization", "Fixture only")
            val modelSpec = JSONObject().put("goal_sha256", CollaborationSemanticGoalCoverage.source(goal).getString("goal_sha256"))
                .put("criterion_id", "quality").put("requirement", goal).put("domain", "sort").put("environment", "fixture-v1")
                .put("scope", "Three integers").put("mechanism", "Stable sort").put("uncertainty", "Untested hypothesis").put("valid_when", "Same values")
                .put("refresh_when", "Input changed").put("confounders", JSONArray().put("Synthetic fixture"))
                .put("basis", JSONArray().put(baseline)).put("state", JSONArray().put(JSONObject().put("id", "input").put("value", "3 1 2")
                    .put("basis", "Preserved fixture").put("epistemic_status", "assumed")))
                .put("actions", JSONArray().put(action("sort", "act")).put(action("defer", "defer")))
            val model = publish("model", "task_environment_model", modelSpec, "lead", 2)
            fun choice(id: String, p: Double) = JSONObject().put("action_id", id).put("reasoning", "Fixture estimate").put("uncertainty", "No real model")
                .put("resources", "One sort").put("risk", "Incorrect order").put("probabilities", JSONObject().put("descending", p))
            val forecast = publish("forecast", "action_forecast", JSONObject().put("task_environment_model", model).put("work_id", "sort-work").put("executor", "worker")
                .put("horizon", "One local computation").put("valid_until", Long.MAX_VALUE).put("decision_rationale", "Test sort behavior")
                .put("risk_tradeoff", "No side effects").put("information_value", "Direction check").put("revalidate_before_action", "Check values")
                .put("utility_unit", "fixture").put("selected_action", "sort").put("source", JSONObject().put("origin", "android_native_tool").put("tool", "fixture.sort"))
                .put("report_pointer", "").put("events", JSONArray().put(JSONObject().put("id", "descending").put("meaning", "Largest first")
                    .put("unit", "boolean").put("pointer", "/descending").put("expected", true).put("utility_if_true", 1).put("utility_if_false", -1)))
                .put("choices", JSONArray().put(choice("sort", 0.8)).put(choice("defer", 0.1))), "lead", 3)
            val criteria = JSONArray().put(JSONObject().put("id", "quality").put("requirement", goal).put("status", "open").put("evidence", JSONArray()))
            val members = CollaborationGoalLoop.initial(listOf(AgentTeamMember("fixture", AgentDeliveryMode.RESPOND, instanceId = "lead"),
                AgentTeamMember("fixture", AgentDeliveryMode.OBSERVE, instanceId = "worker")), goal)
            val record = AgentTeamExecutionRecord(AgentTeamDefinition("fixture", "fixture", members, primaryInstanceId = "lead"),
                AgentRunRequest(group, "turn", "fixture", runId = "run", goal = goal, context = mapOf(CollaborationGoalLoop.ROUND to "4", CollaborationGoalLoop.CRITERIA to criteria.toString())))
            val work = JSONObject().put("id", "sort-work").put("member", "worker").put("stage", "EXECUTE").put("assignment", "Run local sort fixture")
                .put("prediction_work", JSONObject().put("forecast", forecast))
            val admitted = CollaborationPredictionWork.plan(record, listOf(work), { workspace }, access("lead", 4))
            val sorted = listOf(3, 1, 2).sorted()
            val observed = ledger.record(access("worker", 4), "sort", "fixture.sort", "{}", JSONObject().put("format", CollaborationPredictionFeedback.FORMAT)
                .put("forecast_sha256", forecast.getString("sha256")).put("model_sha256", model.getString("sha256"))
                .put("action_id", "sort").put("work_id", "sort-work").put("environment", "fixture-v1").put("descending", sorted.first() > sorted.last()).toString(),
                40, 41, CollaborationEvidenceOrigin.ANDROID_NATIVE_TOOL)
            var offset: Int? = 0
            while (offset != null) offset = ledger.readPage(access("reviewer", 5, "outcome"), observed.getString("evidence_id"), observed.getString("sha256"), offset)!!.next
            val outcome = publish("outcome", "prediction_outcome", JSONObject().put("action_forecast", forecast).put("interpretation", "Wrong direction predicted")
                .put("confounders", "Synthetic only").put("model_correction", "Default sort is ascending").put("next_action", "New descending-sort test")
                .put("checks", JSONArray().put(JSONObject().put("event_id", "descending").put("observation", observed))), "reviewer", 5, JSONArray().put(observed))
            assertEquals("0.64", outcome.getJSONObject("host_evolution").getString("brier_sum"))
            val corrected = publish("corrected", "task_environment_model", JSONObject(modelSpec.toString()).put("previous_model", model)
                .put("feedback", JSONArray().put(outcome)).put("changed_assumptions", "Default sort direction")
                .put("why_change", "Observed ascending output").put("next_discriminating_test", "Explicit descending comparator"), "lead", 6)
            val reopened = CollaborationResearchWorkspace(context)
            val saved = reopened.read(access("lead", 7), corrected.getString("object_id"), 1)!!
            assertFalse(saved.getJSONObject("host_evolution").getBoolean("correction_verified"))
            assertEquals(outcome.getString("sha256"), saved.getJSONObject("host_evolution").getJSONArray("feedback").getJSONObject(0).getString("sha256"))
            val restored = record.copy(request = record.request.copy(context = record.request.context + (CollaborationPredictionWork.CLAIMS to admitted.claims)))
            assertEquals(admitted.claims, CollaborationPredictionWork.plan(restored, listOf(work), { reopened }, access("lead", 7)).claims)
        } finally { groups.remove(group) }
    }
}

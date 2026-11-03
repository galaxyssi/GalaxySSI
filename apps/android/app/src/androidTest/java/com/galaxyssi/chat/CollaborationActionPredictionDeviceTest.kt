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
    @Test fun forecastLocalActionErrorCorrectionAndTaskBindingSurviveReopen() = runFixture(false)

    @Test fun qualitativeProbeCorrectsAssumptionsAndRestoresWithoutInventedProbabilities() = runFixture(true)

    private fun runFixture(qualitative: Boolean) {
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
            val forecastSpec = JSONObject().put("task_environment_model", model).put("work_id", "sort-work").put("executor", "worker")
                .put("horizon", "One local computation").put("valid_until", Long.MAX_VALUE).put("decision_rationale", "Test sort behavior")
                .put("risk_tradeoff", "No side effects").put("information_value", "Direction check").put("revalidate_before_action", "Check values")
                .put("utility_unit", "fixture").put("selected_action", "sort").put("source", JSONObject().put("origin", "android_native_tool").put("tool", "fixture.sort"))
                .put("report_pointer", "").put("events", JSONArray().put(JSONObject().put("id", "descending").put("meaning", "Largest first")
                    .put("unit", "boolean").put("pointer", "/descending").put("expected", true).put("utility_if_true", 1).put("utility_if_false", -1)))
                .put("choices", JSONArray().put(choice("sort", 0.8)).put(choice("defer", 0.1)))
            if (qualitative) {
                fun method(id: String, assignment: String): JSONObject {
                    val value = JSONObject().put("purpose", "Continue after local measurement").put("domain", "sort")
                        .put("bottleneck", "Unknown sort direction").put("change_rationale", "Measured branch")
                        .put("applies_when", "This local fixture").put("avoid_when", "Other inputs").put("risks", "Synthetic only")
                        .put("expected_gain", "Correct next action").put("falsifier", "Wrong branch")
                        .put("dimensions", JSONArray().put("verification")).put("roles", JSONArray().put("worker").put("reviewer"))
                        .put("inputs", JSONArray().put("direction")).put("steps", JSONArray()
                            .put(JSONObject().put("id", "execute").put("role", "worker").put("stage", "EXECUTE")
                                .put("assignment", assignment).put("depends_on", JSONArray()))
                            .put(JSONObject().put("id", "check").put("role", "reviewer").put("stage", "VERIFY")
                                .put("assignment", "Independently check the local result").put("depends_on", JSONArray().put("execute"))
                                .put("independent_review", true)))
                    return publish(id, "workflow_method", value, "lead", 2)
                }
                val retain = method("retain-method", "Retain the measured descending order")
                val repair = method("repair-method", "Repair the comparator before checking again")
                fun branch(id: String, descending: Boolean, method: JSONObject) = JSONObject().put("id", id)
                    .put("rationale", "Result changes the next method").put("when_events", JSONObject().put("descending", descending))
                    .put("method", method).put("roles", JSONObject().put("worker", "worker").put("reviewer", "lead"))
                    .put("inputs", JSONObject()).put("observed_inputs", JSONObject().put("direction", "/descending"))
                forecastSpec.getJSONArray("choices").getJSONObject(0).put("continuations", JSONArray()
                    .put(branch("retain", true, retain)).put(branch("repair", false, repair)))
                forecastSpec.put("prediction_mode", "qualitative").remove("utility_unit")
                forecastSpec.getJSONArray("events").getJSONObject(0).apply { remove("utility_if_true"); remove("utility_if_false") }
                repeat(2) { index -> forecastSpec.getJSONArray("choices").getJSONObject(index).apply {
                    remove("probabilities")
                    put("expectations", JSONObject().put("descending", if (index == 0) "expected" else "unknown"))
                } }
                forecastSpec.put("hypothesis_test", JSONObject().put("question", "What is the actual sort direction?")
                    .put("assumptions", "Two fixture hypotheses").put("prediction_basis", "Direction must be measured")
                    .put("misspecification_check", "Keep unexpected outcomes")
                    .put("hypotheses", JSONArray().put(JSONObject().put("id", "ascending").put("claim", "Default ascending"))
                        .put(JSONObject().put("id", "descending").put("claim", "Default descending")))
                    .put("event_ids", JSONArray().put("descending")).put("predictions", JSONObject()
                        .put("sort", JSONObject().put("ascending", JSONObject().put("descending", "not_expected"))
                            .put("descending", JSONObject().put("descending", "expected")))
                        .put("defer", JSONObject().put("ascending", JSONObject().put("descending", "unknown"))
                            .put("descending", JSONObject().put("descending", "unknown")))))
            }
            val forecast = publish("forecast", "action_forecast", forecastSpec, "lead", 3)
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
            val feedback = workspace.read(access("reviewer", 6), outcome.getString("object_id"), outcome.getInt("revision"))!!
                .getJSONObject("host_evolution")
            if (qualitative) {
                assertTrue(feedback.isNull("brier_sum"))
                assertEquals("contradicted", feedback.getJSONArray("checks").getJSONObject(0).getString("prediction_check"))
                val compared = feedback.getJSONObject("hypothesis_test").getJSONArray("hypotheses")
                assertEquals("consistent_with_observation", compared.getJSONObject(0).getString("state"))
                assertEquals("contradicted", compared.getJSONObject(1).getString("state"))
                assertTrue(feedback.getJSONObject("hypothesis_test").isNull("posterior"))
            } else assertEquals("0.64", feedback.getString("brier_sum"))
            val corrected = publish("corrected", "task_environment_model", JSONObject(modelSpec.toString()).put("previous_model", model)
                .put("feedback", JSONArray().put(outcome)).put("changed_assumptions", "Default sort direction")
                .put("why_change", "Observed ascending output").put("next_discriminating_test", "Explicit descending comparator"), "lead", 6)
            val reopened = CollaborationResearchWorkspace(context)
            val saved = reopened.read(access("lead", 7), corrected.getString("object_id"), 1)!!
            assertFalse(saved.getJSONObject("host_evolution").getBoolean("correction_verified"))
            assertEquals(outcome.getString("sha256"), saved.getJSONObject("host_evolution").getJSONArray("feedback").getJSONObject(0).getString("sha256"))
            val restored = record.copy(request = record.request.copy(context = record.request.context + (CollaborationPredictionWork.CLAIMS to admitted.claims)))
            assertEquals(admitted.claims, CollaborationPredictionWork.plan(restored, listOf(work), { reopened }, access("lead", 7)).claims)
            if (qualitative) {
                val binding = JSONObject(CollaborationPredictionWork.context(admitted.work.single()).getValue(CollaborationPredictionWork.TASK))
                assertEquals("qualitative", binding.getString("prediction_mode"))
                assertEquals("declared_qualitative_comparison", binding.getJSONObject("hypothesis_test").getString("state"))
                val request = JSONObject().put(CollaborationProbeContinuation.FIELD, JSONObject().put("outcome", outcome))
                val expanded = CollaborationWorkflowInstantiation.expand(JSONArray().put(request), { reopened }, access("lead", 7))
                    .let { array -> (0 until array.length()).map(array::getJSONObject) }
                val next = CollaborationWorkflowWork.plan(record, expanded, { reopened }, access("lead", 7))
                assertEquals(2, next.work.size)
                assertTrue(next.work.first().getString("assignment").contains("Repair"))
                val continuation = JSONObject(CollaborationWorkflowWork.context(next.work.first()).getValue(CollaborationWorkflowWork.TASK))
                assertEquals("repair", continuation.getJSONObject(CollaborationProbeContinuation.ORIGIN).getString("branch_id"))
                assertFalse(continuation.getJSONObject("inputs").getBoolean("direction"))
                val resumed = record.copy(request = record.request.copy(context = record.request.context + (CollaborationWorkflowWork.CLAIMS to next.claims)))
                assertEquals(next.claims, CollaborationWorkflowWork.plan(resumed, expanded, { CollaborationResearchWorkspace(context) }, access("lead", 7)).claims)
            }
        } finally { groups.remove(group) }
    }
}

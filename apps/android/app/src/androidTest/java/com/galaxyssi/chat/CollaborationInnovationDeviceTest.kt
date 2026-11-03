package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import kotlinx.coroutines.runBlocking
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** Local synthetic execution only. No model, network, original research or contact actions. */
@RunWith(AndroidJUnit4::class)
class CollaborationInnovationDeviceTest {
    private val context = InstrumentationRegistry.getInstrumentation().targetContext
    private val goal = "Compare local parsing strategies"
    private val criteria get() = JSONArray().put(JSONObject().put("id", "quality").put("requirement", goal)
        .put("status", "open").put("evidence", JSONArray()))

    @Test fun actualLocalComparisonRetainsOnlyScopedEvidenceAndReopensWithoutReexecution() = runBlocking {
        val group = "innovation-device-${UUID.randomUUID()}"
        val groups = CollaborationGroupStore(context)
        val people = listOf("author", "planner", "executor", "analyst", "reviewer")
        groups.update(group) { it.copy(members = people.map { id -> CollaborationMember(id, id, "fixture", "Fixture") }, coordinatorId = "planner") }
        val database = AgentEncryptedDatabase(context, "innovation-fixture-$group")
        try {
            val workspace = CollaborationResearchWorkspace(context)
            val ledger = CollaborationEvidenceLedger(context)
            fun access(person: String, round: Long, node: String = person) = CollaborationWorkspaceAccess(group, "run", "turn", round, node, person)
            fun publish(id: String, kind: String, value: JSONObject, person: String, round: Long, now: Long,
                        refs: JSONArray = JSONArray(), parents: JSONArray = JSONArray()): JSONObject {
                val raw = JSONObject().put("format", CollaborationResearchArtifact.FORMAT).put("summary", "Local synthetic innovation")
                    .put("findings", JSONArray()).put("candidates", JSONArray()).put("workspace", JSONArray().put(JSONObject()
                        .put("id", id).put("kind", kind).put("title", id).put("body", JSONObject().put("content", "Synthetic fixture only").put(kind, value))
                        .put("observations", refs).put("parents", parents))).toString()
                return workspace.publish(access(person, round, id), raw, now)
            }
            fun accepted(receipt: JSONObject): JSONObject {
                assertEquals(receipt.toString(), "recorded", receipt.getString("status"))
                return receipt.getJSONArray("revisions").getJSONObject(0)
            }
            fun read(reader: CollaborationWorkspaceAccess, refs: JSONArray) { repeat(refs.length()) { i ->
                val ref = refs.getJSONObject(i); var offset: Int? = 0
                while (offset != null) offset = ledger.readPage(reader, ref.getString("evidence_id"), ref.getString("sha256"), offset)!!.next
            } }
            val baseline = accepted(publish("baseline", "artifact", JSONObject().put("method", "Parse once per query"), "author", 1, 10))
            val opportunity = accepted(publish("opportunity", "innovation_opportunity", JSONObject()
                .put("goal_sha256", CollaborationSemanticGoalCoverage.source(goal).getString("goal_sha256"))
                .put("criterion_id", "quality").put("requirement", goal).put("question", "Can one immutable parse serve all queries?")
                .put("unmet_need", "Duplicate parsing").put("expected_benefit", "Fewer parse operations").put("constraints", "Equal answers")
                .put("null_hypothesis", "Caching gives no useful gain").put("discriminating_test", "Count parses and compare answers")
                .put("uncertainty", "Only a local fixture").put("alternative_routes", JSONArray().put("Batch queries"))
                .put("drivers", JSONArray().put(JSONObject().put("id", "duplication").put("kind", "limitation").put("sources", JSONArray().put(baseline))
                    .put("why", "Same input is parsed repeatedly").put("what_would_change", "Changing input"))), "author", 2, 20))
            val ideaSpec = JSONObject("""{"origin":"limitation","hypothesis":"Reuse one parse","mechanism":"Immutable indexed data",
                "difference":"Avoid repeated parsing","prior_art":"Fixture control only","novelty_scope":"not_checked","falsifier":"Incorrect answers or no gain",
                "domain":"fixture","applies_when":"Identical JSON input","risks":"Stale data","alternatives":["Batch all queries"],
                "predictions":[{"id":"p1","statement":"Same answer with fewer parses","test":"Count actual parser calls"}]}""")
                .put("innovation_opportunity", opportunity)
            val idea = accepted(publish("idea", "innovation", ideaSpec, "author", 3, 30, parents = JSONArray().put(opportunity)))
            fun case(id: String, purpose: String, direction: String) = JSONObject().put("id", id).put("purpose", purpose)
                .put("prediction", "Original measured comparison").put("metric", id).put("direction", direction).put("minimum_gain", 1)
                .put("tolerance", 0).put("repetitions", 1)
            val cases = JSONArray().put(case("parses", "target", "minimize").put("dimension", "value"))
                .put(case("correct", "feasibility", "maximize").put("threshold", 4)).put(case("legacy", "regression", "maximize"))
            val plan = accepted(publish("plan", "experiment_plan", JSONObject().put("innovation", idea).put("baseline", baseline)
                .put("prediction_id", "p1").put("method", "Same four lookups").put("environment", "s26u-local-json")
                .put("budget_unit", "parses").put("budget_limit", 4).put("source", JSONObject().put("origin", "android_native_tool").put("tool", "fixture.parse_compare"))
                .put("report_pointer", "").put("cases", cases), "planner", 4, 100))
            val members = CollaborationGoalLoop.initial(listOf(AgentTeamMember("fixture", AgentDeliveryMode.RESPOND, instanceId = "planner"),
                AgentTeamMember("fixture", AgentDeliveryMode.OBSERVE, instanceId = "executor")), goal).map { it.copy(context = it.context +
                mapOf("collaboration_group_id" to group, CollaborationTeamOrganization.ENABLED to "0")) }
            val run = "innovation-run-$group"
            fun store() = EncryptedAgentTeamExecutionStore(database, candidateWorkspace = { CollaborationResearchWorkspace(context) })
            fun report(work: JSONArray) = JSONObject().put("format", CollaborationGoalLoop.FORMAT).put("summary", "Local comparison")
                .put("decision", "continue").put("criteria", criteria).put("work", work).put("blockers", JSONArray()).toString()
            val work = JSONObject().put("id", "compare").put("member", "executor").put("stage", "EXECUTE").put("assignment", "Run local fixture")
                .put("innovation_work", JSONObject().put("opportunity", opportunity).put("innovation", idea).put("plan", plan)
                    .put("phase", "experiment").put("expected_output", "Original measurements").put("why_now", "Verify the prediction"))
            store().create(AgentTeamDefinition("fixture", "fixture", members, primaryInstanceId = "planner"),
                AgentRunRequest(group, "new-turn", "task", runId = run, goal = goal, context = mapOf(CollaborationGoalLoop.ROUND to "7")))
            store().append(AgentSubagentEvent(1, run, "planner", AgentSubagentEventKinds.CHILD_SUCCEEDED, childStatus = AgentSubagentStatus.SUCCEEDED,
                result = AgentSubagentChildResult(run, "planner", run, 1, AgentSubagentStatus.SUCCEEDED, report(JSONArray().put(work)))))
            store().append(AgentSubagentEvent(2, run, kind = AgentSubagentEventKinds.SUPERVISOR_SUCCEEDED, runStatus = AgentSubagentRunStatus.SUCCEEDED))
            assertTrue(store().advanceGoal(run, "planner", 150, true))
            val checkpoint = store().resumeCheckpoint(run)!!
            val selected = checkpoint.definition.members.single { CollaborationInnovationWork.TASK in it.context }
            val observations = JSONArray()
            var measuredReport: JSONObject? = null
            var executions = 0
            AgentTeamExecutionRuntime(store(), AgentSubagentLimits(maxConcurrency = 1)).use { runtime ->
                runtime.resume(checkpoint) { execution ->
                    if (execution.member.memberId != selected.memberId) AgentSubagentOutput(report(JSONArray())) else {
                        executions++
                        val binding = JSONObject(execution.member.context.getValue(CollaborationInnovationWork.TASK))
                        assertEquals(plan.getString("sha256"), binding.getJSONObject("work").getJSONObject("plan").getString("sha256"))
                        assertFalse(binding.getBoolean("grants_permissions"))
                        val samples = JSONArray()
                        for (variant in listOf("baseline", "candidate")) {
                            var parses = 0
                            val input = "{\"a\":2,\"b\":3,\"c\":5,\"d\":7}"
                            fun parse(): JSONObject { parses++; return JSONObject(input) }
                            val cached = if (variant == "candidate") parse() else null
                            val expected = mapOf("a" to 2, "b" to 3, "c" to 5, "d" to 7)
                            val correct = expected.count { (key, value) -> (cached ?: parse()).getInt(key) == value }
                            for ((id, value) in mapOf("parses" to parses, "correct" to correct, "legacy" to correct)) samples.put(JSONObject()
                                .put("case_id", id).put("variant", variant).put("variant_sha256", (if (variant == "baseline") baseline else idea).getString("sha256"))
                                .put("metric", id).put("repetition", 1).put("value", value).put("budget_used", parses))
                        }
                        val measured = JSONObject().put("format", CollaborationEvolutionExperiment.FORMAT).put("plan_sha256", plan.getString("sha256"))
                            .put("environment", "s26u-local-json").put("budget_unit", "parses").put("measurements", samples)
                        measuredReport = measured
                        observations.put(ledger.record(access("executor", 5), "local-trial", "fixture.parse_compare", "{}", measured.toString(),
                            200, 201, CollaborationEvidenceOrigin.ANDROID_NATIVE_TOOL))
                        AgentSubagentOutput("Actual local comparison recorded")
                    }
                }.await()
            }
            assertEquals(1, executions)
            assertTrue(store().advanceGoal(run, checkpoint.definition.primaryMemberId, 500, true))
            val restored = store().resumeCheckpoint(run)!!
            assertEquals("succeeded", JSONObject(restored.request.context.getValue(CollaborationInnovationWork.OUTCOMES).toString())
                .getJSONObject(selected.memberId).getString("status"))
            assertTrue(restored.definition.members.none { CollaborationInnovationWork.TASK in it.context })
            read(access("analyst", 6, "result"), observations)
            val result = accepted(publish("result", "experiment_result", JSONObject().put("plan", plan).put("interpretation", "Fewer parses at equal correctness")
                .put("limitations", "Synthetic fixture, not model innovation"), "analyst", 6, 300, observations))
            assertEquals("measured_improvement", result.getJSONObject("host_evolution").getString("state"))
            val broken = JSONObject(requireNotNull(measuredReport).toString())
            val lost = mapOf("a" to 2, "b" to 3, "c" to 5, "d" to 7).count { (key, value) -> JSONObject().optInt(key, -1) == value }
            val brokenSamples = broken.getJSONArray("measurements")
            repeat(brokenSamples.length()) { i -> brokenSamples.getJSONObject(i).let {
                if (it.getString("variant") == "candidate" && it.getString("case_id") == "legacy") it.put("value", lost)
            } }
            val badRefs = JSONArray().put(ledger.record(access("executor", 5), "broken-local-trial", "fixture.parse_compare", "{}",
                broken.toString(), 202, 203, CollaborationEvidenceOrigin.ANDROID_NATIVE_TOOL))
            read(access("analyst", 6, "regressed"), badRefs)
            val regressed = accepted(publish("regressed", "experiment_result", JSONObject().put("plan", plan)
                .put("interpretation", "Deliberately broken lookup loses legacy answers").put("limitations", "Local negative fixture"),
                "analyst", 6, 305, badRefs))
            assertEquals("regressed", regressed.getJSONObject("host_evolution").getString("state"))
            assertFalse(regressed.getJSONObject("host_evolution").getBoolean("eligible_for_retention"))
            val prior = ledger.record(access("analyst", 7), "prior-art", "fixture.read_baseline", "{}", "{\"method\":\"parse per query\"}",
                310, 311, CollaborationEvidenceOrigin.ANDROID_NATIVE_TOOL)
            observations.put(prior)
            val review = JSONObject().put("innovation", idea).put("decision", "retain").put("rationale", "Scoped fixture only")
                .put("novelty", JSONObject().put("outcome", "distinguished_in_searched_scope").put("search_scope", "Fixture baseline only")
                    .put("coverage_gaps", "No real prior-art research").put("rationale", "Different measured operation count")
                    .put("closest_work", JSONArray().put(JSONObject().put("observation", prior).put("overlap", "Same JSON data")
                        .put("difference", "One parse").put("significance", "Local operation reduction"))))
                .put("results", JSONArray().put(result)).put("feasibility_scope", "Four correct answers").put("value_scope", "Three fewer parses")
                .put("limitations", "No worldwide novelty claim").put("unresolved", JSONArray()).put("next_action", "Real dataset tests remain")
            read(access("author", 8, "self-review"), observations)
            assertEquals("rejected", publish("self-review", "innovation_assessment", review, "author", 8, 400, observations).getString("status"))
            read(access("reviewer", 8, "review"), observations)
            val assessment = accepted(publish("review", "innovation_assessment", review, "reviewer", 8, 400, observations))
            assertFalse(assessment.getJSONObject("host_evolution").getBoolean("novelty_certified"))
            val failedReview = JSONObject(review.toString()).put("results", JSONArray().put(regressed))
            val failedRefs = JSONArray().put(badRefs.getJSONObject(0)).put(prior)
            read(access("reviewer", 8, "regression-review"), failedRefs)
            assertEquals("rejected", publish("regression-review", "innovation_assessment", failedReview,
                "reviewer", 8, 401, failedRefs).getString("status"))
            val later = access("reviewer", 0).copy(runId = "future", turnId = "future")
            val saved = CollaborationResearchWorkspace(context).read(later, assessment.getString("object_id"), 1)!!
            assertEquals("eligible_for_scoped_innovation_use", saved.getJSONObject("host_evolution").getString("state"))
            assertEquals(1, executions)
        } finally { database.clear(); groups.remove(group) }
    }
}

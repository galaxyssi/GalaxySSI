package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import com.galaxyssi.chat.CollaborationActionPrediction.FORECAST
import com.galaxyssi.chat.CollaborationActionPrediction.OUTCOME
import com.galaxyssi.chat.CollaborationProbeContinuation.BRANCHES
import com.galaxyssi.chat.CollaborationProbeContinuation.FIELD
import com.galaxyssi.chat.CollaborationProbeContinuation.ORIGIN

class CollaborationProbeContinuationTest {
    private class Fixture {
        val t = CollaborationActionPredictionTest.Fixture()
        val f = t.f
        val spec = JSONObject(CollaborationWorkflowTest.Fixture().spec.toString())
        val method = f.ref(f.publish("next-method", CollaborationWorkflowMethod.KIND, spec, round = 6, now = 450))
        val other = f.ref(f.publish("alternative-method", CollaborationWorkflowMethod.KIND, JSONObject(spec.toString()).apply {
            getJSONArray("steps").getJSONObject(0).put("assignment", "Measure cache validity with a different method")
        }, round = 6, now = 451))
        fun branch(id: String, fast: Boolean, target: JSONObject = method) = JSONObject().put("id", id).put("rationale", "Observed probe changes actual work")
            .put("when_events", JSONObject().put("fast", fast)).put("method", target)
            .put("roles", JSONObject().put("worker", "peer").put("reviewer", "lead"))
            .put("inputs", JSONObject()).put("observed_inputs", JSONObject().put("dataset", "/parse_count"))
        val forecastSpec = JSONObject(t.forecastSpec.toString()).apply {
            getJSONArray("choices").getJSONObject(0).put(BRANCHES, JSONArray().put(branch("reuse", true)).put(branch("recheck", false, other)))
        }
        val forecast by lazy { f.ref(f.publish("planned-probe", FORECAST, forecastSpec, round = 8, now = 550)) }
        fun report(count: Int = 1) = t.report().put("forecast_sha256", forecast.getString("sha256")).put("parse_count", count)
        fun outcome(count: Int = 1, change: (JSONObject) -> Unit = {}) = f.ref(t.outcome(t.observe(report(count).apply(change))) { it.put(FORECAST, forecast) })
        fun request(outcome: JSONObject) = JSONObject().put(FIELD, JSONObject().put("outcome", outcome))
        fun expand(outcome: JSONObject, access: CollaborationWorkspaceAccess = f.access(), milestones: Map<String, JSONObject> = emptyMap()): List<JSONObject> {
            val expanded = CollaborationWorkflowInstantiation.expand(JSONArray().put(request(outcome)), { f.reopen() }, access, milestones)
            return (0 until expanded.length()).map(expanded::getJSONObject)
        }
        fun admit(outcome: JSONObject, record: AgentTeamExecutionRecord = t.record()) =
            CollaborationWorkflowWork.plan(record, expand(outcome), { f.reopen() }, f.access())
        fun binding(plan: CollaborationWorkflowWork.Plan) = JSONObject(CollaborationWorkflowWork.context(plan.work.first()).getValue(CollaborationWorkflowWork.TASK))
    }

    @Test fun prospectiveProbeSelectsRealMethodsAndOriginalInputs() {
        val fast = Fixture(); val fastResult = fast.outcome(); val accepted = fast.admit(fastResult)
        val slow = Fixture(); val slowResult = slow.outcome(4); val alternate = slow.admit(slowResult)
        assertEquals(2, accepted.work.size); assertEquals(2, alternate.work.size)
        assertNotEquals(accepted.work.first().getString("assignment"), alternate.work.first().getString("assignment"))
        val origin = fast.binding(accepted).getJSONObject(ORIGIN)
        assertEquals("reuse", origin.getString("branch_id")); assertEquals("recheck", slow.binding(alternate).getJSONObject(ORIGIN).getString("branch_id"))
        assertEquals(fastResult.getString("sha256"), origin.getJSONObject("outcome").getString("sha256"))
        assertEquals("worker", origin.getString("role")); assertEquals("peer", origin.getString("recipient"))
        assertFalse(origin.has("roles"))
        assertEquals(1, fast.binding(accepted).getJSONObject("inputs").getInt("dataset"))
        assertFalse(origin.getBoolean("quality_improved"))
    }

    @Test fun overlappingBranchesCanRunTogetherWithoutAForcedWinner() {
        val x = Fixture()
        x.forecastSpec.getJSONArray("choices").getJSONObject(0).getJSONArray(BRANCHES).getJSONObject(1)
            .put("when_events", JSONObject().put("correct", true))
        val plan = x.admit(x.outcome())
        assertEquals(4, plan.work.size)
        assertEquals(4, plan.work.map { it.getString("id") }.distinct().size)
        assertEquals(2, x.binding(plan).getJSONObject(ORIGIN).getInt("matched_branch_count"))
    }

    @Test fun failedMissingStaleAndUnmatchedOutcomesRequestReplanningWithoutFallback() {
        for (kind in listOf("failed", "missing", "stale", "unmatched")) {
            val x = Fixture()
            if (kind == "stale") x.forecastSpec.put("valid_until", 575)
            if (kind == "unmatched") x.forecastSpec.getJSONArray("choices").getJSONObject(0).getJSONArray(BRANCHES).remove(1)
            val outcome = x.outcome(4) {
                if (kind == "failed") it.put("status", "failed")
                if (kind == "missing") it.remove("parse_count")
            }
            val failure = runCatching { x.admit(outcome) }.exceptionOrNull()?.message.orEmpty()
            assertTrue("$kind: $failure", failure.contains("No measured continuation matches") && failure.contains("Branch states"))
        }
    }

    @Test fun malformedProspectiveBranchesCannotPublish() {
        for (kind in listOf("event", "boolean", "duplicate", "method", "role", "alias", "input", "pointer", "override")) {
            val x = Fixture(); val branches = x.forecastSpec.getJSONArray("choices").getJSONObject(0).getJSONArray(BRANCHES)
            val row = branches.getJSONObject(0)
            when (kind) {
                "event" -> row.put("when_events", JSONObject().put("invented", true))
                "boolean" -> row.getJSONObject("when_events").put("fast", "true")
                "duplicate" -> branches.put(JSONObject(row.toString()))
                "method" -> row.put("method", x.t.model)
                "role" -> row.getJSONObject("roles").remove("reviewer")
                "alias" -> row.getJSONObject("roles").put("worker", "recruit:new")
                "input" -> row.getJSONObject("inputs").put("dataset", 100)
                "pointer" -> row.getJSONObject("observed_inputs").put("dataset", "~9")
                else -> row.put("tool_policy", "all")
            }
            assertEquals(kind, "rejected", x.f.publish("bad", FORECAST, x.forecastSpec, round = 8, now = 550).getString("status"))
        }
    }

    @Test fun recipientsConditionsAndSourceCannotBeRewrittenAfterObservingResult() {
        for (kind in listOf("recipient", "branch", "origin", "execution", "source")) {
            val x = Fixture(); val outcome = x.outcome(); val work = x.expand(outcome)
            work.forEach { item ->
                val use = item.getJSONObject(CollaborationWorkflowWork.FIELD)
                when (kind) {
                    "recipient" -> if (use.getString("step_id") == "parse") item.put("member", "lead")
                    "branch" -> use.getJSONObject(ORIGIN).put("branch_id", "recheck")
                    "origin" -> use.getJSONObject(ORIGIN).getJSONObject("forecast").put("sha256", "0".repeat(64))
                    "execution" -> use.put("execution_id", "fresh-attempt")
                    else -> use.getJSONObject(CollaborationWorkflowObservations.FIELD).getJSONObject("dataset").put("pointer", "/correct")
                }
            }
            assertTrue(kind, runCatching { CollaborationWorkflowWork.plan(x.t.record(), work, { x.f.reopen() }, x.f.access()) }.isFailure)
        }
    }

    @Test fun replayPinsOutcomeAndDoesNotRepeatFinishedSteps() {
        val x = Fixture(); val outcome = x.outcome(); val plan = x.admit(outcome)
        val restored = x.t.record().let { it.copy(request = it.request.copy(context = it.request.context + mapOf(
            CollaborationWorkflowWork.CLAIMS to plan.claims, CollaborationGoalLoop.FINISHED_WORK to JSONArray().put(plan.work.first().getString("id")).toString(),
            CollaborationGoalLoop.FINISHED_AUTHORS to JSONObject().put(plan.work.first().getString("id"), "peer").toString()))) }
        assertEquals(plan.claims, x.admit(outcome, restored).claims)
        val next = CollaborationGoalLoop.advance(x.f.completed(restored, "lead", x.f.report(listOf(x.request(outcome))).toString(), true),
            "lead", 1000, false, candidateWorkspace = { x.f.reopen() })!!
        val nodes = next.definition.members.filter { CollaborationWorkflowWork.TASK in it.context }
        assertEquals(1, nodes.size)
        assertTrue(JSONObject(nodes.single().context.getValue(CollaborationWorkflowWork.TASK)).has(ORIGIN))
        val another = x.f.ref(x.t.outcome(x.t.observe(x.report()), id = "second-outcome") { it.put(FORECAST, x.forecast) })
        assertTrue(runCatching { x.admit(another, restored) }.isFailure)
    }

    @Test fun continuationCannotMoveIntoAnotherTaskOrGoal() {
        for (kind in listOf("run", "turn", "goal", "criterion")) {
            val x = Fixture(); val outcome = x.outcome(); val base = x.t.record()
            val request = when (kind) {
                "run" -> base.request.copy(runId = "other")
                "turn" -> base.request.copy(messageId = "other")
                "goal" -> base.request.copy(goal = "Other goal")
                else -> base.request.copy(context = base.request.context + (CollaborationGoalLoop.CRITERIA to "[]"))
            }
            assertTrue(kind, runCatching { x.admit(outcome, base.copy(request = request)) }.isFailure)
        }
    }

    @Test fun livePlannerAdmitsMeasuredBranchesWhileUnrelatedWorkContinues() {
        val x = Fixture(); val outcome = x.outcome(); val base = x.t.record()
        val people = base.definition.members.map { it.copy(deliveryMode = AgentDeliveryMode.IGNORE) }
        val slow = people.last().copy(instanceId = "slow", deliveryMode = AgentDeliveryMode.OBSERVE,
            context = people.last().context + mapOf(CollaborationGoalLoop.ROSTER to "false", CollaborationGoalLoop.WORK_ID to "unrelated"))
        val planner = people.first().copy(instanceId = "planner", deliveryMode = AgentDeliveryMode.OBSERVE,
            context = people.first().context + mapOf(CollaborationGoalLoop.ROSTER to "false", CollaborationLiveGraph.PLANNER to "1"))
        val final = people.first().copy(instanceId = "final", deliveryMode = AgentDeliveryMode.RESPOND,
            context = people.first().context + (CollaborationGoalLoop.ROSTER to "false"))
        val record = base.copy(definition = base.definition.copy(members = people + slow + planner + final, primaryInstanceId = "final"))
        val report = JSONObject().put("format", CollaborationLiveGraph.FORMAT).put("summary", "Continue from probe")
            .put("work", JSONArray().put(x.request(outcome)))
        val next = CollaborationLiveGraph.update(x.f.completed(record, "planner", report.toString()), setOf("planner"), 1000, { x.f.reopen() })
        val nodes = next.definition.members.filter { CollaborationWorkflowWork.TASK in it.context }
        assertEquals(next.request.context.toString(), 2, nodes.size)
        assertTrue(nodes.none { "slow" in it.dependsOnAgentIds })
        assertEquals(next.definition, CollaborationLiveGraph.update(next, setOf("planner"), 2000, { x.f.reopen() }).definition)
    }

    @Test fun manyAlternativeBranchesUseCompactTaskBindingsWithoutATopKCutoff() {
        val x = Fixture()
        x.forecastSpec.getJSONArray("choices").getJSONObject(0).put(BRANCHES,
            JSONArray((0 until 500).map { x.branch("branch-$it", true) }))
        val plan = x.admit(x.outcome())
        assertEquals(1000, plan.work.size)
        val origin = x.binding(plan).getJSONObject(ORIGIN)
        assertEquals(500, origin.getInt("matched_branch_count"))
        assertEquals(1, origin.getJSONArray("conditions").length())
        assertFalse(origin.has("branch_states"))
    }

    @Test fun sameRoundOriginalEvidenceNeedsAndKeepsMilestoneGrant() {
        val x = Fixture(); val sourceAccess = x.f.access("peer", 9, "probe-node")
        val original = x.f.ledger.record(sourceAccess, "same-round", "fixture.predict", "{}", x.report().toString(), 600, 601,
            CollaborationEvidenceOrigin.ANDROID_NATIVE_TOOL)
        val reviewer = x.f.access("reviewer", 9, "outcome-node").copy(dependencyNodes = setOf("probe-node"))
        val refs = JSONArray().put(original); x.f.read(reviewer, refs)
        val spec = JSONObject().put(FORECAST, x.forecast).put("interpretation", "Fixture measurement").put("confounders", "Synthetic")
            .put("model_correction", "None").put("next_action", "Follow prospective branches").put("checks", JSONArray()
                .put(JSONObject().put("event_id", "correct").put("observation", original)).put(JSONObject().put("event_id", "fast").put("observation", original)))
        val outcome = x.f.ref(x.f.workspace.publish(reviewer, x.f.raw("same-outcome", OUTCOME, spec, refs), 700))
        val access = x.f.access(round = 9).copy(dependencyNodes = setOf("probe-node", "outcome-node"))
        val request = x.request(outcome)
        assertTrue(runCatching { CollaborationWorkflowInstantiation.expand(JSONArray().put(request), { x.f.reopen() }, access) }.isFailure)
        val token = "c".repeat(64)
        val milestone = JSONObject().put("token", token).put("person_id", "peer").put("producer_node", "probe-node")
            .put("grants", JSONArray().put(CollaborationMilestoneDispatch.grant(original)))
        request.getJSONObject(FIELD).put("milestone", token)
        val expanded = CollaborationWorkflowInstantiation.expand(JSONArray().put(request), { x.f.reopen() }, access, mapOf(token to milestone))
        repeat(expanded.length()) { assertEquals(token, expanded.getJSONObject(it).getJSONArray(CollaborationMilestoneDispatch.USES).getString(0)) }
        milestone.put("grants", JSONArray())
        assertTrue(runCatching { CollaborationWorkflowInstantiation.expand(JSONArray().put(request), { x.f.reopen() }, access, mapOf(token to milestone)) }.isFailure)
    }
}

package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.HOST
import com.galaxyssi.chat.CollaborationWorkflowSelection.KIND
import com.galaxyssi.chat.CollaborationWorkflowSelection.FIELD
import com.galaxyssi.chat.CollaborationWorkflowSelection.DECISION

class CollaborationWorkflowSelectionTest {
    internal class Fixture {
        val t = CollaborationWorkflowTest.Fixture()
        val f = t.f
        val candidate = f.ref(f.publish("conditional-candidate", CollaborationWorkflowMethod.KIND, JSONObject(t.spec.toString())
            .put("steps", JSONArray().put(t.step("index", "worker")).put(t.step("validate", "reviewer", listOf("index"), true))), round = 6))
        fun idea(method: JSONObject) = JSONObject(f.ideaSpec.toString()).apply { remove(CollaborationInnovationValidation.OPPORTUNITY) }
            .put(CollaborationWorkflowMethod.KIND, method)
        val before = f.ref(f.publish("selection-before", "innovation", idea(t.method), round = 7))
        val after = f.ref(f.publish("selection-after", "innovation", idea(candidate), round = 7))
        val planSpec = JSONObject(f.spec.toString()).put("baseline", before).put("innovation", after)
            .put("cases", JSONArray().put(f.case("quality", "target")).put(f.case("retained", "regression")))
            .put(CollaborationWorkflowMethod.COMPARISON, JSONObject().put("dataset", f.baseline).put("controlled_conditions", "Same fixture")
                .put("quality_oracle", "Exact fixture score").put("cost_accounting", "Local test operations").put("selection_bias", "Synthetic only"))
        val plan = f.ref(f.publish("selection-plan", "experiment_plan", planSpec, round = 8, now = 100))
        val refs = JSONArray()
        val result: JSONObject
        val lesson: JSONObject
        init {
            val samples = JSONArray()
            for (variant in listOf("baseline", "candidate")) for (case in listOf("quality", "retained")) {
                val old = variant == "baseline"
                samples.put(JSONObject().put("case_id", case).put("variant", variant).put("variant_sha256", (if (old) before else after).getString("sha256"))
                    .put("workflow_sha256", (if (old) t.method else candidate).getString("sha256")).put("dataset_sha256", f.baseline.getString("sha256"))
                    .put("metric", "score").put("repetition", 1).put("budget_used", 1).put("value", if (old) 1 else 2))
            }
            val report = JSONObject().put("format", CollaborationEvolutionExperiment.FORMAT).put("plan_sha256", plan.getString("sha256"))
                .put("environment", "fixture").put("budget_unit", "operations").put("measurements", samples)
            refs.put(f.ledger.record(f.access("executor", 9), "conditional-trial", "fixture.compare", "{}", report.toString(), 200, 201,
                CollaborationEvidenceOrigin.ANDROID_NATIVE_TOOL))
            f.read(f.access("analyst", 10, "selection-result"), refs)
            result = f.ref(f.publish("selection-result", "experiment_result", JSONObject().put("plan", plan).put("interpretation", "Synthetic measurement")
                .put("limitations", "Not an efficacy experiment"), "analyst", 10, 300, refs))
            f.read(f.access("arbiter", 11, "selection-lesson"), refs)
            lesson = f.ref(f.publish("selection-lesson", "capability_lesson", JSONObject().put("result", result).put("decision", "retain")
                .put("rationale", "Fixture improvement").put("applies_when", "Immutable repeated input").put("avoid_when", "Mutable input")
                .put("procedure", "Use index").put("transfer_test", "Test unknown inputs").put("rollback", before), "arbiter", 11, 400, refs))
        }
        fun condition(id: String, pointer: String, operator: String, value: Any) = JSONObject().put("id", id).put("input", "dataset")
            .put("pointer", pointer).put("operator", operator).put("value", value).put("rationale", "Test an observable input condition")
        val ruleSpec = JSONObject().put("purpose", "Choose an indexing method").put("domain", "fixture").put("lesson", lesson)
            .put("condition_basis", "Fixture-only comparison, proposed applicability").put("limitations", "No prospective task evidence")
            .put("prospective_test", "Compare on fresh mutable and immutable sources")
            .put("when_all", JSONArray().put(condition("repeated", "/repetitions", "gte", 2)))
            .put("unless_any", JSONArray().put(condition("mutable", "/mutable", "eq", true)))
        val rule by lazy { f.ref(f.publish("selection-rule", KIND, ruleSpec, round = 12, now = 500)) }
        fun savedRule() = CollaborationWorkflowSelection.read(rule, f.reopen(), f.access(round = 20))
        fun inputs(repetitions: Any = 3, mutable: Any = false) = JSONObject().put("dataset", JSONObject().put("repetitions", repetitions).put("mutable", mutable))
        fun instance(inputs: JSONObject = inputs(), execution: String = "conditional-use") = JSONObject().put(CollaborationWorkflowInstantiation.FIELD,
            JSONObject().put("execution_id", execution).put(FIELD, rule).put("inputs", inputs).put("roles", JSONObject().put("worker", "peer").put("reviewer", "lead")))
        fun expand(request: JSONObject = instance(), access: CollaborationWorkspaceAccess = f.access(round = 20)) =
            CollaborationWorkflowInstantiation.expand(JSONArray().put(request), { f.reopen() }, access).let { a -> (0 until a.length()).map(a::getJSONObject) }
        fun record() = f.record().let { it.copy(request = it.request.copy(context = it.request.context + (CollaborationGoalLoop.ROUND to "20"))) }
        fun admit(request: JSONObject = instance(), record: AgentTeamExecutionRecord = record()) =
            CollaborationWorkflowWork.plan(record, expand(request), { f.reopen() }, f.access(round = 20))
    }

    @Test fun retainedEvidenceSelectsActualDifferentGraphAndPreservesExplanation() {
        val x = Fixture(); val request = x.instance(); val original = request.toString(); val admitted = x.admit(request)
        assertEquals(original, request.toString())
        assertTrue(admitted.work.first().getString("assignment").contains("index"))
        val binding = JSONObject(CollaborationWorkflowWork.context(admitted.work.first()).getValue(CollaborationWorkflowWork.TASK))
        val decision = binding.getJSONObject(DECISION)
        assertEquals("candidate", decision.getString("variant")); assertEquals("applicability_matched", decision.getString("reason"))
        assertTrue(decision.isNull("quality_effect")); assertFalse(decision.getBoolean("causality_proven"))
        assertFalse(x.rule.getJSONObject(HOST).getBoolean("conditions_prospectively_validated"))
        assertEquals(x.candidate.getString("sha256"), binding.getJSONObject("method").getString("sha256"))
    }

    @Test fun outOfScopeCounterconditionsAndUnknownDataUsePreservedBaseline() {
        val x = Fixture()
        for ((inputs, reason) in listOf(x.inputs(1) to "outside_applicability", x.inputs(mutable = true) to "countercondition_matched",
            x.inputs("3") to "insufficient_condition_data", x.inputs().apply { getJSONObject("dataset").remove("mutable") } to "insufficient_condition_data")) {
            val admitted = x.admit(x.instance(inputs))
            assertTrue(admitted.work.first().getString("assignment").contains("parse"))
            val binding = JSONObject(CollaborationWorkflowWork.context(admitted.work.first()).getValue(CollaborationWorkflowWork.TASK))
            assertEquals(reason, binding.getJSONObject(DECISION).getString("reason"))
            assertEquals(x.t.method.getString("sha256"), binding.getJSONObject("method").getString("sha256"))
        }
    }

    @Test fun numericEqualityNullAndEscapedPointersKeepJsonSemantics() {
        val x = Fixture()
        x.ruleSpec.put("when_all", JSONArray().put(x.condition("equal", "/a~1b/~0key/0", "eq", 2.0))
            .put(x.condition("null", "/explicit", "eq", JSONObject.NULL))).put("unless_any", JSONArray())
        val input = JSONObject().put("dataset", JSONObject().put("a/b", JSONObject().put("~key", JSONArray().put(2))).put("explicit", JSONObject.NULL))
        assertEquals("candidate", CollaborationWorkflowSelection.choose(x.savedRule(), input).getString("variant"))
        input.getJSONObject("dataset").remove("explicit")
        assertEquals("insufficient_condition_data", CollaborationWorkflowSelection.choose(x.savedRule(), input).getString("reason"))
    }

    @Test fun allOrderedOperatorsAreTypedAndNoNumericStringCoercionOccurs() {
        val x = Fixture()
        for ((op, threshold) in listOf("lt" to 4, "lte" to 3, "gt" to 2, "gte" to 3, "neq" to 2)) {
            val record = x.savedRule()
            record.getJSONObject("body").getJSONObject(KIND).put("when_all", JSONArray().put(x.condition("test", "/repetitions", op, threshold)))
            assertEquals(op, "candidate", CollaborationWorkflowSelection.choose(record, x.inputs()).getString("variant"))
            assertEquals(op, "baseline", CollaborationWorkflowSelection.choose(record, x.inputs("3")).getString("variant"))
        }
    }

    @Test fun invalidRuleContractsAreRejectedWithSpecificFeedback() {
        val x = Fixture()
        for (change in listOf("lesson", "empty", "duplicate", "input", "pointer", "operator", "numeric", "object", "authority")) {
            val spec = JSONObject(x.ruleSpec.toString()); val c = spec.getJSONArray("when_all").getJSONObject(0)
            when (change) {
                "lesson" -> spec.put("lesson", x.plan)
                "empty" -> spec.put("when_all", JSONArray())
                "duplicate" -> c.put("id", "mutable")
                "input" -> c.put("input", "hidden")
                "pointer" -> c.put("pointer", "/bad~2")
                "operator" -> c.put("operator", "execute")
                "numeric" -> c.put("value", "2")
                "object" -> c.put("value", JSONObject())
                else -> c.put("permissions", "all")
            }
            assertEquals(change, "rejected", x.f.publish("bad-$change", KIND, spec, round = 15).getString("status"))
        }
    }

    @Test fun ruleIsDiscoverablePersistentAndAvailableAcrossAuthorizedFutureTurns() {
        val x = Fixture(); val rule = x.rule
        val later = x.f.access(round = 0).copy(runId = "future", turnId = "future")
        val recalled = x.f.reopen().searchCapabilities(later, "indexing")
        assertTrue(recalled.getJSONArray("records").toString().contains(rule.getString("object_id")))
        assertEquals("candidate", CollaborationWorkflowSelection.choose(CollaborationWorkflowSelection.read(rule, x.f.reopen(), later), x.inputs()).getString("variant"))
        assertTrue(runCatching { x.expand(access = later.copy(groupId = "other")) }.isFailure)
    }

    @Test fun cannotChooseBothMethodAndRuleOrForgeTheExpandedSelection() {
        val x = Fixture(); val request = x.instance(); request.getJSONObject(CollaborationWorkflowInstantiation.FIELD).put("method", x.t.method)
        assertTrue(runCatching { x.expand(request) }.isFailure)
        val work = x.expand(x.instance(x.inputs(1)))
        work.forEach { it.getJSONObject(CollaborationWorkflowWork.FIELD).getJSONObject("inputs").getJSONObject("dataset").put("repetitions", 3) }
        assertTrue(runCatching { CollaborationWorkflowWork.plan(x.f.record(), work, { x.f.workspace }, x.f.access(round = 20)) }.isFailure)
    }

    @Test fun rulesCannotBeChangedOrDetachedFromAdmittedWork() {
        val x = Fixture(); val admitted = x.admit(); val restored = x.t.withClaims(admitted)
        assertEquals(admitted.claims, x.admit(record = restored).claims)
        assertTrue(runCatching { x.admit(x.instance(x.inputs(1)), restored) }.isFailure)
        val work = x.expand(); work.forEach { it.getJSONObject(CollaborationWorkflowWork.FIELD).remove(FIELD) }
        assertTrue(runCatching { CollaborationWorkflowWork.plan(restored, work, { x.f.workspace }, x.f.access(round = 20)) }.isFailure)
        val raw = JSONObject(x.f.raw("rewrite", KIND, x.ruleSpec)); raw.getJSONArray("workspace").getJSONObject(0)
            .put("object_id", x.rule.getString("object_id")).put("base_revision", 1)
        assertEquals("rejected", x.f.workspace.publish(x.f.access(round = 20), raw.toString()).getString("status"))
    }

    @Test fun goalPlannerUsesConditionalGraphAndPreservesIndependentReview() {
        val x = Fixture(); val record = x.record()
        val next = CollaborationGoalLoop.advance(x.f.completed(record, "lead", x.f.report(listOf(x.instance())).toString(), true),
            "lead", 1000, false, candidateWorkspace = { x.f.reopen() })!!
        val nodes = next.definition.members.filter { CollaborationWorkflowWork.TASK in it.context }
        assertEquals(2, nodes.size); assertEquals(setOf(nodes.first().memberId), nodes.last().dependsOnAgentIds)
        assertEquals(x.f.criteria.toString(), next.request.context[CollaborationGoalLoop.CRITERIA].toString())
        assertTrue(nodes.all { JSONObject(it.context.getValue(CollaborationWorkflowWork.TASK)).has(DECISION) })
        val samePerson = x.instance(); samePerson.getJSONObject(CollaborationWorkflowInstantiation.FIELD).getJSONObject("roles").put("worker", "lead")
        val rejected = CollaborationGoalLoop.advance(x.f.completed(record, "lead", x.f.report(listOf(samePerson)).toString(), true),
            "lead", 1000, false, candidateWorkspace = { x.f.reopen() })!!
        assertTrue(rejected.definition.members.none { CollaborationWorkflowWork.TASK in it.context })
    }

    @Test fun executionHistoryKeepsSelectionInANewConversationWithoutClaimingLearningGain() {
        val x = Fixture(); val record = x.record()
        val next = CollaborationGoalLoop.advance(x.f.completed(record, "lead", x.f.report(listOf(x.instance())).toString(), true),
            "lead", 1000, false, candidateWorkspace = { x.f.reopen() })!!
        val node = next.definition.members.first { CollaborationWorkflowWork.TASK in it.context }
        val result = AgentSubagentChildResult("run", node.memberId, "run", 1, AgentSubagentStatus.FAILED, "Counterexample: input changed",
            startedAtMillis = 1000, completedAtMillis = 1200)
        x.f.workspace.recordMethodExperience(next, result)
        x.f.workspace.recordMethodExperience(next, result)
        val future = x.f.access().copy(runId = "later", turnId = "later", round = 0)
        val history = x.f.reopen().methodHistory(future, x.candidate).getJSONArray("records")
        assertEquals(1, history.length())
        val saved = x.f.reopen().methodHistoryRecord(future, history.getJSONObject(0).getString("record_id"))!!
        assertEquals("candidate", saved.getJSONObject("binding").getJSONObject(DECISION).getString("variant"))
        assertEquals(x.rule.getString("sha256"), saved.getJSONObject("binding").getJSONObject(DECISION).getJSONObject("rule").getString("sha256"))
        assertEquals("failed", saved.getString("status")); assertTrue(saved.isNull("quality_effect"))
    }

    @Test fun partialCompletionReplaysOnlyUnfinishedConditionalSteps() {
        val x = Fixture(); val admitted = x.admit(); val finished = admitted.work.first().getString("id")
        val record = x.record().let { it.copy(request = it.request.copy(context = it.request.context + mapOf(
            CollaborationWorkflowWork.CLAIMS to admitted.claims,
            CollaborationGoalLoop.FINISHED_WORK to JSONArray().put(finished).toString(),
            CollaborationGoalLoop.FINISHED_AUTHORS to JSONObject().put(finished, "peer").toString()))) }
        val next = CollaborationGoalLoop.advance(x.f.completed(record, "lead", x.f.report(listOf(x.instance())).toString(), true),
            "lead", 1500, false, candidateWorkspace = { x.f.reopen() })!!
        val nodes = next.definition.members.filter { CollaborationWorkflowWork.TASK in it.context }
        assertEquals(1, nodes.size); assertTrue(nodes.single().objective.contains("validate"))
        assertEquals(admitted.claims, next.request.context[CollaborationWorkflowWork.CLAIMS])
    }

    @Test fun staleEvidenceRejectsNewWorkButDoesNotRewriteAdmittedRecovery() {
        val x = Fixture(); val first = x.admit(); val restored = x.record().let {
            it.copy(request = it.request.copy(context = it.request.context + (CollaborationWorkflowWork.CLAIMS to first.claims))) }
        val raw = JSONObject(x.f.raw("revise-idea", "innovation", x.idea(x.candidate)))
        raw.getJSONArray("workspace").getJSONObject(0).put("object_id", x.after.getString("object_id")).put("base_revision", 1)
        val changed = x.f.workspace.publish(x.f.access("selection-after", 21, "revise-idea"), raw.toString(), 1500)
        assertEquals(changed.toString(), "recorded", changed.getString("status"))
        assertTrue(runCatching { x.admit(x.instance(execution = "new-use")) }.isFailure)
        assertEquals(first.claims, x.admit(record = restored).claims)
    }

    @Test fun livePlannerUsesRuleWithoutWaitingForUnrelatedMembers() {
        val x = Fixture(); val base = x.record(); val people = base.definition.members.map { it.copy(deliveryMode = AgentDeliveryMode.IGNORE) }
        val slow = people.last().copy(instanceId = "slow", deliveryMode = AgentDeliveryMode.OBSERVE,
            context = people.last().context + mapOf(CollaborationGoalLoop.ROSTER to "false", CollaborationGoalLoop.WORK_ID to "unrelated"))
        val planner = people.first().copy(instanceId = "planner", deliveryMode = AgentDeliveryMode.OBSERVE,
            context = people.first().context + mapOf(CollaborationGoalLoop.ROSTER to "false", CollaborationLiveGraph.PLANNER to "1"))
        val final = people.first().copy(instanceId = "final", deliveryMode = AgentDeliveryMode.RESPOND,
            context = people.first().context + (CollaborationGoalLoop.ROSTER to "false"))
        val record = base.copy(definition = base.definition.copy(members = people + slow + planner + final, primaryInstanceId = "final"))
        val report = JSONObject().put("format", CollaborationLiveGraph.FORMAT).put("summary", "Use conditional method").put("work", JSONArray().put(x.instance()))
        val next = CollaborationLiveGraph.update(x.f.completed(record, "planner", report.toString()), setOf("planner"), 1000, { x.f.reopen() })
        val nodes = next.definition.members.filter { CollaborationWorkflowWork.TASK in it.context }
        assertEquals(2, nodes.size); assertTrue(nodes.none { "slow" in it.dependsOnAgentIds })
        assertEquals(next.definition, CollaborationLiveGraph.update(next, setOf("planner"), 2000, { x.f.reopen() }).definition)
    }
}

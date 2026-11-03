package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.HOST
import com.galaxyssi.chat.CollaborationInnovationValidation.OPPORTUNITY
import com.galaxyssi.chat.CollaborationInnovationValidation.ASSESSMENT

class CollaborationInnovationTest {
    internal class Fixture(opportunityChange: (JSONObject) -> Unit = {}, planChange: (JSONObject) -> Unit = {}) {
        val rows = CollaborationEvolutionTest.Rows()
        val ledger = CollaborationEvidenceLedger(CollaborationEvolutionTest.Rows())
        fun reopen() = CollaborationResearchWorkspace(rows, evidence = ledger::references, evidenceReadCoverage = ledger::requireReadCoverage,
            evidenceOriginal = { a, r -> ledger.read(a, r.getString("evidence_id"), r.getString("sha256")) })
        val workspace = reopen()
        val goal = "Improve evidence comparison"
        val criteria = JSONArray().put(JSONObject().put("id", "quality").put("requirement", goal).put("verification", "documentary")
            .put("status", "open").put("evidence", JSONArray()))
        fun access(person: String = "lead", round: Long = 10, node: String = person) = CollaborationWorkspaceAccess("group", "run", "turn", round, node, person)
        fun raw(id: String, kind: String, spec: JSONObject, observations: JSONArray = JSONArray(), parents: JSONArray = JSONArray()) =
            JSONObject().put("format", CollaborationResearchArtifact.FORMAT).put("summary", "Synthetic innovation")
                .put("findings", JSONArray()).put("candidates", JSONArray()).put("workspace", JSONArray().put(JSONObject().put("id", id)
                    .put("kind", kind).put("title", id).put("body", JSONObject().put("content", "Original synthetic data").put(kind, spec))
                    .put("observations", observations).put("parents", parents))).toString()
        fun publish(id: String, kind: String, spec: JSONObject, person: String = id, round: Long = 1, now: Long = 10,
                    observations: JSONArray = JSONArray(), parents: JSONArray = JSONArray()) = workspace.publish(access(person, round, id), raw(id, kind, spec, observations, parents), now)
        fun ref(receipt: JSONObject): JSONObject { assertEquals(receipt.toString(), "recorded", receipt.getString("status")); return receipt.getJSONArray("revisions").getJSONObject(0) }
        val baseline = ref(publish("baseline", "artifact", JSONObject()))
        val opportunitySpec = JSONObject().put("goal_sha256", CollaborationSemanticGoalCoverage.source(goal).getString("goal_sha256"))
            .put("criterion_id", "quality").put("requirement", goal).put("question", "Can parsed evidence be reused safely?")
            .put("unmet_need", "Repeated parsing").put("expected_benefit", "Fewer operations at equal correctness")
            .put("constraints", "Same corpus, local only").put("null_hypothesis", "No improvement")
            .put("discriminating_test", "Compare counts and correctness").put("uncertainty", "Fixture only")
            .put("alternative_routes", JSONArray().put("Batch requests instead")).put("drivers", JSONArray().put(JSONObject()
                .put("id", "reuse").put("kind", "limitation").put("sources", JSONArray().put(baseline))
                .put("why", "Baseline duplicates work").put("what_would_change", "Different corpus"))).apply(opportunityChange)
        val opportunity = ref(publish("opportunity", OPPORTUNITY, opportunitySpec, round = 2, now = 20))
        val ideaSpec = JSONObject("""{"origin":"limitation","hypothesis":"Reuse reduces operations","mechanism":"Immutable parsed index",
            "difference":"Avoid reparsing","prior_art":"Not searched yet","novelty_scope":"not_checked","falsifier":"Same cost or incorrect output",
            "domain":"fixture","applies_when":"Identical authorized corpus","risks":"Stale data","alternatives":["Batching"],
            "predictions":[{"id":"p1","statement":"Less work, same quality","test":"Paired local comparison"}]}""").put(OPPORTUNITY, opportunity)
        val idea = ref(publish("idea", "innovation", ideaSpec, round = 3, now = 30, parents = JSONArray().put(opportunity)))
        val spec = JSONObject().put("innovation", idea).put("baseline", baseline).put("prediction_id", "p1").put("method", "Paired local comparison")
            .put("environment", "fixture").put("budget_unit", "operations").put("budget_limit", 100)
            .put("source", JSONObject().put("origin", "android_native_tool").put("tool", "fixture.compare")).put("report_pointer", "")
            .put("cases", JSONArray().put(case("value", "target").put("dimension", "value"))
                .put(case("possible", "feasibility").put("threshold", 11)).put(case("old", "regression"))).apply(planChange)
        val plan = ref(publish("plan", "experiment_plan", spec, round = 4, now = 100))
        val observations = JSONArray()
        fun case(id: String, purpose: String) = JSONObject().put("id", id).put("purpose", purpose).put("prediction", "Observable change")
            .put("metric", "score").put("direction", "maximize").put("minimum_gain", 1).put("tolerance", 0).put("repetitions", 1)
        fun run(change: (JSONObject) -> Unit = {}): JSONObject {
            val samples = JSONArray()
            val cases = spec.getJSONArray("cases")
            repeat(cases.length()) { i -> for (variant in listOf("baseline", "candidate")) samples.put(JSONObject()
                .put("case_id", cases.getJSONObject(i).getString("id")).put("variant", variant)
                .put("variant_sha256", (if (variant == "baseline") baseline else idea).getString("sha256"))
                .put("metric", "score").put("repetition", 1).put("value", if (variant == "baseline") 10 else 12).put("budget_used", 20)) }
            val report = JSONObject().put("format", CollaborationEvolutionExperiment.FORMAT).put("plan_sha256", plan.getString("sha256"))
                .put("environment", "fixture").put("budget_unit", "operations").put("measurements", samples).apply(change)
            val observed = ledger.record(access("executor", 5), "trial", "fixture.compare", "{}", report.toString(), 200, 201, CollaborationEvidenceOrigin.ANDROID_NATIVE_TOOL)
            observations.put(observed)
            read(access("analyst", 6, "result"))
            return ref(publish("result", "experiment_result", JSONObject().put("plan", plan).put("interpretation", "Synthetic result")
                .put("limitations", "Not real research"), "analyst", 6, 300, observations))
        }
        fun read(access: CollaborationWorkspaceAccess, refs: JSONArray = observations) {
            repeat(refs.length()) { i -> var offset: Int? = 0
                while (offset != null) offset = ledger.readPage(access, refs.getJSONObject(i).getString("evidence_id"), refs.getJSONObject(i).getString("sha256"), offset)!!.next }
        }
        fun review(result: JSONObject): JSONObject {
            val prior = ledger.record(access("searcher", 7), "prior", "fixture.prior_art", "{}", "{\"method\":\"Repeated parsing\"}", 320, 321,
                CollaborationEvidenceOrigin.ANDROID_NATIVE_TOOL)
            observations.put(prior)
            return JSONObject().put("innovation", idea).put("decision", "retain").put("rationale", "Independent scoped comparison")
                .put("novelty", JSONObject().put("outcome", "distinguished_in_searched_scope").put("search_scope", "Synthetic prior art fixture")
                    .put("coverage_gaps", "Everything outside fixture").put("rationale", "Mechanism differs")
                    .put("closest_work", JSONArray().put(JSONObject().put("observation", prior).put("overlap", "Parsing")
                        .put("difference", "Index reuse").put("significance", "Fewer parses"))))
                .put("results", JSONArray().put(result)).put("feasibility_scope", "Local counts").put("value_scope", "Fixture metric")
                .put("limitations", "No global novelty proof").put("unresolved", JSONArray()).put("next_action", "Test realistic inputs")
        }
        fun assess(value: JSONObject, id: String = "assessment", person: String = "reviewer", read: Boolean = true): JSONObject {
            if (read) read(access(person, 8, id))
            return publish(id, ASSESSMENT, value, person, 8, 400, observations)
        }
        fun work(phase: String = "explore") = JSONObject().put("id", "explore-work").put("member", "peer").put("stage", "EXECUTE")
            .put("assignment", "Investigate the opportunity without external side effects").put("innovation_work", JSONObject()
                .put("opportunity", opportunity).put("phase", phase).put("expected_output", "Evidence-linked alternatives").put("why_now", "Serves open quality criterion"))
        fun record(): AgentTeamExecutionRecord {
            val members = CollaborationGoalLoop.initial(listOf(AgentTeamMember("fixture", AgentDeliveryMode.RESPOND, instanceId = "lead"),
                AgentTeamMember("fixture", AgentDeliveryMode.OBSERVE, instanceId = "peer")), goal).map {
                it.copy(context = it.context + mapOf("collaboration_group_id" to "group", CollaborationLiveGraph.ENABLED to "1")) }
            return AgentTeamExecutionRecord(AgentTeamDefinition("team", "fixture", members, primaryInstanceId = "lead"),
                AgentRunRequest("group", "turn", "task", runId = "run", goal = goal, context = mapOf(CollaborationGoalLoop.ROUND to "10", CollaborationGoalLoop.CRITERIA to criteria.toString())))
        }
        fun report(work: List<JSONObject>) = JSONObject().put("format", CollaborationGoalLoop.FORMAT).put("summary", "Investigate scoped opportunity")
            .put("decision", "continue").put("criteria", criteria).put("work", JSONArray(work)).put("blockers", JSONArray())
        fun completed(record: AgentTeamExecutionRecord, child: String, output: String, terminal: Boolean = false): AgentTeamExecutionRecord {
            val seq = record.events.size + 1L
            return record.copy(events = record.events + AgentSubagentEvent(seq, "run", child, AgentSubagentEventKinds.CHILD_SUCCEEDED,
                childStatus = AgentSubagentStatus.SUCCEEDED, result = AgentSubagentChildResult("run", child, "run", 1, AgentSubagentStatus.SUCCEEDED, output,
                    startedAtMillis = 100, completedAtMillis = 300)) + if (terminal) listOf(AgentSubagentEvent(seq + 1, "run",
                kind = AgentSubagentEventKinds.SUPERVISOR_SUCCEEDED, runStatus = AgentSubagentRunStatus.SUCCEEDED)) else emptyList())
        }
    }

    @Test fun scopedNoveltyFeasibilityAndValueAreSeparateAndPersist() {
        val f = Fixture(); val result = f.run(); val review = f.review(result); val assessment = f.ref(f.assess(review))
        val host = assessment.getJSONObject(HOST)
        assertEquals("eligible_for_scoped_innovation_use", host.getString("state"))
        assertTrue(host.getBoolean("feasibility_measured")); assertTrue(host.getBoolean("value_measured"))
        assertFalse(host.getBoolean("novelty_certified")); assertFalse(host.getBoolean("automatically_installed"))
        assertNotNull(f.reopen().read(f.access().copy(runId = "future", turnId = "future", round = 0), assessment.getString("object_id"), 1))
    }

    @Test fun claimedNoveltyCannotReplaceOriginalReadSources() {
        val f = Fixture(); val review = f.review(f.run())
        assertEquals("rejected", f.assess(review, read = false).getString("status"))
        review.getJSONObject("novelty").put("closest_work", JSONArray())
        assertEquals("rejected", f.assess(review, "no-source").getString("status"))
        review.getJSONObject("novelty").put("outcome", "world_first")
        assertEquals("rejected", f.assess(review, "global-claim").getString("status"))
    }

    @Test fun ideaAuthorCannotIndependentlyRetainAndBlockersArePreserved() {
        val f = Fixture(); val review = f.review(f.run())
        assertEquals("rejected", f.assess(review, person = "idea").getString("status"))
        review.put("unresolved", JSONArray().put("Physical validation missing"))
        assertEquals("rejected", f.assess(review, "blocked-retain").getString("status"))
        review.put("decision", "continue")
        val saved = f.ref(f.assess(review, "continue"))
        assertEquals("continue", saved.getJSONObject(HOST).getString("state"))
    }

    @Test fun regressionAndUnmeasuredValueRejectRetention() {
        for (variant in listOf("regression", "no-value")) {
            val f = Fixture(planChange = { if (variant == "no-value") it.getJSONArray("cases").getJSONObject(0).put("dimension", "mechanism") })
            val result = f.run { if (variant == "regression") it.getJSONArray("measurements").getJSONObject(5).put("value", 9) }
            assertEquals("rejected", f.assess(f.review(result)).getString("status"))
        }
    }

    @Test fun feasibilityUsesAbsoluteThresholdNotPositiveGain() {
        val f = Fixture(planChange = { it.getJSONArray("cases").getJSONObject(1).put("threshold", 13) })
        val result = f.run()
        assertEquals("infeasible", result.getJSONObject(HOST).getString("state"))
        assertEquals("rejected", f.assess(f.review(result)).getString("status"))
    }

    @Test fun feasibilityOnlyAndMinimizeThresholdNeverBecomeCapabilityGain() {
        val f = Fixture(planChange = { p -> p.put("cases", JSONArray().put(JSONObject(p.getJSONArray("cases").getJSONObject(1).toString())
            .put("direction", "minimize").put("threshold", 12))) })
        val result = f.run()
        assertEquals("feasibility_measured", result.getJSONObject(HOST).getString("state"))
        assertFalse(result.getJSONObject(HOST).getBoolean("eligible_for_retention"))
        assertEquals("rejected", f.assess(f.review(result)).getString("status"))
    }

    @Test fun incompleteMeasurementsAndKnownPriorWorkCannotBeRetained() {
        val f = Fixture(); val result = f.run { it.getJSONArray("measurements").remove(3) }
        assertEquals("incomplete", result.getJSONObject(HOST).getString("state"))
        assertEquals("rejected", f.assess(f.review(result)).getString("status"))
        val g = Fixture(); val review = g.review(g.run()); review.getJSONObject("novelty").put("outcome", "known")
        assertEquals("rejected", g.assess(review).getString("status"))
        assertEquals("reject", g.ref(g.assess(review.put("decision", "reject"), "known-reject")).getJSONObject(HOST).getString("state"))
    }

    @Test fun opportunityDriversRequireSavedGapsAndTransferStudies() {
        for (kind in listOf("knowledge_gap", "cross_domain", "contradiction")) reject {
            Fixture(opportunityChange = { it.getJSONArray("drivers").getJSONObject(0).put("kind", kind) })
        }
        val f = Fixture(opportunityChange = { it.getJSONArray("drivers").getJSONObject(0).put("kind", "contradiction")
            .put("claim_a", "Caching helps").put("claim_b", "Caching may be stale") })
        assertEquals("opportunity_hypothesis", f.opportunity.getJSONObject(HOST).getString("state"))
    }

    @Test fun admissionBindsGoalCriterionAndExperimentPrerequisites() {
        val f = Fixture(); val record = f.record()
        reject { CollaborationInnovationWork.plan(record.copy(request = record.request.copy(goal = "Different goal")), listOf(f.work()), { f.workspace }, f.access()) }
        reject { CollaborationInnovationWork.plan(record, listOf(f.work()), { f.workspace }, f.access(), JSONArray()) }
        reject { CollaborationInnovationWork.plan(record, listOf(f.work("experiment")), { f.workspace }, f.access()) }
        val work = f.work("experiment").apply { getJSONObject("innovation_work").put("innovation", f.idea).put("plan", f.plan) }
        val plan = CollaborationInnovationWork.plan(record, listOf(work), { f.workspace }, f.access())
        val binding = JSONObject(CollaborationInnovationWork.context(plan.work.single()).getValue(CollaborationInnovationWork.TASK))
        assertEquals("documentary", binding.getJSONObject("criterion").getString("verification"))
        assertFalse(binding.getBoolean("grants_permissions")); assertFalse(binding.getBoolean("goal_verified"))
    }

    @Test fun recoveryCannotRewriteBindingButCriteriaStatusCanChange() {
        val f = Fixture(); val work = f.work()
        val selected = CollaborationInnovationWork.plan(f.record(), listOf(work), { f.workspace }, f.access())
        val restored = f.record().copy(request = f.record().request.copy(context = f.record().request.context + (CollaborationInnovationWork.CLAIMS to selected.claims)))
        val criteria = JSONArray(f.criteria.toString()).apply { getJSONObject(0).put("status", "met").put("evidence", JSONArray().put("New evidence")) }
        assertEquals(selected.claims, CollaborationInnovationWork.plan(restored, listOf(work), { f.reopen() }, f.access(), criteria).claims)
        reject { CollaborationInnovationWork.plan(restored, listOf(JSONObject(work.toString()).put("assignment", "Change task")), { f.workspace }, f.access()) }
        reject { CollaborationInnovationWork.plan(restored, listOf(JSONObject(work.toString()).apply { remove("innovation_work") }), { f.workspace }, f.access()) }
    }

    @Test fun admissionIsolationAndMixedInvalidBatchHaveNoSideEffects() {
        val f = Fixture(); val work = f.work(); val before = work.toString()
        reject { CollaborationInnovationWork.plan(f.record(), listOf(work), { f.workspace }, f.access().copy(groupId = "other")) }
        reject { CollaborationInnovationWork.plan(f.record(), listOf(work), null, f.access()) }
        reject { CollaborationInnovationWork.plan(f.record(), listOf(work, JSONObject(work.toString()).put("host_innovation_work", JSONObject())), { f.workspace }, f.access()) }
        assertEquals(before, work.toString())
        val ordinary = JSONObject().put("id", "ordinary")
        assertSame(ordinary, CollaborationInnovationWork.plan(f.record(), listOf(ordinary), { error("No ordinary-task workspace I/O") }, f.access()).work.single())
    }

    @Test fun nextRoundActuallyDispatchesBoundWorkAndCapturesOnce() {
        val f = Fixture(); val finished = f.completed(f.record(), "lead", f.report(listOf(f.work())).toString(), true)
        val next = CollaborationGoalLoop.advance(finished, "lead", 1000, true, candidateWorkspace = { f.workspace })!!
        val selected = next.definition.members.single { CollaborationInnovationWork.TASK in it.context }
        val completed = f.completed(next, selected.memberId, "Alternative registered")
        val raw = CollaborationInnovationWork.capture(completed, completed.events.mapNotNull { it.result })
        assertFalse(JSONObject(raw).getJSONObject(selected.memberId).getBoolean("innovation_verified"))
        assertEquals(raw, CollaborationInnovationWork.capture(completed.copy(request = completed.request.copy(context = completed.request.context +
            (CollaborationInnovationWork.OUTCOMES to raw))), completed.events.mapNotNull { it.result }))
        val bad = f.work().put("id", "invalid").apply { getJSONObject("innovation_work").put("phase", "invented") }
        val rejected = CollaborationGoalLoop.advance(f.completed(f.record(), "lead", f.report(listOf(f.work(), bad)).toString(), true),
            "lead", 1000, true, candidateWorkspace = { f.workspace })!!
        assertTrue(rejected.definition.members.none { CollaborationInnovationWork.TASK in it.context })
        assertEquals("{}", rejected.request.context[CollaborationInnovationWork.CLAIMS])
    }

    @Test fun changedIdeaLeavesAssessmentHistoricalAndRejectsNewRetention() {
        val f = Fixture(); val result = f.run(); val assessment = f.ref(f.assess(f.review(result)))
        val update = JSONObject(f.raw("idea-update", "innovation", f.ideaSpec, parents = JSONArray().put(f.opportunity)))
        update.getJSONArray("workspace").getJSONObject(0).put("object_id", f.idea.getString("object_id")).put("base_revision", 1)
        assertEquals("recorded", f.workspace.publish(f.access("idea", 9, "idea-update"), update.toString(), 500).getString("status"))
        val saved = f.reopen().browseEvolution(f.access(round = 12)).revisions.single { it.getString("object_id") == assessment.getString("object_id") }
        assertEquals("historical_requires_revalidation", saved.getString("evolution_applicability"))
        assertNotNull(f.reopen().read(f.access(round = 12), assessment.getString("object_id"), 1))
        reject { CollaborationInnovationWork.plan(f.record(), listOf(f.work("experiment").apply { getJSONObject("innovation_work")
            .put("innovation", f.idea).put("plan", f.plan) }), { f.reopen() }, f.access(round = 12)) }
    }

    @Test fun opportunityLessonCannotBypassIndependentAssessment() {
        val f = Fixture(); val result = f.run(); val review = f.review(result)
        val lesson = JSONObject().put("result", result).put("decision", "retain").put("rationale", "Synthetic retention")
            .put("applies_when", "Fixture").put("avoid_when", "Real research").put("procedure", "Reuse index")
            .put("transfer_test", "New experiment").put("rollback", f.baseline)
        f.read(f.access("reviewer", 9, "no-assessment"))
        assertEquals("rejected", f.publish("no-assessment", "capability_lesson", lesson, "reviewer", 9, 500, f.observations).getString("status"))
        val assessment = f.ref(f.assess(review))
        lesson.put(ASSESSMENT, assessment); f.read(f.access("reviewer", 9, "with-assessment"))
        val saved = f.ref(f.publish("with-assessment", "capability_lesson", lesson, "reviewer", 9, 500, f.observations))
        assertEquals(assessment.getString("sha256"), saved.getJSONObject(HOST).getJSONObject(ASSESSMENT).getString("sha256"))
    }

    @Test fun incrementalWorkDoesNotWaitForUnrelatedTasksOrReplayExecution() {
        val f = Fixture(); val base = f.record(); val people = base.definition.members.map { it.copy(deliveryMode = AgentDeliveryMode.IGNORE) }
        val slow = people.last().copy(instanceId = "slow", deliveryMode = AgentDeliveryMode.OBSERVE,
            context = people.last().context + mapOf(CollaborationGoalLoop.ROSTER to "false", CollaborationGoalLoop.WORK_ID to "slow-work",
                CollaborationResearchWorkflow.STAGE to "EXECUTE"))
        val planner = people.first().copy(instanceId = "planner-node", deliveryMode = AgentDeliveryMode.OBSERVE,
            context = people.first().context + mapOf(CollaborationGoalLoop.ROSTER to "false", CollaborationLiveGraph.PLANNER to "1"))
        val final = people.first().copy(instanceId = "final", deliveryMode = AgentDeliveryMode.RESPOND,
            context = people.first().context + (CollaborationGoalLoop.ROSTER to "false"), dependsOnAgentIds = setOf("slow", planner.memberId))
        val live = base.copy(definition = base.definition.copy(members = people + slow + planner + final, primaryInstanceId = "final"))
        val returned = f.completed(live, planner.memberId, JSONObject().put("format", CollaborationLiveGraph.FORMAT)
            .put("summary", "Investigate a useful independent branch").put("work", JSONArray().put(f.work())).toString())
        val next = CollaborationLiveGraph.update(returned, setOf(planner.memberId), 1000, { f.workspace })
        val selected = next.definition.members.single { CollaborationInnovationWork.TASK in it.context }
        assertFalse("Unrelated work must not become a dependency", "slow" in selected.dependsOnAgentIds)
        assertEquals(slow, next.definition.members.single { it.memberId == "slow" })
        assertEquals(next.definition, CollaborationLiveGraph.update(next, setOf(planner.memberId), 2000, { f.workspace }).definition)
        val completed = f.completed(next, selected.memberId, "Scoped output")
        val captured = CollaborationLiveGraph.update(completed, setOf(selected.memberId), 3000, { f.workspace })
        assertEquals("succeeded", JSONObject(captured.request.context.getValue(CollaborationInnovationWork.OUTCOMES).toString())
            .getJSONObject(selected.memberId).getString("status"))
    }

    @Test fun scopeCannotBeForgedWithAnUnrelatedPlanOrResult() {
        val f = Fixture()
        val unrelated = f.ref(f.publish("other-idea", "innovation", JSONObject(f.ideaSpec.toString()), round = 5, now = 120, parents = JSONArray().put(f.opportunity)))
        val work = f.work("experiment").apply { getJSONObject("innovation_work").put("innovation", unrelated).put("plan", f.plan) }
        reject { CollaborationInnovationWork.plan(f.record(), listOf(work), { f.workspace }, f.access()) }
        val review = f.review(f.run()).put("innovation", unrelated)
        assertEquals("rejected", f.assess(review).getString("status"))
    }

    @Test fun incompleteFeasibilityCannotBorrowValueFromAnotherExperiment() {
        val f = Fixture(); val result = f.run(); val review = f.review(result)
        val host = JSONObject(result.getJSONObject(HOST).toString()).put("state", "incomplete")
        reject { CollaborationInnovationValidation.assessment(review, JSONObject().put("host_observations", f.observations), "reviewer",
            { ref, _ -> val saved = f.workspace.read(f.access(), ref.getString("object_id"), ref.getInt("revision"))!!
                if (saved.getString("kind") == "experiment_result") JSONObject(saved.toString()).put(HOST, host) else saved },
            { ref -> f.ledger.read(f.access(), ref.getString("evidence_id"), ref.getString("sha256")) }, {}) }
    }

    @Test fun deepLineageIsIterativeAndVisitsEachSavedVersionOnce() {
        val data = hashMapOf<String, JSONObject>()
        var previous: JSONObject? = null
        repeat(2000) { i ->
            val ref = JSONObject().put("object_id", "opportunity-$i").put("revision", 1).put("sha256", "hash-$i")
            val record = JSONObject(ref.toString()).put("kind", OPPORTUNITY).put(HOST, JSONObject().put("basis", JSONArray().apply { previous?.let { put(it) } }))
            data[ref.getString("object_id")] = record; previous = ref
        }
        var reads = 0
        CollaborationInnovationValidation.checkRecord(data.getValue("opportunity-1999")) { ref, _ -> reads++; data.getValue(ref.getString("object_id")) }
        assertEquals(1999, reads)
    }

    @Test fun baselineContributorCannotLaunderAnIndependentReview() {
        val f = Fixture(); val review = f.review(f.run())
        reject { CollaborationInnovationValidation.assessment(review, JSONObject().put("host_observations", f.observations), "reviewer",
            { ref, _ -> val saved = f.workspace.read(f.access(), ref.getString("object_id"), ref.getInt("revision"))!!
                if (saved.getString("object_id") == f.baseline.getString("object_id")) JSONObject(saved.toString())
                    .put(HOST, JSONObject().put("contributors", JSONArray().put("reviewer"))) else saved },
            { ref -> f.ledger.read(f.access(), ref.getString("evidence_id"), ref.getString("sha256")) }, {}) }
    }

    private fun reject(block: () -> Unit) = assertNotNull("Expected rejection", runCatching(block).exceptionOrNull())
}

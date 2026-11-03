package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.HOST
import com.galaxyssi.chat.CollaborationTeamInvention.EXCHANGE
import com.galaxyssi.chat.CollaborationTeamInvention.SYNTHESIS
import com.galaxyssi.chat.CollaborationTeamInvention.EVALUATION

class CollaborationTeamInventionTest {
    internal class Fixture {
        val f = CollaborationInnovationTest.Fixture()
        val a = f.idea
        val b = f.ref(f.publish("parent-b", "innovation", JSONObject(f.ideaSpec.toString()).put("mechanism", "Deduplicate"), "peer", 3, 30,
            parents = JSONArray().put(f.opportunity)))
        fun challenge(idea: JSONObject) = JSONObject().put("operation", "challenge").put("innovation", idea).put("issue", "Edge cases")
            .put("reasoning", "Incomplete normalization").put("discriminating_test", "Mixed case duplicates").put("uncertainty", "Synthetic only")
            .put("suggested_change", "Combine normalization and deduplication")
        val ca = f.ref(f.publish("challenge-a", EXCHANGE, challenge(a), "critic-a", 4, 40))
        val cb = f.ref(f.publish("challenge-b", EXCHANGE, challenge(b), "critic-b", 4, 40))
        fun response(idea: JSONObject, challenge: JSONObject) = this.challenge(idea).put("operation", "response").put("challenge", challenge)
            .put("decision", "test_needed").put("change_or_reason", "Test combined mechanism").put("remaining_question", "Interaction gain unknown")
        val ra = f.ref(f.publish("response-a", EXCHANGE, response(a, ca), "idea", 5, 50))
        val rb = f.ref(f.publish("response-b", EXCHANGE, response(b, cb), "peer", 5, 50))
        fun part(idea: JSONObject, challenge: JSONObject, response: JSONObject) = JSONObject().put("innovation", idea).put("challenge", challenge)
            .put("response", response).put("retained", "Useful mechanism").put("changed", "Compose before lookup").put("response_effect", "Add mixed input test")
        val synthesisSpec = JSONObject().put("opportunity", f.opportunity).put("mechanism", "Normalize then deduplicate")
            .put("interaction_hypothesis", "Normalization enables deduplication").put("why_not_concatenation", "Order changes the result")
            .put("discriminating_test", "Compare each parent").put("limitations", "Local synthetic inputs")
            .put("contributions", JSONArray().put(part(a, ca, ra)).put(part(b, cb, rb)))
        val synthesis = f.ref(f.publish("synthesis", SYNTHESIS, synthesisSpec, "lead", 6, 60))
        val parents = JSONArray().put(a).put(b).put(synthesis).put(f.opportunity)
        val ideaSpec = JSONObject(f.ideaSpec.toString()).put("origin", "combination").put("transfer_conditions", "Same corpus")
            .put(SYNTHESIS, synthesis).put("mechanism", "Normalize before deduplicating")
        val idea = f.ref(f.publish("combined", "innovation", ideaSpec, "lead", 7, 70, parents = parents))
        val dataset = f.ref(f.publish("corpus", "artifact", JSONObject().put("input", "A a B b"), "data", 1, 10))
        val controls = listOf(a, b, f.baseline)
        val specs = controls.map { control -> JSONObject(f.spec.toString()).put("innovation", idea).put("baseline", control)
            .put("budget_limit", 200)
            .put(CollaborationTeamComparison.FIELD, JSONObject().put("single_agent", f.baseline).put("accounting", "end_to_end").put("resource_scope", "All operations"))
            .apply { getJSONArray("cases").let { c -> repeat(c.length()) { c.getJSONObject(it).put("dataset", dataset) } } } }
        val plans = specs.mapIndexed { i, spec -> f.ref(f.publish("comparison-$i", "experiment_plan", spec, "planner", 8, 100)) }
        val observations = JSONArray()
        fun run(index: Int, change: (JSONObject) -> Unit = {}): JSONObject {
            val samples = JSONArray()
            val spec = specs[index]
            val cases = spec.getJSONArray("cases")
            repeat(cases.length()) { i -> for (variant in listOf("baseline", "candidate")) samples.put(JSONObject()
                .put("case_id", cases.getJSONObject(i).getString("id")).put("variant", variant)
                .put("variant_sha256", (if (variant == "baseline") controls[index] else idea).getString("sha256"))
                .put("dataset_sha256", dataset.getString("sha256")).put("metric", "score").put("repetition", 1)
                .put("value", if (variant == "baseline") 10 else 12).put("budget_used", 10)) }
            val totals = JSONArray()
            for (variant in listOf("baseline", "candidate")) totals.put(JSONObject().put("variant", variant).put("preparation", 5)
                .put("coordination", if (variant == "candidate") 10 else 0).put("execution", 30))
            val report = JSONObject().put("format", CollaborationEvolutionExperiment.FORMAT).put("plan_sha256", plans[index].getString("sha256"))
                .put("environment", "fixture").put("budget_unit", "operations").put("measurements", samples).put("resource_totals", totals).apply(change)
            val ref = f.ledger.record(f.access("executor", 9), "compare-$index", "fixture.compare", "{}", report.toString(), 200, 201, CollaborationEvidenceOrigin.ANDROID_NATIVE_TOOL)
            observations.put(ref)
            val refs = JSONArray().put(ref)
            f.read(f.access("analyst", 10, "team-result-$index"), refs)
            return f.publish("team-result-$index", "experiment_result", JSONObject().put("plan", plans[index]).put("interpretation", "Local comparison")
                .put("limitations", "Not real agent gains"), "analyst", 10, 300, refs)
        }
        fun results(change: (Int, JSONObject) -> Unit = { _, _ -> }) = JSONArray().apply {
            repeat(3) { i -> put(f.ref(run(i) { change(i, it) })) }
        }
        fun review(results: JSONArray, decision: String = "retain") = JSONObject().put("innovation", idea).put("results", results).put("decision", decision)
            .put("rationale", "Same conditions, compare all controls").put("harness_review", "Inspected fixture implementation")
            .put("limitations", "No model or scientific claims").put("unresolved", JSONArray()).put("next_action", "Test realistic data")
        fun evaluate(value: JSONObject, person: String = "reviewer", read: Boolean = true, id: String = "team-review"): JSONObject {
            if (read) f.read(f.access(person, 11, id), observations)
            return f.publish(id, EVALUATION, value, person, 11, 400, observations)
        }
        fun exact(ref: JSONObject, kinds: Set<String>): JSONObject {
            val saved = requireNotNull(f.workspace.read(f.access(round = 20), ref.getString("object_id"), ref.getInt("revision")))
            require(saved.getString("kind") in kinds && CollaborationResearchCandidates.same(saved, ref) &&
                f.workspace.isCurrent(f.access(round = 20), ref.getString("object_id"), ref.getInt("revision")))
            return saved
        }
    }

    @Test fun peerChallengeResponseCombinationAndComparisonsSurviveReopen() {
        val t = Fixture(); val saved = t.f.ref(t.evaluate(t.review(t.results())))
        assertEquals("eligible_for_scoped_team_reuse", saved.getJSONObject(HOST).getString("state"))
        assertFalse(saved.getJSONObject(HOST).getBoolean("general_team_superiority_proven"))
        val reopened = t.f.reopen().read(t.f.access(round = 20).copy(runId = "later", turnId = "later"), saved.getString("object_id"), 1)
        assertNotNull(reopened)
        assertEquals(3, saved.getJSONObject(HOST).getJSONArray("results").length())
        assertTrue(t.idea.getJSONObject(HOST).getJSONArray("contributors").toString().contains("critic-a"))
    }

    @Test fun challengeCannotComeFromAuthorAndResponseCannotComeFromUnrelatedMember() {
        val t = Fixture()
        assertEquals("rejected", t.f.publish("self-challenge", EXCHANGE, t.challenge(t.a), "idea", 5, 50).getString("status"))
        assertEquals("rejected", t.f.publish("forged-response", EXCHANGE, t.response(t.a, t.ca), "stranger", 6, 60).getString("status"))
        assertEquals("rejected", t.f.publish("wrong-response", EXCHANGE, t.response(t.a, t.cb), "idea", 6, 60).getString("status"))
    }

    @Test fun combinationCannotDropChallengesOrDuplicateOneIdea() {
        val t = Fixture()
        for (variant in listOf("missing", "duplicate", "wrong")) {
            val spec = JSONObject(t.synthesisSpec.toString()); val parts = spec.getJSONArray("contributions")
            when (variant) {
                "missing" -> parts.getJSONObject(0).remove("response")
                "duplicate" -> parts.put(1, parts.getJSONObject(0))
                else -> parts.getJSONObject(0).put("response", t.rb)
            }
            assertEquals("rejected", t.f.publish(variant, SYNTHESIS, spec, "lead", 7, 70).getString("status"))
        }
        assertEquals("rejected", t.f.publish("missing-parents", "innovation", t.ideaSpec, "lead", 8, 80,
            parents = JSONArray().put(t.synthesis).put(t.f.opportunity)).getString("status"))
    }

    @Test fun singleAuthorVariantsAreNotDifferentTeamMembers() {
        val t = Fixture()
        val fake = JSONObject(t.b.toString()).put("person_id", t.a.getString("person_id"))
        reject { CollaborationTeamInvention.synthesis(t.synthesisSpec) { ref, kinds ->
            if (ref.getString("object_id") == t.b.getString("object_id")) fake else t.exact(ref, kinds)
        } }
    }

    @Test fun incompleteOrNonImprovingParentComparisonCannotBeRetained() {
        for (variant in listOf("missing-parent", "regression", "no-gain", "missing-cost")) {
            val t = Fixture()
            val results = t.results { i, report -> if (i == 0) when (variant) {
                "regression" -> report.getJSONArray("measurements").getJSONObject(5).put("value", 9)
                "no-gain" -> report.getJSONArray("measurements").getJSONObject(1).put("value", 10)
                "missing-cost" -> report.remove("resource_totals")
            } }
            if (variant == "missing-parent") results.remove(0)
            assertEquals(variant, "rejected", t.evaluate(t.review(results)).getString("status"))
            val saved = t.f.ref(t.evaluate(t.review(results, "revise"), id = "negative"))
            assertEquals("revise", saved.getJSONObject(HOST).getString("state"))
        }
    }

    @Test fun completeCostsMustIncludeCoordinationAndAllTrials() {
        for (variant in listOf("overspend", "omitted-trials", "negative", "duplicate")) {
            val t = Fixture()
            val receipt = t.run(0) { report -> val rows = report.getJSONArray("resource_totals"); val row = rows.getJSONObject(1)
                when (variant) {
                    "overspend" -> row.put("coordination", 300)
                    "omitted-trials" -> row.put("execution", 1)
                    "negative" -> row.put("preparation", -1)
                    else -> rows.put(JSONObject(row.toString()))
                }
            }
            assertEquals(variant, "rejected", receipt.getString("status"))
        }
    }

    @Test fun datasetAndMeasurementIdentityCannotChange() {
        val t = Fixture()
        assertEquals("rejected", t.run(0) { it.getJSONArray("measurements").getJSONObject(0).put("dataset_sha256", "changed") }.getString("status"))
    }

    @Test fun evaluationNeedsOriginalReadCoverageAndIndependentReviewer() {
        val t = Fixture(); val value = t.review(t.results())
        assertEquals("rejected", t.evaluate(value, read = false).getString("status"))
        for (author in listOf("idea", "peer", "critic-a", "lead", "planner", "analyst", "executor", "baseline")) {
            assertEquals(author, "rejected", t.evaluate(value, person = author, id = "self-$author").getString("status"))
        }
    }

    @Test fun emptyAndDuplicateComparisonsAreNotTeamGains() {
        val t = Fixture()
        assertEquals("continue", t.f.ref(t.evaluate(t.review(JSONArray(), "continue"))).getJSONObject(HOST).getString("state"))
        val result = t.f.ref(t.run(0))
        assertEquals("rejected", t.evaluate(t.review(JSONArray().put(result).put(result), "continue"), id = "duplicates").getString("status"))
    }

    @Test fun comparatorProtocolCannotChangeOrBeRegisteredAfterTrials() {
        val t = Fixture(); val results = t.results(); val value = t.review(results)
        for (variant in listOf("budget", "time", "dataset")) reject {
            CollaborationTeamComparison.evaluate(value, JSONObject().put("host_observations", t.observations), "reviewer", { ref, kinds ->
                val original = t.exact(ref, kinds)
                if (original.getString("object_id") != t.plans[1].getString("object_id")) original else JSONObject(original.toString()).apply {
                    when (variant) {
                        "budget" -> getJSONObject("body").getJSONObject("experiment_plan").put("budget_limit", 101)
                        "time" -> put("recorded_at", 201)
                        else -> getJSONObject("body").getJSONObject("experiment_plan").getJSONArray("cases").getJSONObject(0).put("metric", "easier")
                    }
                }
            }, { ref -> t.f.ledger.read(t.f.access(round = 20), ref.getString("evidence_id"), ref.getString("sha256")) }, {})
        }
    }

    @Test fun singleAgentControlCannotReuseOneParentOrHaveSeveralAuthors() {
        val t = Fixture()
        val spec = JSONObject(t.specs[0].toString()).apply { getJSONObject(CollaborationTeamComparison.FIELD).put("single_agent", t.a) }
        reject { CollaborationTeamComparison.plan(spec, t.idea, t.a, t::exact) }
        reject { CollaborationTeamComparison.plan(t.specs[0], t.idea, t.a) { ref, kinds -> t.exact(ref, kinds).let {
            if (it.getString("object_id") == t.f.baseline.getString("object_id")) JSONObject(it.toString())
                .put(HOST, JSONObject().put("contributors", JSONArray().put("extra"))) else it
        } } }
    }

    @Test fun peerTasksReachDurableDagAndPreserveBindingsAcrossRecovery() {
        val t = Fixture(); val f = t.f
        val work = f.work("challenge").apply { getJSONObject("innovation_work").put("innovation", t.a) }
        val completed = f.completed(f.record(), "lead", f.report(listOf(work)).toString(), true)
        val next = CollaborationGoalLoop.advance(completed, "lead", 1000, true, candidateWorkspace = { f.workspace })!!
        val member = next.definition.members.single { CollaborationInnovationWork.TASK in it.context }
        val binding = JSONObject(member.context.getValue(CollaborationInnovationWork.TASK))
        assertEquals("challenge", binding.getJSONObject("work").getString("phase"))
        assertEquals(t.a.getString("sha256"), binding.getJSONObject("work").getJSONObject("innovation").getString("sha256"))
        val response = f.work("respond").apply { getJSONObject("innovation_work").put("innovation", t.b).put("exchange", t.cb) }
        val admitted = CollaborationInnovationWork.plan(f.record(), listOf(response), { f.workspace }, f.access())
        val restored = f.record().copy(request = f.record().request.copy(context = f.record().request.context + (CollaborationInnovationWork.CLAIMS to admitted.claims)))
        assertEquals(admitted.claims, CollaborationInnovationWork.plan(restored, listOf(response), { f.reopen() }, f.access()).claims)
        response.getJSONObject("innovation_work").put("exchange", t.ca)
        reject { CollaborationInnovationWork.plan(restored, listOf(response), { f.workspace }, f.access()) }
    }

    @Test fun combinationWorkDoesNotNeedAnAlreadyExistingCombination() {
        val t = Fixture(); val work = t.f.work("combine").apply { getJSONObject("innovation_work").put(SYNTHESIS, t.synthesis) }
        val admitted = CollaborationInnovationWork.plan(t.f.record(), listOf(work), { t.f.workspace }, t.f.access())
        val binding = JSONObject(CollaborationInnovationWork.context(admitted.work.single()).getValue(CollaborationInnovationWork.TASK))
        assertEquals(t.synthesis.getString("sha256"), binding.getJSONObject("work").getJSONObject(SYNTHESIS).getString("sha256"))
        reject { CollaborationInnovationWork.plan(t.f.record(), listOf(work), { t.f.workspace }, t.f.access().copy(groupId = "other")) }
    }

    @Test fun genericLessonCannotBypassComparativeReview() {
        val t = Fixture(); val result = t.f.ref(t.run(0))
        reject { CollaborationTeamInvention.retention(JSONObject(), t.idea, t::exact) }
        assertFalse(result.getJSONObject(HOST).getJSONObject(CollaborationTeamComparison.FIELD).getBoolean("billing_independently_verified"))
    }

    @Test fun changingSourceMakesTeamLineageHistoricalAndBlocksReuse() {
        val t = Fixture(); val evaluation = t.f.ref(t.evaluate(t.review(t.results())))
        val raw = JSONObject(t.f.raw("parent-update", "innovation", t.f.ideaSpec, parents = JSONArray().put(t.f.opportunity)))
        raw.getJSONArray("workspace").getJSONObject(0).put("object_id", t.a.getString("object_id")).put("base_revision", 1)
        assertEquals("recorded", t.f.workspace.publish(t.f.access("idea", 12, "parent-update"), raw.toString(), 500).getString("status"))
        reject { CollaborationTeamInvention.retention(JSONObject().put(EVALUATION, evaluation), t.idea, t::exact) }
        assertNotNull(t.f.reopen().read(t.f.access(round = 20), evaluation.getString("object_id"), 1))
    }

    @Test fun localExecutionCombinesMechanismsInsteadOfAveragingAnswers() {
        val t = Fixture()
        val input = listOf("A", "a", "B", "b")
        fun score(method: Int): Int {
            val output = when (method) {
                0 -> input.map { it.lowercase() }
                1 -> input.distinct()
                2 -> input
                else -> input.map { it.lowercase() }.distinct()
            }
            return 12 - kotlin.math.abs(output.size - 2) - output.count { it != it.lowercase() }
        }
        val results = t.results { index, report -> val rows = report.getJSONArray("measurements")
            repeat(rows.length()) { i -> rows.getJSONObject(i).let { sample ->
                if (sample.getString("case_id") != "old") sample.put("value", score(if (sample.getString("variant") == "candidate") 3 else index))
            } }
        }
        assertEquals("eligible_for_scoped_team_reuse", t.f.ref(t.evaluate(t.review(results))).getJSONObject(HOST).getString("state"))
    }

    @Test fun splitComparisonsCannotHideCampaignOverspending() {
        val t = Fixture()
        val results = t.results { _, report -> report.getJSONArray("resource_totals").getJSONObject(1).put("coordination", 50) }
        assertEquals("rejected", t.evaluate(t.review(results)).getString("status"))
        val saved = t.f.ref(t.evaluate(t.review(results, "revise"), id = "budget-revision"))
        assertFalse(saved.getJSONObject(HOST).getBoolean("campaign_within_budget"))
        assertEquals("255", saved.getJSONObject(HOST).getJSONObject("campaign_costs").getString(t.idea.getString("sha256")))
    }

    @Test fun revisionCannotDiscardTeamLineage() {
        val t = Fixture()
        for (variant in listOf("missing", "null", "text")) {
            val value = JSONObject(t.ideaSpec.toString()).apply {
                if (variant == "missing") remove(SYNTHESIS) else put(SYNTHESIS, if (variant == "null") JSONObject.NULL else "discarded")
            }
            val raw = JSONObject(t.f.raw("team-update-$variant", "innovation", value, parents = t.parents))
            raw.getJSONArray("workspace").getJSONObject(0).put("object_id", t.idea.getString("object_id")).put("base_revision", 1)
            assertEquals("rejected", t.f.workspace.publish(t.f.access("lead", 12, "team-update-$variant"), raw.toString(), 500).getString("status"))
        }
    }

    @Test fun changedDatasetLeavesOldTeamResultHistorical() {
        val t = Fixture(); val evaluation = t.f.ref(t.evaluate(t.review(t.results())))
        val raw = JSONObject(t.f.raw("data-update", "artifact", JSONObject().put("input", "different")))
        raw.getJSONArray("workspace").getJSONObject(0).put("object_id", t.dataset.getString("object_id")).put("base_revision", 1)
        assertEquals("recorded", t.f.workspace.publish(t.f.access("data", 12, "data-update"), raw.toString(), 500).getString("status"))
        reject { CollaborationTeamInvention.retention(JSONObject().put(EVALUATION, evaluation), t.idea, t::exact) }
        assertNotNull(t.f.reopen().read(t.f.access(round = 20), evaluation.getString("object_id"), 1))
    }

    private fun reject(block: () -> Unit) = assertNotNull("Expected rejection", runCatching(block).exceptionOrNull())
}

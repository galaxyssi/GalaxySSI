package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.GAP
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.IDEA
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.PLAN
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.RESULT
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.LESSON
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.HOST

class CollaborationEvolutionTest {
    internal class Rows : CollaborationWorkspaceRows {
        val data = sortedMapOf<String, String>()
        var fail = false
        override fun read(key: String) = data[key]
        override fun page(prefix: String, after: String, limit: Int) = data.keys.filter { it.startsWith(prefix) && it > after }.take(limit)
        override fun commit(values: Map<String, String>) { check(!fail); data.putAll(values) }
    }
    private fun access(node: String, round: Long = 1) = CollaborationWorkspaceAccess("group", "run", "turn", round, node, node)
    private fun raw(vararg items: JSONObject) = JSONObject().put("format", CollaborationResearchArtifact.FORMAT)
        .put("summary", "Research contribution").put("candidates", JSONArray()).put("findings", JSONArray())
        .put("workspace", JSONArray(items.toList())).toString()
    private fun item(id: String, kind: String, value: JSONObject) = JSONObject().put("id", id).put("kind", kind)
        .put("title", id).put("body", JSONObject().put("content", "Complete original artifact: $id").put(kind, value))
    private fun ref(receipt: JSONObject): JSONObject {
        assertEquals(receipt.toString(), "recorded", receipt.optString("status"))
        return receipt.getJSONArray("revisions").getJSONObject(0)
    }
    private fun idea() = JSONObject().put("origin", "limitation").put("hypothesis", "A shared parsed index reduces duplicated work")
        .put("mechanism", "Reuse an immutable index").put("difference", "Avoid independent reparsing")
        .put("prior_art", "Not yet searched").put("novelty_scope", "not_checked").put("falsifier", "Latency is unchanged or accuracy falls")
        .put("domain", "retrieval").put("applies_when", "Identical authorized corpus").put("risks", "Stale cached evidence")
        .put("alternatives", JSONArray().put("Smaller corpus may explain the change"))
        .put("predictions", JSONArray().put(JSONObject().put("id", "p1").put("statement", "Latency improves with equal quality")
            .put("test", "Paired benchmark with old retrieval regression cases")))
    private fun case(id: String, purpose: String = "target") = JSONObject().put("id", id).put("purpose", purpose)
        .put("prediction", "Equal or better measured result").put("metric", "score").put("direction", "maximize")
        .put("minimum_gain", 1).put("tolerance", 0).put("repetitions", 2)
    internal class Fixture(val owner: CollaborationEvolutionTest, val planChange: (JSONObject) -> Unit = {}) {
        val rows = Rows()
        val ledger = CollaborationEvidenceLedger(Rows())
        fun workspace() = CollaborationResearchWorkspace(rows, evidence = ledger::references,
            evidenceReadCoverage = ledger::requireReadCoverage, evidenceOriginal = { access, ref ->
                ledger.read(access, ref.getString("evidence_id"), ref.getString("sha256")) })
        val workspace = workspace()
        val baseline = owner.ref(workspace.publish(owner.access("baseline"), owner.raw(owner.item("baseline", "artifact", JSONObject())), 10))
        val innovation = owner.ref(workspace.publish(owner.access("inventor"), owner.raw(owner.item("idea", IDEA, owner.idea())), 20))
        val spec = JSONObject().put("innovation", innovation).put("baseline", baseline).put("prediction_id", "p1")
            .put("method", "Paired benchmark").put("environment", "fixture-v1").put("budget_unit", "operations")
            .put("budget_limit", 100).put("source", JSONObject().put("origin", "android_cloud_tool").put("tool", "benchmark"))
            .put("report_pointer", "").put("cases", JSONArray().put(owner.case("target")).put(owner.case("old", "regression")))
            .apply(planChange)
        val plan = owner.ref(workspace.publish(owner.access("planner", 2), owner.raw(owner.item("plan", PLAN, spec)), 100))
        var lastRefs = JSONArray()
        var result: JSONObject? = null
        fun report(change: (JSONObject) -> Unit = {}): JSONObject {
            val measurements = JSONArray()
            val cases = spec.getJSONArray("cases")
            repeat(cases.length()) { index ->
                val case = cases.getJSONObject(index)
                repeat(case.getInt("repetitions")) { rep ->
                    for (variant in listOf("baseline", "candidate")) measurements.put(JSONObject().put("case_id", case.getString("id"))
                        .put("variant", variant).put("variant_sha256", (if (variant == "baseline") baseline else innovation).getString("sha256"))
                        .put("metric", "score").put("repetition", rep + 1).put("value", if (variant == "baseline") 10 else 12).put("budget_used", 50))
                }
            }
            return JSONObject().put("format", CollaborationEvolutionExperiment.FORMAT).put("plan_sha256", plan.getString("sha256"))
                .put("environment", "fixture-v1").put("budget_unit", "operations").put("measurements", measurements).apply(change)
        }
        fun trial(report: JSONObject = report(), started: Long = 200, tool: String = "benchmark",
                  origin: CollaborationEvidenceOrigin = CollaborationEvidenceOrigin.ANDROID_CLOUD_TOOL): JSONObject =
            ledger.record(owner.access("executor", 3), "trial-${lastRefs.length()}", tool, "{}", report.toString(), started, started + 1, origin)
                .also { lastRefs.put(it) }
        fun readEvidence(reader: CollaborationWorkspaceAccess) {
            repeat(lastRefs.length()) { index ->
                val ref = lastRefs.getJSONObject(index)
                var offset: Int? = 0
                while (offset != null) offset = ledger.readPage(reader, ref.getString("evidence_id"), ref.getString("sha256"), offset)!!.next
            }
        }
        fun publishResult(read: Boolean = true): JSONObject {
            val reader = owner.access("analyst", 4)
            if (read) readEvidence(reader)
            val receipt = workspace.publish(reader, owner.raw(owner.item("result", RESULT, JSONObject().put("plan", plan)
                .put("interpretation", "Measured under this fixture").put("limitations", "Not proof of general usefulness"))
                .put("observations", lastRefs)), 300)
            if (receipt.optString("status") == "recorded") result = owner.ref(receipt)
            return receipt
        }
        fun lesson(person: String = "reviewer", decision: String = "retain", read: Boolean = true): JSONObject {
            val reader = owner.access("$person-lesson", 5).copy(personId = person)
            if (read) readEvidence(reader)
            return workspace.publish(reader, owner.raw(owner.item("lesson", LESSON, JSONObject().put("result", result!!)
                .put("decision", decision).put("rationale", "Inspect benchmark and use only in registered scope")
                .put("applies_when", "Same dataset and environment").put("avoid_when", "Unknown domain")
                .put("procedure", "Use the saved indexed method").put("transfer_test", "New domain needs a new experiment")
                .put("rollback", baseline)).put("observations", lastRefs)), 400)
        }
    }

    @Test fun measuredInnovationBecomesDurableScopedLessonWithoutInstallingAnything() {
        val f = Fixture(this); f.trial()
        val result = ref(f.publishResult())
        assertEquals("measured_improvement", result.getJSONObject(HOST).getString("state"))
        val lesson = ref(f.lesson())
        assertEquals("eligible_for_scoped_reuse", lesson.getJSONObject(HOST).getString("state"))
        assertFalse(lesson.getJSONObject(HOST).getBoolean("automatically_installed"))
        val laterTask = access("new-member", 0).copy(runId = "next-run", turnId = "next-turn")
        val records = f.workspace().browseEvolution(laterTask).revisions
        assertEquals(4, records.size)
        assertTrue(records.any { it.getString("kind") == LESSON })
        assertEquals(f.baseline.getString("sha256"), lesson.getJSONObject(HOST).getJSONObject("rollback").getString("sha256"))
    }

    @Test fun hypothesisIsNotTruthAndModelCannotForgeHostStatus() {
        val w = CollaborationResearchWorkspace(Rows())
        val record = ref(w.publish(access("inventor"), raw(item("idea", IDEA, idea()).put(HOST, JSONObject().put("state", "verified")))))
        assertEquals("hypothesis_unverified", record.getJSONObject(HOST).getString("state"))
        assertEquals("not_checked", record.getJSONObject(HOST).getString("novelty"))
    }

    @Test fun gapKeepsAgentChosenLearningPriorityAndPreciseFailure() {
        val w = CollaborationResearchWorkspace(Rows())
        val gap = JSONObject().put("category", "verification").put("symptom", "No independent measurement")
            .put("needed_capability", "Paired benchmark").put("chosen_option", "learn").put("rationale", "High information gain")
            .put("learning_options", JSONArray().put(JSONObject().put("id", "learn").put("action", "Build a fixture")
                .put("expected_gain", "Test the hypothesis").put("cost", "Small").put("goal_relevance", "Direct")
                .put("verification", "Run baseline and candidate")))
        val saved = ref(w.publish(access("diagnoser"), raw(item("gap", GAP, gap))))
        assertEquals("diagnosis_and_priority_proposed", saved.getJSONObject(HOST).getString("state"))
        gap.put("chosen_option", "invented")
        val rejected = w.publish(access("other"), raw(item("gap", GAP, gap)))
        assertTrue(rejected.getString("reason").contains("learning_options"))
    }

    @Test fun globalNoveltyAndUnobservedSearchAreRejected() {
        for (scope in listOf("world_first", "searched_scope_only")) {
            val w = CollaborationResearchWorkspace(Rows())
            assertEquals("rejected", w.publish(access("inventor"), raw(item("idea", IDEA, idea().put("novelty_scope", scope)))).getString("status"))
        }
    }

    @Test fun combinationNeedsRealDistinctParentsAndPreservesContributors() {
        val w = CollaborationResearchWorkspace(Rows())
        val a = ref(w.publish(access("a"), raw(item("idea", IDEA, idea()))))
        val b = ref(w.publish(access("b"), raw(item("idea", IDEA, idea()))))
        val combined = item("combined", IDEA, idea().put("origin", "combination").put("transfer_conditions", "Matching constraints"))
            .put("parents", JSONArray().put(a).put(b))
        val result = ref(w.publish(access("c", 2), raw(combined)))
        assertEquals(listOf("a", "b", "c"), result.getJSONObject(HOST).getJSONArray("contributors").let { (0 until it.length()).map(it::getString) })
        combined.put("parents", JSONArray().put(a).put(a))
        assertEquals("rejected", w.publish(access("d", 2), raw(combined)).getString("status"))
    }

    @Test fun partialTrialsRemainIncompleteAndCannotBeRetained() {
        val f = Fixture(this)
        f.trial(f.report { it.getJSONArray("measurements").remove(0) })
        assertEquals("incomplete", ref(f.publishResult()).getJSONObject(HOST).getString("state"))
        assertEquals("rejected", f.lesson().getString("status"))
    }

    @Test fun regressionsPreventRetentionDespiteImprovedTarget() {
        val f = Fixture(this)
        f.trial(f.report { json -> val rows = json.getJSONArray("measurements"); repeat(rows.length()) {
            rows.getJSONObject(it).let { row -> if (row.getString("case_id") == "old" && row.getString("variant") == "candidate") row.put("value", 0) }
        } })
        assertEquals("regressed", ref(f.publishResult()).getJSONObject(HOST).getString("state"))
        assertEquals("rejected", f.lesson().getString("status"))
    }

    @Test fun equalityIsNotAnInnovationGain() {
        val f = Fixture(this) { it.getJSONArray("cases").getJSONObject(0).put("minimum_gain", 0) }
        f.trial(f.report { json -> val rows = json.getJSONArray("measurements"); repeat(rows.length()) { rows.getJSONObject(it).put("value", 10) } })
        assertEquals("inconclusive", ref(f.publishResult()).getJSONObject(HOST).getString("state"))
    }

    @Test fun improvementWithoutRegressionSuiteIsNotRetentionEligible() {
        val f = Fixture(this) { it.getJSONArray("cases").remove(1) }; f.trial()
        assertEquals("improved_without_regression_suite", ref(f.publishResult()).getJSONObject(HOST).getString("state"))
    }

    @Test fun oldObservationCannotBeUsedToPostSelectExperiment() {
        val f = Fixture(this); f.trial(started = 99)
        assertTrue(f.publishResult().getString("reason").contains("predates"))
    }

    @Test fun wrongToolOrOriginCannotServeAsExecutionEvidence() {
        val f = Fixture(this); f.trial(tool = "web_search")
        assertTrue(f.publishResult().getString("reason").contains("origin/tool"))
        val other = Fixture(this); other.trial(origin = CollaborationEvidenceOrigin.DESKTOP_CODEX_TOOL)
        assertTrue(other.publishResult().getString("reason").contains("origin/tool"))
    }

    @Test fun versionEnvironmentBudgetAndPlanBindingsAreChecked() {
        val mutations = listOf<(JSONObject) -> Unit>(
            { it.put("plan_sha256", "a".repeat(64)) }, { it.put("environment", "easier") }, { it.put("budget_unit", "unlimited") },
            { it.getJSONArray("measurements").getJSONObject(0).put("variant_sha256", "a".repeat(64)) },
            { it.getJSONArray("measurements").getJSONObject(0).put("budget_used", 101) })
        mutations.forEach { change -> val f = Fixture(this); f.trial(f.report(change)); assertEquals("rejected", f.publishResult().getString("status")) }
    }

    @Test fun fabricatedScoresAndNonfiniteNumbersCannotPass() {
        val f = Fixture(this)
        f.trial(f.report { it.getJSONArray("measurements").getJSONObject(0).put("value", "NaN") })
        assertTrue(f.publishResult().getString("reason").contains("finite decimal"))
        val noEvidence = Fixture(this)
        assertTrue(noEvidence.publishResult().getString("reason").contains("original tool observations"))
    }

    @Test fun duplicateSamplesAndUnregisteredCasesAreRejected() {
        val f = Fixture(this); f.trial(f.report { val rows = it.getJSONArray("measurements"); rows.put(rows.getJSONObject(0)) })
        assertTrue(f.publishResult().getString("reason").contains("Duplicate case"))
        val g = Fixture(this); g.trial(g.report { it.getJSONArray("measurements").getJSONObject(0).put("case_id", "easy-case") })
        assertTrue(g.publishResult().getString("reason").contains("unregistered"))
    }

    @Test fun multipleReportsCombineWithoutDuplicateExecution() {
        val f = Fixture(this)
        val all = f.report().getJSONArray("measurements")
        f.trial(f.report { it.put("measurements", JSONArray((0..3).map(all::getJSONObject))) })
        f.trial(f.report { it.put("measurements", JSONArray((4..7).map(all::getJSONObject))) })
        assertEquals("measured_improvement", ref(f.publishResult()).getJSONObject(HOST).getString("state"))
    }

    @Test fun independentReviewerMustReadAllOriginals() {
        val f = Fixture(this); f.trial()
        assertTrue(f.publishResult(read = false).getString("reason").contains("fully served"))
        val g = Fixture(this); g.trial(); ref(g.publishResult())
        assertTrue(g.lesson(read = false).getString("reason").contains("fully served"))
    }

    @Test fun selfReviewCannotPromoteAndNegativeExperienceSurvives() {
        for (person in listOf("inventor", "baseline", "planner", "executor")) {
            val f = Fixture(this); f.trial(); ref(f.publishResult())
            assertTrue(f.lesson(person).getString("reason").contains("independent"))
        }
        val f = Fixture(this); f.trial(); ref(f.publishResult())
        assertEquals("reject", ref(f.lesson(decision = "reject")).getJSONObject(HOST).getString("state"))
    }

    @Test fun plansAreImmutableAndStaleIdeasCannotBeCertified() {
        val f = Fixture(this)
        val revised = item("plan", PLAN, f.spec).put("object_id", f.plan.getString("object_id")).put("base_revision", 1)
        assertTrue(f.workspace.publish(access("planner-edit", 3), raw(revised)).getString("reason").contains("immutable"))
        ref(f.workspace.publish(access("edit", 3).copy(personId = "inventor"), raw(item("idea", IDEA, idea())
            .put("object_id", f.innovation.getString("object_id")).put("base_revision", 1))))
        f.trial()
        val oldResult = ref(f.publishResult())
        assertFalse(oldResult.getJSONObject(HOST).getBoolean("eligible_for_retention"))
        assertFalse(oldResult.getJSONObject(HOST).getBoolean("targets_current_at_publication"))
        assertEquals("record_not_current", f.lesson().getJSONObject(CollaborationRecordValidation.DETAIL).getString("code"))
        assertEquals("reject", ref(f.lesson(person = "negative-reviewer", decision = "reject")).getJSONObject(HOST).getString("state"))
        val directory = f.workspace.browseEvolution(access("reader", 6)).revisions
        assertEquals("historical_requires_revalidation", directory.single { it.getString("object_id") == oldResult.getString("object_id") }
            .getString("evolution_applicability"))
    }

    @Test fun revokedMemberCannotPublishNewEvolutionRecords() {
        val rows = Rows()
        val workspace = CollaborationResearchWorkspace(rows, accessAuthorized = { false })
        val receipt = workspace.publish(access("revoked"), raw(item("idea", IDEA, idea())))
        assertTrue(receipt.getString("reason").contains("access was removed"))
        assertTrue(workspace.browseEvolution(access("reader", 2)).revisions.isEmpty())
    }

    @Test fun scopedDirectoryHonorsBlindWorkPrivacyPaginationAndRestart() {
        val rows = Rows(); val w = CollaborationResearchWorkspace(rows)
        repeat(25) { ref(w.publish(access("person-$it"), raw(item("idea", IDEA, idea())))) }
        assertTrue(w.browseEvolution(access("independent")).revisions.isEmpty())
        assertTrue(w.browseEvolution(access("reader", 2).copy(groupId = "private-group")).revisions.isEmpty())
        val reopened = CollaborationResearchWorkspace(rows)
        var cursor = ""; val ids = mutableListOf<String>()
        do {
            val page = reopened.browseEvolution(access("reader", 2), cursor, 7)
            ids += page.revisions.map { it.getString("object_id") }; cursor = page.next.orEmpty()
        } while (cursor.isNotEmpty())
        assertEquals(25, ids.distinct().size)
    }

    @Test fun failedTransactionDoesNotPublishLearningIndexOrPartialIdea() {
        val rows = Rows(); val w = CollaborationResearchWorkspace(rows)
        rows.fail = true
        assertTrue(runCatching { w.publish(access("inventor"), raw(item("idea", IDEA, idea()))) }.isFailure)
        assertTrue(rows.data.isEmpty())
        rows.fail = false
        val input = raw(item("idea", IDEA, idea()))
        val first = w.publish(access("inventor"), input)
        assertEquals(first.toString(), CollaborationResearchWorkspace(rows).publish(access("inventor"), input).toString())
    }

    @Test fun nestedDesktopReportUsesSameHostComparator() {
        val f = Fixture(this) { it.put("report_pointer", "/item/aggregatedOutput").getJSONObject("source")
            .put("origin", "desktop_codex_tool").put("tool", "codex.commandExecution") }
        f.trial(JSONObject().put("item", JSONObject().put("aggregatedOutput", f.report().toString())), tool = "codex.commandExecution",
            origin = CollaborationEvidenceOrigin.DESKTOP_CODEX_TOOL)
        assertEquals("measured_improvement", ref(f.publishResult()).getJSONObject(HOST).getString("state"))
    }
}

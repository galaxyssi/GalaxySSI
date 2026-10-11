package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CollaborationMethodEvaluationsTest {
    private fun records(page: JSONObject) = page.getJSONArray("records").let { a -> (0 until a.length()).map(a::getJSONObject) }
    private fun later(x: CollaborationWorkflowSelectionTest.Fixture) = x.f.access().copy(runId = "next", turnId = "next", round = 0)

    private fun outcome(x: CollaborationWorkflowSelectionTest.Fixture, id: String, value: Int, review: String): JSONObject {
        val samples = JSONArray()
        for (variant in listOf("baseline", "candidate")) for (case in listOf("quality", "retained")) {
            val old = variant == "baseline"
            samples.put(JSONObject().put("case_id", case).put("variant", variant)
                .put("variant_sha256", (if (old) x.before else x.after).getString("sha256"))
                .put("workflow_sha256", (if (old) x.t.method else x.candidate).getString("sha256"))
                .put("dataset_sha256", x.f.baseline.getString("sha256")).put("metric", "score")
                .put("repetition", 1).put("budget_used", 1).put("value", if (old) 1 else value))
        }
        val report = JSONObject().put("format", CollaborationEvolutionExperiment.FORMAT).put("plan_sha256", x.plan.getString("sha256"))
            .put("environment", "fixture").put("budget_unit", "operations").put("measurements", samples)
        val observations = JSONArray().put(x.f.ledger.record(x.f.access("executor", 20), "trial-$id", "fixture.compare", "{}",
            report.toString(), 600, 601, CollaborationEvidenceOrigin.ANDROID_NATIVE_TOOL))
        x.f.read(x.f.access("analyst", 21, id), observations)
        val result = x.f.ref(x.f.publish(id, "experiment_result", JSONObject().put("plan", x.plan)
            .put("interpretation", "Synthetic later result").put("limitations", "Disclosed fixture only"), "analyst", 21, 700, observations))
        x.f.ref(x.f.publish("$id-review", "capability_lesson", JSONObject().put("result", result).put("decision", review)
            .put("rationale", "Do not discard contrary evidence").put("applies_when", "Fixture condition")
            .put("avoid_when", "Unknown environment").put("procedure", "Investigate cause before selecting")
            .put("transfer_test", "Fresh inputs").put("rollback", x.before), "arbiter", 22, 800))
        return result
    }

    @Test fun recallJoinsExactMethodToPlansObservedResultsAndReviewsAfterReopen() {
        val x = CollaborationWorkflowSelectionTest.Fixture()
        val page = x.f.reopen().methodEvaluations(later(x), x.candidate)
        val found = records(page)
        assertEquals(setOf("experiment_plan", "experiment_result", "capability_lesson"), found.map { it.getString("kind") }.toSet())
        assertEquals(3, found.size)
        assertTrue(found.all { it.getString("method_variant") == "candidate" })
        assertTrue(found.all { it.getJSONObject("plan").getString("sha256") == x.plan.getString("sha256") })
        val result = found.single { it.getString("kind") == "experiment_result" }
        assertEquals("measured_improvement", result.getString("measured_state"))
        assertEquals(2, result.getJSONObject("case_states").getInt("passed"))
        assertFalse(result.getBoolean("complete_read")); assertFalse(result.getBoolean("current_applicability_verified"))
        assertEquals("workspace", result.getJSONObject("read_original").getString("mode"))
        assertTrue(page.isNull("quality_effect")); assertFalse(page.getBoolean("causality_proven"))
        assertTrue(page.getString("guidance").contains("do not count them as independent trials"))
        assertTrue(records(x.f.reopen().methodEvaluations(later(x), x.t.method)).all { it.getString("method_variant") == "baseline" })
    }

    @Test fun laterInconclusiveAndRegressedExperimentsRemainAlongsidePositiveReview() {
        val x = CollaborationWorkflowSelectionTest.Fixture()
        outcome(x, "unchanged", 1, "revise")
        outcome(x, "worse", 0, "reject")
        val found = records(x.f.reopen().methodEvaluations(later(x), x.candidate))
        assertEquals(setOf("measured_improvement", "inconclusive", "regressed"), found.filter { it.getString("kind") == "experiment_result" }
            .map { it.getString("measured_state") }.toSet())
        assertEquals(setOf("retain", "revise", "reject"), found.filter { it.getString("kind") == "capability_lesson" }
            .map { it.getString("review_decision") }.toSet())
        assertTrue(found.filter { it.has("review_decision") }.all { it.getJSONObject("excerpts").has("avoid_when") })
        assertEquals(0, x.f.reopen().methodHistory(later(x), x.candidate).getJSONArray("records").length())
    }

    @Test fun originalOutcomeCannotBeOverwrittenByARevisedInterpretation() {
        val x = CollaborationWorkflowSelectionTest.Fixture()
        val saved = x.f.workspace.read(later(x), x.result.getString("object_id"), 1)!!
        val spec = JSONObject(saved.getJSONObject("body").getJSONObject("experiment_result").toString()).put("interpretation", "Clarified limitations")
        val raw = JSONObject(x.f.raw("replacement", "experiment_result", spec, x.refs))
        raw.getJSONArray("workspace").getJSONObject(0).put("object_id", x.result.getString("object_id")).put("base_revision", 1)
        val access = x.f.access("analyst", 30, "replacement")
        x.f.read(access, x.refs)
        assertEquals("rejected", x.f.workspace.publish(access, raw.toString(), 1000).getString("status"))
        val versions = records(x.f.reopen().methodEvaluations(later(x), x.candidate))
            .filter { it.getString("object_id") == x.result.getString("object_id") }.map { it.getInt("revision") }.toSet()
        assertEquals(setOf(1), versions)
    }

    @Test fun discoveryAndExecutionHistoryExposeEvaluationSelectorWithoutPretendingTheyWereRead() {
        val x = CollaborationWorkflowSelectionTest.Fixture()
        val found = x.f.reopen().searchCapabilities(later(x), "parsing").getJSONArray("records")
        val method = (0 until found.length()).map(found::getJSONObject).single { it.getString("object_id") == x.candidate.getString("object_id") }
        val selector = method.getJSONObject("evaluation_recall")
        assertEquals("method_history", selector.getString("mode")); assertEquals("evaluations", selector.getString("view"))
        assertEquals(x.candidate.getString("sha256"), selector.getString("sha256"))
        assertEquals(selector.toString(), x.f.reopen().methodHistory(later(x), x.candidate).getJSONObject("evaluation_recall").toString())
    }

    @Test fun noMethodNameMatchingOrInheritanceOfAnotherVersionOutcome() {
        val x = CollaborationWorkflowSelectionTest.Fixture()
        val different = x.f.ref(x.f.publish("same-name-new-method", CollaborationWorkflowMethod.KIND,
            JSONObject(x.t.spec.toString()), round = 30))
        val empty = x.f.reopen().methodEvaluations(later(x), different)
        assertTrue(records(empty).isEmpty()); assertTrue(empty.getBoolean("scan_complete"))
        assertTrue(empty.getString("guidance").contains("unknown evaluated history"))
        assertTrue(runCatching { x.f.reopen().methodEvaluations(later(x), JSONObject(x.candidate.toString()).put("sha256", "a".repeat(64))) }.isFailure)
        assertTrue(runCatching { x.f.reopen().methodEvaluations(later(x), x.plan) }.isFailure)
    }

    @Test fun comparisonsDoNotLeakHiddenPlansCounterpartsOtherGroupsOrRevokedAccess() {
        val x = CollaborationWorkflowSelectionTest.Fixture()
        val limited = x.f.access("isolated", 6).copy(dependencyNodes = setOf("conditional-candidate", "selection-result"))
        assertNotNull(x.f.workspace.read(limited, x.candidate.getString("object_id"), 1))
        assertTrue(records(x.f.workspace.methodEvaluations(limited, x.candidate)).isEmpty())
        assertTrue(runCatching { x.f.reopen().methodEvaluations(later(x).copy(groupId = "elsewhere"), x.candidate) }.isFailure)
        val revoked = CollaborationResearchWorkspace(x.f.rows, accessAuthorized = { false })
        assertTrue(runCatching { revoked.methodEvaluations(later(x), x.candidate) }.isFailure)
    }

    @Test fun boundedPaginationIncludesEmptyPagesRejectsChangedScopeAndReturnsAllRecords() {
        val x = CollaborationWorkflowSelectionTest.Fixture()
        repeat(220) { index -> x.f.ref(x.f.publish("unrelated-$index", "workflow_method", JSONObject(x.t.spec.toString()), round = 30)) }
        val access = later(x)
        var page = x.f.reopen().methodEvaluations(access, x.candidate)
        assertFalse(page.getBoolean("scan_complete"))
        val cursor = page.getString("next_cursor")
        assertTrue(runCatching { x.f.reopen().methodEvaluations(access, x.t.method, cursor) }.isFailure)
        assertTrue(runCatching { x.f.reopen().methodEvaluations(access.copy(personId = "other"), x.candidate, cursor) }.isFailure)
        assertTrue(runCatching { x.f.reopen().methodEvaluations(access.copy(pinnedReads = setOf("changed")), x.candidate, cursor) }.isFailure)
        val found = mutableListOf<JSONObject>()
        var pages = 0
        do {
            found += records(page); pages++
            if (page.isNull("next_cursor")) break
            page = x.f.reopen().methodEvaluations(access, x.candidate, page.getString("next_cursor"))
        } while (true)
        assertEquals(3, found.size); assertTrue(pages >= 3)
        assertEquals(3, found.map { it.getString("object_id") }.toSet().size)
        for (bad in listOf("not-json", "{}", "x".repeat(513)))
            assertTrue(runCatching { x.f.reopen().methodEvaluations(access, x.candidate, bad) }.isFailure)
    }

    @Test fun resultPageLimitIsNotALimitOnContraryEvidence() {
        val x = CollaborationWorkflowSelectionTest.Fixture()
        repeat(9) { outcome(x, "negative-$it", 0, "reject") }
        val access = later(x)
        var page = x.f.reopen().methodEvaluations(access, x.candidate)
        assertEquals(CollaborationMethodEvaluations.RESULT_PAGE, records(page).size)
        val found = mutableListOf<JSONObject>()
        do {
            found += records(page)
            if (page.isNull("next_cursor")) break
            page = x.f.reopen().methodEvaluations(access, x.candidate, page.getString("next_cursor"))
        } while (true)
        assertEquals(21, found.size)
        assertEquals(21, found.map { it.getString("object_id") }.toSet().size)
        assertEquals(9, found.count { it.optString("review_decision") == "reject" })
    }
}

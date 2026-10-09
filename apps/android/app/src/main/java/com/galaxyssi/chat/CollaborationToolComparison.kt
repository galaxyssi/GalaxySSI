package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.text
import com.galaxyssi.chat.CollaborationExecutableTool.TEST

/** Paired case outcomes guide the next decision; they neither choose a method nor certify learning. */
internal object CollaborationToolComparison {
    const val KIND = "tool_test_comparison"

    fun lineageReferences(host: JSONObject): List<Pair<String, JSONObject>> = listOf("baseline", "candidate").flatMap { name ->
        val side = host.getJSONObject(name)
        listOf(TEST, CollaborationExecutableTool.TOOL).map { kind -> kind to side.getJSONObject(kind) }
    }

    fun evaluate(value: JSONObject, revision: JSONObject, exact: (JSONObject, Set<String>) -> JSONObject,
                 original: (JSONObject) -> JSONObject?, coverage: (JSONObject) -> Unit): JSONObject {
        require(value.keys().asSequence().toSet() == setOf("purpose", "baseline", "candidate", "interpretation", "limitations")) {
            "Tool comparison needs purpose, baseline, candidate, interpretation and limitations"
        }
        listOf("purpose", "interpretation", "limitations").forEach { text(value, it) }
        coverage(revision)
        fun observed(name: String): CollaborationExecutableTool.ObservedTest {
            val selected = value.getJSONObject(name)
            require(selected.keys().asSequence().toSet() == setOf(TEST, "observation")) {
                "$name needs only an exact tool_test_plan and original observation"
            }
            return CollaborationExecutableTool.observedTest(selected, revision, exact, original).also { test ->
                require(listOf("group_id", "run_id", "turn_id").all {
                    test.observation.getString(it) == revision.getString(it)
                }) { "Compare actual tests from this goal; historical claims are not a new paired evaluation" }
            }
        }
        val baseline = observed("baseline")
        val candidate = observed("candidate")
        require(baseline.observation.getString("evidence_id") != candidate.observation.getString("evidence_id")) {
            "A single observation cannot be both sides of a tool comparison"
        }
        val before = baseline.plan.getJSONObject("body").getJSONObject(TEST)
        val after = candidate.plan.getJSONObject("body").getJSONObject(TEST)
        listOf("environment", "purpose", "oracle_basis", "coverage_gaps", "cases").forEach { field ->
            require(CollaborationToolFeedback.difference(before.get(field), after.get(field)) == null) {
                "Test contract changed at $field; compare both methods on the same preserved cases, not different scores"
            }
        }
        require(CollaborationToolFeedback.difference(baseline.receipt.getJSONObject("report").getJSONObject("runtime"),
            candidate.receipt.getJSONObject("report").getJSONObject("runtime")) == null) {
            "Observed Python runtime identities differ; do not attribute the difference to the method"
        }
        val oldChecks = baseline.checked.getJSONArray("checks")
        val newChecks = candidate.checked.getJSONArray("checks")
        val byId = (0 until newChecks.length()).associate { newChecks.getJSONObject(it).getString("id") to newChecks.getJSONObject(it) }
        val counts = linkedMapOf("improved" to 0, "regressed" to 0, "both_passed" to 0, "both_failed" to 0)
        val cases = JSONArray()
        repeat(oldChecks.length()) { index ->
            val old = oldChecks.getJSONObject(index)
            val new = byId.getValue(old.getString("id"))
            val outcome = when {
                old.getBoolean("passed") && new.getBoolean("passed") -> "both_passed"
                old.getBoolean("passed") -> "regressed"
                new.getBoolean("passed") -> "improved"
                else -> "both_failed"
            }
            counts[outcome] = counts.getValue(outcome) + 1
            cases.put(JSONObject().put("id", old.getString("id")).put("purpose", old.getString("purpose"))
                .put("outcome", outcome).put("baseline", old).put("candidate", new))
        }
        return JSONObject().put("state", "observed_paired_case_outcomes").put("case_count", cases.length())
            .put("counts", JSONObject().apply { counts.forEach { (key, count) -> put(key, count) } }).put("cases", cases)
            .put("baseline", side(baseline)).put("candidate", side(candidate))
            .put("source_changed", baseline.receipt.getString("source_sha256") != candidate.receipt.getString("source_sha256"))
            .put("candidate_all_passed", candidate.checked.getBoolean("passed"))
            .put("oracle_truth_verified", false).put("unseen_cases_verified", false).put("environment_equivalence_proven", false)
            .put("independent_attempts_verified", false).put("causal_contribution", JSONObject.NULL)
            .put("capability_gain_verified", false).put("automatically_adopted", false).put("grants_permissions", false)
    }

    private fun side(test: CollaborationExecutableTool.ObservedTest) = JSONObject()
        .put(TEST, CollaborationExecutableTool.ref(test.plan)).put(CollaborationExecutableTool.TOOL, CollaborationExecutableTool.ref(test.tool))
        .put("observation", JSONObject().put("evidence_id", test.observation.getString("evidence_id"))
            .put("sha256", test.observation.getString("sha256")))
        .put("source_sha256", test.receipt.getString("source_sha256"))
        .put("execution_source_sha256", test.receipt.getString("execution_source_sha256"))
        .put("passed", test.checked.getBoolean("passed"))

    fun rules() = """
        After revising a generated tool, publish tool_test_comparison to inspect actual paired outcomes, including failures:
        {purpose,baseline:{tool_test_plan:<exact ref>,observation:{evidence_id,sha256}},
          candidate:{tool_test_plan:<exact ref>,observation:{evidence_id,sha256}},interpretation,limitations}.
        Cite and read both full native test observations. Both tests must have complete reports from this goal, matching declared
        environment, purpose, oracle_basis, coverage_gaps, case inputs/expected values/order, and observed Python runtime identity.
        A tool source or its version may differ. Historical exact versions remain readable; this does not approve their reuse.
        The host recomputes each case and reports improved, regressed, both_passed and both_failed with actual/expected details.
        Keep regressions and failures; do not replace them with a net score or repeat side effects to obtain a missing receipt.
        Decide whether to revise, seek a counterexample, retain alternatives or arrange independent validation from this evidence.
        Matching runtimes is not equivalent environments or equal cost. These finite, disclosed cases establish neither unseen
        generalization, independent attempts, causal peer contribution nor capability growth. No release, retention or goal acceptance
        is automatic; use the existing independent review, experiment and regression mechanisms before adopting a method.
    """.trimIndent()
}

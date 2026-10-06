package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.text

/** Immutable local trials expose actual counterexamples before goal acceptance or capability retention. */
internal object CollaborationNumericModelTrial {
    const val KIND = "numeric_model_trial"

    fun evaluate(value: JSONObject, revision: JSONObject, exact: (JSONObject, Set<String>) -> JSONObject): JSONObject {
        val fields = setOf("purpose", "reference_basis", "limitations", "validator", "computation")
        require(value.keys().asSequence().toSet() == fields + if (value.has("previous_trial")) setOf("previous_trial") else emptySet()) {
            "numeric_model_trial needs purpose, reference_basis, limitations, validator, computation and optional previous_trial"
        }
        listOf("purpose", "reference_basis", "limitations").forEach { text(value, it) }
        val spec = value.getJSONObject("validator")
        val result = CollaborationNumericModelValidator.evaluate(spec, value.getJSONObject("computation"))
        val host = JSONObject().put("state", "numeric_replay_recorded_not_generalized").put("evaluation", result)
            .put("eligible_for_retention", false).put("reference_truth_verified", false).put("goal_accepted", false)
        if (value.has("previous_trial")) {
            val reference = value.getJSONObject("previous_trial")
            val previous = exact(reference, setOf(KIND))
            val parents = revision.getJSONArray("parents")
            require((0 until parents.length()).any { CollaborationResearchCandidates.same(parents.getJSONObject(it), reference) }) {
                "Preserve the exact previous numeric trial in parents"
            }
            val prior = previous.getJSONObject("body").getJSONObject(KIND)
            require(CollaborationNumericModelValidator.binding(spec) == CollaborationNumericModelValidator.binding(prior.getJSONObject("validator"))) {
                "A same-case model revision cannot change inputs, reference values or tolerances; changed cases need a separately identified study"
            }
            val before = CollaborationNumericModelValidator.evaluate(prior.getJSONObject("validator"), prior.getJSONObject("computation"))
            fun outcomes(report: JSONObject): Map<String, JSONObject> = report.getJSONArray("checks").let { rows ->
                (0 until rows.length()).associate { rows.getJSONObject(it).let { row -> row.getString("id") to row } }
            }
            val old = outcomes(before)
            val now = outcomes(result)
            fun errorChange(id: String): Int? = if (old.getValue(id).has("absolute_error") && now.getValue(id).has("absolute_error"))
                now.getValue(id).getString("absolute_error").toBigDecimal()
                    .compareTo(old.getValue(id).getString("absolute_error").toBigDecimal()) else null
            host.put("comparison", JSONObject().put("previous_trial", CollaborationResearchCandidates.reference(previous))
                .put("same_registered_cases", true).put("model_changed", before.getString("model_sha256") != result.getString("model_sha256"))
                .put("previous_failed_cases", before.getInt("failed_cases")).put("current_failed_cases", result.getInt("failed_cases"))
                .put("improved_case_ids", JSONArray(old.keys.filter { !old.getValue(it).getBoolean("passed") && now.getValue(it).getBoolean("passed") }))
                .put("regressed_case_ids", JSONArray(old.keys.filter { old.getValue(it).getBoolean("passed") && !now.getValue(it).getBoolean("passed") }))
                .put("error_reduced_case_ids", JSONArray(old.keys.filter { errorChange(it) == -1 }))
                .put("error_increased_case_ids", JSONArray(old.keys.filter { errorChange(it) == 1 }))
                .put("domain_recovered_case_ids", JSONArray(old.keys.filter { old.getValue(it).has("error") && !now.getValue(it).has("error") }))
                .put("domain_failed_case_ids", JSONArray(old.keys.filter { !old.getValue(it).has("error") && now.getValue(it).has("error") }))
                .put("meaning", "same_case_replay_comparison_not_held_out_transfer_or_causal_team_gain"))
        }
        return host
    }

    fun rules() = """
        Pure numeric work can use numeric_model_trial through ordinary workspace publication; cloud and Desktop members use the
        same scoped publish/recall bridge. The App replays the expression locally, without Python, a second model or external I/O.
        numeric_model_trial:{purpose,reference_basis,limitations,validator:{id:"numeric_model_cases.v1",variables:["x"],
          cases:[{id:"case",input:{x:2},expected:4,absolute_tolerance:0.001}]},
          computation:{validator_id:"numeric_model_cases.v1",model:{op:"mul",args:[{variable:"x"},{variable:"x"}]}},
          previous_trial:<optional exact numeric_model_trial ref>}.
        Expressions use {constant:<finite decimal>}, {variable:<registered name>} or {op,args}; unary neg,abs,exp,expm1,log,log1p,sqrt,sin,cos;
        binary add,sub,mul,div,pow,min,max. No code, calls, files, network or mutable external state. Every input and intermediate is
        finite float64; final absolute errors use decimal comparison with the preserved reference/tolerance, never model-written scores.
        Per-plan replay envelope: 4096 cases, 64 variables, 2048 expression nodes, depth 48 and 2000000 case-node operations.
        These bound local CPU/memory use, not goal/round duration. Unsupported models require a suitable alternative adapter.
        A valid failed trial is SAVED, not rejected. Read host_evolution.evaluation: every actual/error, failed/domain case counts,
        worst counterexample and exact specification/model hashes. Invalid expression syntax is a different publication error.
        To revise, publish a NEW trial with previous_trial and the exact prior in parents. Keep all inputs, references and tolerances;
        the host recomputes both versions and lists improved and regressed cases. Changed cases require a separately identified study.
        improved/regressed_case_ids track pass-status transitions; error_reduced/increased_case_ids compare finite absolute errors
        even if both versions still fail. domain_recovered/failed_case_ids expose domain transitions without inventing error scores.
        This does not mandate a fixed iteration count or decide your next model. Use counterexamples to change actual computations.
        Repeating a model sets model_changed=false; execution activity is not evidence of progress. Retain disagreement and regressions.
        Reference values remain supplied claims: cite their sources, check oracle validity, avoid leakage, and test fresh held-out cases
        before claiming generalization. Neither a passing trial nor a same-case comparison automatically retains a capability.
        To qualify only this finite computation at final acceptance, first preserve the SAME validator in a computational criterion
        with the literal requirement "${CollaborationNumericModelValidator.REQUIREMENT}". Deliver the exact computation in body.computation,
        plus substantive content and an independent exact-version acceptance review. Host acceptance replays every preserved case.
        observed here means actual local recomputation, NOT a physical observation or proof that references are independently true.
        Keep original broader accuracy, provenance, uncertainty, transfer and physical requirements separate; never weaken them to fit this adapter.
    """.trimIndent()
}

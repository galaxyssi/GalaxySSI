package com.galaxyssi.chat

import java.math.BigDecimal
import org.json.JSONArray
import org.json.JSONObject
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.HOST
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.IDEA
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.PLAN
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.RESULT
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.objects
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.text
import com.galaxyssi.chat.CollaborationTeamInvention.SYNTHESIS

/** Reuses paired experiments for ablations; all controls share a preregistered protocol and budget. */
internal object CollaborationTeamComparison {
    const val FIELD = "team_comparison"
    private val CONTROLS = setOf("artifact", "proposal", IDEA)

    fun plan(spec: JSONObject, idea: JSONObject, baseline: JSONObject, exact: (JSONObject, Set<String>) -> JSONObject): JSONObject? {
        val value = spec.optJSONObject(FIELD) ?: return null
        val synthesis = exact(idea.getJSONObject(HOST).getJSONObject(SYNTHESIS), setOf(SYNTHESIS))
        val single = exact(value.getJSONObject("single_agent"), CONTROLS)
        val sources = objects(synthesis.getJSONObject("body").getJSONObject(SYNTHESIS), "contributions").map { it.getJSONObject("innovation") }
        require(single.getString("object_id") != idea.getString("object_id") && sources.none { it.getString("object_id") == single.getString("object_id") } &&
            CollaborationTeamInvention.authors(single).size == 1) { "Single-agent control must be a distinct single-author method, not a team parent" }
        require((sources + single).any { same(it, baseline) }) { "Compare the combination against a registered parent or single-agent control" }
        require(text(value, "accounting") == "end_to_end") { "Account for preparation, coordination and execution, not only the final trial" }
        text(value, "resource_scope")
        val datasets = objects(spec, "cases").map { case -> ref(exact(case.getJSONObject("dataset"), setOf("artifact"))) }
        return JSONObject().put("single_agent", ref(single)).put(SYNTHESIS, ref(synthesis))
            .put("datasets", JSONArray(datasets.distinctBy { it.getString("object_id") + it.getString("sha256") }))
            .put("accounting", "end_to_end").put("billing_independently_verified", false)
    }

    fun collect(report: JSONObject, accounting: JSONObject) {
        val rows = report.optJSONArray("resource_totals") ?: return
        repeat(rows.length()) { index ->
            val row = rows.getJSONObject(index)
            val variant = text(row, "variant")
            require(variant in setOf("baseline", "candidate") && !accounting.has(variant)) { "One resource total per variant across all experiment observations" }
            val values = listOf("preparation", "coordination", "execution").map { key -> decimal(row, key).also {
                require(it >= BigDecimal.ZERO) { "Resource totals cannot be negative" }
            } }
            accounting.put(variant, JSONObject(row.toString()).put("total", values.fold(BigDecimal.ZERO, BigDecimal::add).toPlainString()))
        }
    }

    fun accounting(spec: JSONObject, totals: JSONObject, trialCosts: Map<String, BigDecimal>): JSONObject {
        for (variant in listOf("baseline", "candidate")) totals.optJSONObject(variant)?.let { row ->
            require(decimal(row, "total") <= decimal(spec, "budget_limit")) { "End-to-end $variant cost exceeded the common budget; preserve as a failed experiment" }
            require(decimal(row, "execution") >= trialCosts.getOrDefault(variant, BigDecimal.ZERO)) { "Execution total omits observed trial costs" }
        }
        return JSONObject().put("complete", totals.has("baseline") && totals.has("candidate"))
            .put("totals", totals).put("billing_independently_verified", false)
    }

    fun evaluate(value: JSONObject, revision: JSONObject, person: String, exact: (JSONObject, Set<String>) -> JSONObject,
                 original: (JSONObject) -> JSONObject?, coverage: (JSONObject) -> Unit): JSONObject {
        val idea = exact(value.getJSONObject("innovation"), setOf(IDEA))
        if (value.optString("decision") == "retain") CollaborationInnovationValidation.currentIdea(idea, exact)
        val synthesis = exact(idea.getJSONObject(HOST).getJSONObject(SYNTHESIS), setOf(SYNTHESIS))
        val decision = text(value, "decision")
        require(decision in setOf("continue", "revise", "reject", "retain")) { "Unknown team evaluation decision" }
        listOf("rationale", "limitations", "next_action", "harness_review").forEach { text(value, it) }
        val blockers = value.getJSONArray("unresolved")
        repeat(blockers.length()) { require(blockers.opt(it) is String && blockers.getString(it).isNotBlank()) { "Name each unresolved issue" } }
        val comparisons = value.getJSONArray("results")
        val requiredParents = objects(synthesis.getJSONObject("body").getJSONObject(SYNTHESIS), "contributions").map { it.getJSONObject("innovation") }
        val seen = hashSetOf<String>()
        val authors = CollaborationTeamInvention.authors(idea).toMutableSet()
        val observations = revision.getJSONArray("host_observations")
        if (observations.length() > 0) coverage(revision)
        val savedResults = JSONArray()
        var signature: String? = null
        var single: JSONObject? = null
        var allPass = true
        var latestRegistration = Long.MIN_VALUE
        var earliestTrial = Long.MAX_VALUE
        val campaignCosts = linkedMapOf<String, BigDecimal>()
        var ceiling: BigDecimal? = null
        repeat(comparisons.length()) { index ->
            val result = exact(comparisons.getJSONObject(index), setOf(RESULT))
            val host = result.getJSONObject(HOST)
            require(same(idea, host.getJSONObject("innovation"))) { "Team comparison result belongs to another combined idea" }
            val plan = exact(host.getJSONObject("plan"), setOf(PLAN))
            if (decision == "retain") CollaborationInnovationValidation.checkRecord(plan, exact)
            val spec = plan.getJSONObject("body").getJSONObject(PLAN)
            ceiling = decimal(spec, "budget_limit")
            val config = requireNotNull(plan.getJSONObject(HOST).optJSONObject(FIELD)) { "Every comparison must preregister team_comparison" }
            val control = exact(host.getJSONObject("baseline"), CONTROLS)
            require(seen.add(control.getString("object_id"))) { "Do not cherry-pick multiple results for one control; preserve a new campaign instead" }
            val comparator = exact(config.getJSONObject("single_agent"), CONTROLS)
            if (single == null) single = comparator else require(same(single!!, comparator)) { "Single-agent control changed between comparisons" }
            // Ignore only the control itself: cases, datasets, source, method and costs must match exactly.
            val protocol = JSONObject(spec.toString()).apply { remove("baseline") }
            val digest = AgentNativeJsonCodec.sha256(canonical(protocol))
            if (signature == null) signature = digest else require(signature == digest) { "Comparisons changed registered conditions, datasets or budgets" }
            latestRegistration = maxOf(latestRegistration, plan.getLong("recorded_at"))
            listOf(result, plan, control).forEach { authors += CollaborationTeamInvention.authors(it) }
            host.getJSONArray("trial_authors").let { a -> repeat(a.length()) { authors += a.getString(it) } }
            val refs = result.getJSONArray("host_observations")
            repeat(refs.length()) { i ->
                val source = refs.getJSONObject(i)
                require((0 until observations.length()).any { j -> observations.getJSONObject(j).let {
                    it.optString("evidence_id") == source.getString("evidence_id") && it.optString("sha256") == source.getString("sha256")
                } }) { "Read and cite all original comparison reports, including negative results" }
                val observed = requireNotNull(original(source)) { "Original team comparison report unavailable or isolated" }
                earliestTrial = minOf(earliestTrial, observed.getLong("started_at"))
            }
            allPass = allPass && host.optBoolean("eligible_for_retention") && host.optJSONObject(FIELD)?.optBoolean("complete") == true
            host.optJSONObject(FIELD)?.optJSONObject("totals")?.let { totals ->
                for ((variant, method) in listOf("baseline" to control, "candidate" to idea)) totals.optJSONObject(variant)?.let { row ->
                    val id = method.getString("sha256")
                    campaignCosts[id] = campaignCosts.getOrDefault(id, BigDecimal.ZERO) + decimal(row, "total")
                }
            }
            savedResults.put(ref(result))
        }
        require(comparisons.length() == 0 || latestRegistration <= earliestTrial) { "Register all comparator plans before any campaign trial; do not add easy controls after seeing scores" }
        val complete = single != null && (requiredParents + single!!).all { it.getString("object_id") in seen } && seen.size == requiredParents.size + 1
        val independent = person !in authors
        val withinBudget = ceiling != null && campaignCosts.isNotEmpty() && campaignCosts.values.all { it <= ceiling!! }
        if (decision == "retain") {
            require(complete) { "team_evaluation.results: comparisons=$seen; require every source idea and a distinct single-agent control" }
            require(allPass) { "team_evaluation.results: a comparison is incomplete, non-improving or regressed; inspect each host_evolution and cost record" }
            require(withinBudget) { "team_evaluation.campaign_costs=$campaignCosts exceed the shared budget_limit=$ceiling" }
            require(independent) { "team_evaluation.reviewer=$person is a contributor; independent evidence review is required" }
            require(blockers.length() == 0) { "team_evaluation.unresolved still contains ${blockers.length()} blockers; keep the decision non-retained" }
        }
        return JSONObject().put("state", if (decision == "retain") "eligible_for_scoped_team_reuse" else decision)
            .put("innovation", ref(idea)).put(SYNTHESIS, ref(synthesis)).put("results", savedResults)
            .put("comparisons_complete", complete).put("comparisons_passed", allPass && complete).put("independent_review", independent)
            .put("campaign_within_budget", withinBudget).put("campaign_costs", JSONObject(campaignCosts.mapValues { it.value.toPlainString() }))
            .put("general_team_superiority_proven", false).put("meaning", "scoped_reported_comparison_not_cognitive_independence_or_scientific_proof")
    }

    private fun canonical(value: Any?): Any? = when (value) {
        is JSONObject -> value.keys().asSequence().associateWith { canonical(value.get(it)) }
        is JSONArray -> (0 until value.length()).map { canonical(value.get(it)) }
        JSONObject.NULL -> null
        else -> value
    }
    private fun decimal(value: JSONObject, key: String) = CollaborationEvolutionExperiment.decimal(value, key)
    private fun ref(record: JSONObject) = CollaborationResearchCandidates.reference(record)
    private fun same(a: JSONObject, b: JSONObject) = CollaborationResearchCandidates.same(a, b)
}

package com.galaxyssi.chat

import java.math.BigDecimal
import java.math.MathContext
import org.json.JSONArray
import org.json.JSONObject
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.IDEA
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.PLAN
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.objects
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.text

/** Recomputes preregistered comparisons from original tool output, not model-supplied scores. */
internal object CollaborationEvolutionExperiment {
    const val FORMAT = "galaxyssi.experiment-measurements.v1"

    fun plan(value: JSONObject, exact: (JSONObject, Set<String>) -> JSONObject): JSONObject {
        val idea = exact(value.getJSONObject("innovation"), setOf(IDEA))
        val baseline = exact(value.getJSONObject("baseline"), setOf("proposal", "artifact", IDEA))
        require(idea.getString("object_id") != baseline.getString("object_id")) { "Compare against a distinct preserved baseline" }
        val predictions = idea.getJSONObject("body").getJSONObject(IDEA).getJSONArray("predictions")
        require((0 until predictions.length()).any { predictions.getJSONObject(it).getString("id") == text(value, "prediction_id") }) {
            "Experiment must test an existing innovation prediction"
        }
        listOf("method", "environment", "budget_unit", "report_pointer").forEach { key ->
            if (key == "report_pointer") require(value.opt(key) is String &&
                (value.getString(key).isEmpty() || value.getString(key).startsWith('/'))) { "report_pointer must be a JSON pointer (empty selects root)" }
            else text(value, key)
        }
        require(decimal(value, "budget_limit") > BigDecimal.ZERO) { "budget_limit must be positive" }
        val source = value.getJSONObject("source")
        require(text(source, "origin") in CollaborationEvidenceOrigin.entries.map { it.wireValue }) { "Unknown observation origin" }
        val tool = text(source, "tool")
        require(!tool.contains("recall", ignoreCase = true) && tool != ResearchEvidenceAudit.TOOL) {
            "A recall or member assessment is not a new experimental execution"
        }
        val cases = objects(value, "cases")
        require(cases.map { text(it, "id") }.distinct().size == cases.size) { "Experiment case IDs must be unique" }
        require(cases.any { it.optString("purpose") == "target" }) { "An experiment needs a target case" }
        cases.forEach { case ->
            text(case, "metric"); text(case, "prediction")
            require(text(case, "purpose") in setOf("target", "regression", "transfer")) { "Invalid experiment case purpose" }
            require(text(case, "direction") in setOf("maximize", "minimize")) { "Invalid metric direction" }
            require(decimal(case, "minimum_gain") >= BigDecimal.ZERO && decimal(case, "tolerance") >= BigDecimal.ZERO) {
                "minimum_gain and tolerance must be nonnegative"
            }
            require(case.opt("repetitions") is Int && case.getInt("repetitions") > 0) { "repetitions must be a positive integer chosen for this experiment" }
        }
        return JSONObject().put("state", "preregistered_not_executed")
            .put("innovation", CollaborationResearchCandidates.reference(idea)).put("baseline", CollaborationResearchCandidates.reference(baseline))
            .put("case_count", cases.size).put("has_regression_suite", cases.any { it.getString("purpose") == "regression" })
            .apply { CollaborationTransferStudy.plan(value, idea, exact)?.let { put(CollaborationTransferStudy.KIND, it) } }
    }

    fun result(value: JSONObject, revision: JSONObject, exact: (JSONObject, Set<String>) -> JSONObject,
               original: (JSONObject) -> JSONObject?, coverage: (JSONObject) -> Unit): JSONObject {
        val registered = exact(value.getJSONObject("plan"), setOf(PLAN))
        val spec = registered.getJSONObject("body").getJSONObject(PLAN)
        val idea = exact(spec.getJSONObject("innovation"), setOf(IDEA))
        val baseline = exact(spec.getJSONObject("baseline"), setOf("proposal", "artifact", IDEA))
        text(value, "interpretation"); text(value, "limitations")
        val refs = revision.getJSONArray("host_observations")
        require(refs.length() > 0) { "Experiment result requires original tool observations, not reported scores" }
        coverage(revision)
        val cases = objects(spec, "cases").associateBy { it.getString("id") }
        val samples = linkedMapOf<String, MutableMap<Pair<String, Int>, BigDecimal>>()
        val seenEvidence = hashSetOf<String>()
        val authors = sortedSetOf<String>()
        repeat(refs.length()) { index ->
            val ref = refs.getJSONObject(index)
            require(seenEvidence.add(ref.getString("evidence_id"))) { "Duplicate experiment observation" }
            val observed = requireNotNull(original(ref)) { "Original experiment observation unavailable" }
            require(observed.getString("evidence_id") == ref.getString("evidence_id") &&
                observed.getString("sha256") == ref.getString("sha256") && observed.getString("status") == "returned" &&
                observed.getString("observation_kind") == "tool_output_recorded") { "Experiment source is not a successful original tool observation" }
            val source = spec.getJSONObject("source")
            require(observed.getString("origin") == source.getString("origin") && observed.getString("tool") == source.getString("tool")) {
                "Experiment source differs from preregistered origin/tool"
            }
            require(observed.getLong("started_at") >= registered.getLong("recorded_at")) {
                "Experiment observation predates preregistration; do not choose a passing standard after observing results"
            }
            authors += observed.getString("person_id")
            val output = JSONObject(observed.getString("output_json"))
            val selected = pointer(output, spec.getString("report_pointer"))
            val report = when (selected) {
                is JSONObject -> selected
                is String -> JSONObject(selected)
                else -> throw IllegalArgumentException("report_pointer must select a JSON object or exact JSON text")
            }
            require(report.optString("format") == FORMAT && report.optString("plan_sha256") == registered.getString("sha256") &&
                report.optString("environment") == spec.getString("environment") && report.optString("budget_unit") == spec.getString("budget_unit")) {
                "Measurement report format/plan/environment/budget binding mismatch"
            }
            objects(report, "measurements").forEach { sample ->
                val case = requireNotNull(cases[text(sample, "case_id")]) { "Measurement uses an unregistered case" }
                val variant = text(sample, "variant")
                require(variant in setOf("baseline", "candidate")) { "Measurement variant must be baseline or candidate" }
                val expected = if (variant == "baseline") baseline else idea
                require(sample.optString("variant_sha256") == expected.getString("sha256") && sample.optString("metric") == case.getString("metric")) {
                    "Measurement variant/metric changed"
                }
                if (spec.has(CollaborationTransferStudy.KIND)) require(
                    sample.optString("dataset_sha256") == case.getJSONObject("dataset").getString("sha256") &&
                        sample.optString("domain") == case.getString("domain")) { "Measurement dataset/domain differs from the registered transfer case" }
                require(sample.opt("repetition") is Int && sample.getInt("repetition") in 1..case.getInt("repetitions")) {
                    "Measurement repetition is outside the preregistered case"
                }
                val used = decimal(sample, "budget_used")
                require(used >= BigDecimal.ZERO && used <= decimal(spec, "budget_limit")) { "Trial exceeded its registered resource budget" }
                val values = samples.getOrPut(case.getString("id")) { linkedMapOf() }
                val key = variant to sample.getInt("repetition")
                require(key !in values) { "Duplicate case/variant/repetition; do not cherry-pick or count the same trial twice" }
                values[key] = decimal(sample, "value")
            }
        }
        val evaluated = JSONArray()
        var incomplete = false
        var regression = false
        var targetsPass = true
        var transferPass = true
        cases.values.forEach { case ->
            val repetitions = case.getInt("repetitions")
            val values = samples[case.getString("id")].orEmpty()
            val row = JSONObject().put("case_id", case.getString("id")).put("purpose", case.getString("purpose"))
                .put("received_samples", values.size).put("expected_samples", repetitions.toLong() * 2)
            if (values.size.toLong() != repetitions.toLong() * 2) {
                incomplete = true
                row.put("state", "incomplete")
            } else {
                fun average(variant: String) = values.filterKeys { it.first == variant }.values.fold(BigDecimal.ZERO, BigDecimal::add)
                    .divide(BigDecimal(repetitions), MathContext.DECIMAL128)
                val control = average("baseline")
                val candidate = average("candidate")
                val gain = if (case.getString("direction") == "maximize") candidate - control else control - candidate
                val passes = if (case.getString("purpose") == "regression") gain >= -decimal(case, "tolerance")
                    else gain > BigDecimal.ZERO && gain >= decimal(case, "minimum_gain")
                if (case.getString("purpose") == "regression" && !passes) regression = true
                if (case.getString("purpose") == "target" && !passes) targetsPass = false
                if (case.getString("purpose") == "transfer" && !passes) transferPass = false
                row.put("baseline_mean", control.toPlainString()).put("candidate_mean", candidate.toPlainString())
                    .put("gain", gain.toPlainString()).put("state", if (passes) "passed" else "not_met")
            }
            evaluated.put(row)
        }
        val hasRegression = cases.values.any { it.getString("purpose") == "regression" }
        val state = when {
            incomplete -> "incomplete"
            regression -> "regressed"
            spec.has(CollaborationTransferStudy.KIND) && !transferPass -> "transfer_not_demonstrated"
            !targetsPass -> "inconclusive"
            !hasRegression -> "improved_without_regression_suite"
            else -> "measured_improvement"
        }
        return JSONObject().put("state", state).put("eligible_for_retention", state == "measured_improvement")
            .put("plan", CollaborationResearchCandidates.reference(registered)).put("cases", evaluated)
            .put("innovation", CollaborationResearchCandidates.reference(idea)).put("baseline", CollaborationResearchCandidates.reference(baseline))
            .put("trial_authors", JSONArray(authors.toList())).put("meaning", "arithmetic_on_observed_reports_not_independent_scientific_validation")
    }

    private fun decimal(json: JSONObject, key: String): BigDecimal {
        val raw = json.opt(key)
        require(raw is Number || raw is String) { "$key must be a finite decimal number" }
        return try { BigDecimal(raw.toString()).also {
            require(it.precision() <= 128 && kotlin.math.abs(it.scale().toLong()) <= 128) { "$key exceeds supported decimal precision" }
        } } catch (_: NumberFormatException) { throw IllegalArgumentException("$key must be a finite decimal number") }
    }

    // Android's org.json has no JSONPointer; traverse parsed JSON without interpreting report text as code.
    internal fun pointer(root: JSONObject, path: String): Any {
        if (path.isEmpty()) return root
        require(path.startsWith('/')) { "Invalid report JSON pointer" }
        return path.drop(1).split('/').fold(root as Any) { current, part ->
            require(!Regex("~(?![01])").containsMatchIn(part)) { "Invalid JSON pointer escape" }
            val key = part.replace("~1", "/").replace("~0", "~")
            when (current) {
                is JSONObject -> current.get(key)
                is JSONArray -> { require(key.matches(Regex("0|[1-9][0-9]*"))) { "Invalid array index" }; current.get(key.toInt()) }
                else -> throw IllegalArgumentException("Report pointer traverses a non-container")
            }
        }
    }
}

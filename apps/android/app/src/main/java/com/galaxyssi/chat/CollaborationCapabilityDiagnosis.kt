package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.objects
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.text

/** Agent-selected explanations, bound to original evidence and preregistered observable probes. */
internal object CollaborationCapabilityDiagnosis {
    const val DIAGNOSIS = "capability_diagnosis"
    const val PROBE = "capability_probe"
    val CATEGORIES = setOf("knowledge", "tool", "method", "verification", "coordination", "environment", "authorization", "unknown")

    fun diagnosis(value: JSONObject, revision: JSONObject,
                  exact: (JSONObject, Set<String>) -> JSONObject,
                  original: (JSONObject) -> JSONObject?, coverage: (JSONObject) -> Unit): JSONObject {
        val gap = exact(value.getJSONObject("gap"), setOf(CollaborationEvolutionContract.GAP))
        val gapValue = gap.getJSONObject("body").getJSONObject(CollaborationEvolutionContract.GAP)
        val option = text(value, "selected_option")
        require(objects(gapValue, "learning_options").any { it.getString("id") == option }) {
            "selected_option must reference an actual learning option in the exact gap revision"
        }
        listOf("uncertainty", "action", "authorization_boundary").forEach { text(value, it) }
        val hypotheses = objects(value, "hypotheses")
        val ids = hypotheses.map { text(it, "id") }
        require(ids.distinct().size == ids.size && text(value, "selected_hypothesis") in ids) {
            "selected_hypothesis must name one of the distinct hypotheses"
        }
        hypotheses.forEach {
            require(text(it, "category") in CATEGORIES) { "Hypothesis category must be one of ${CATEGORIES.sorted()}" }
            listOf("explanation", "discriminating_test", "would_refute").forEach { key -> text(it, key) }
        }
        val expected = objects(value, "expected_observations")
        require(expected.map { text(it, "id") }.distinct().size == expected.size) { "Expectation IDs must be unique" }
        expected.forEach {
            val source = it.getJSONObject("source")
            require(text(source, "origin") in CollaborationEvidenceOrigin.entries.map { origin -> origin.wireValue }) {
                "Probe source origin must be an observed executor origin"
            }
            require(!text(source, "tool").contains("recall", true) && source.getString("tool") != ResearchEvidenceAudit.TOOL) {
                "A recall or member assessment cannot be the discriminating probe"
            }
            require(it.opt("pointer") is String && it.getString("pointer").startsWith('/') &&
                !Regex("~(?![01])").containsMatchIn(it.getString("pointer"))) { "Expectation pointer must address an output field" }
            if (it.has("report_pointer")) require(it.opt("report_pointer") is String &&
                (it.getString("report_pointer").isEmpty() || it.getString("report_pointer").startsWith('/')) &&
                !Regex("~(?![01])").containsMatchIn(it.getString("report_pointer"))) { "report_pointer must be a JSON pointer" }
            require(it.has("expected") && scalar(it.get("expected"))) { "Expected observation must be an exact JSON scalar" }
            text(it, "meaning")
        }
        val originals = originals(revision, original, coverage)
        return JSONObject().put("state", "diagnosis_proposed").put("gap", CollaborationResearchCandidates.reference(gap))
            .put("selected_hypothesis", value.getString("selected_hypothesis")).put("selected_option", option)
            .put("observed_failures", originals.count { it.optString("status") == "failed" })
            .put("source_count", originals.size).put("cause_verified", false).put("gap_resolved", false)
    }

    fun probe(value: JSONObject, revision: JSONObject,
              exact: (JSONObject, Set<String>) -> JSONObject,
              original: (JSONObject) -> JSONObject?, coverage: (JSONObject) -> Unit): JSONObject {
        val diagnosis = exact(value.getJSONObject("diagnosis"), setOf(DIAGNOSIS))
        val spec = diagnosis.getJSONObject("body").getJSONObject(DIAGNOSIS)
        listOf("interpretation", "remaining_work").forEach { text(value, it) }
        require(text(value, "assessment") in setOf("supported", "refuted", "inconclusive", "blocked")) { "Invalid probe assessment" }
        val originals = originals(revision, original, coverage).associateBy { it.getString("evidence_id") }
        val expectations = objects(spec, "expected_observations").associateBy { it.getString("id") }
        val checks = objects(value, "checks")
        require(checks.map { text(it, "expectation_id") }.distinct().size == checks.size) { "Duplicate expectation result" }
        val prior = diagnosis.getJSONArray("host_observations")
        val priorIds = (0 until prior.length()).map { prior.getJSONObject(it).getString("evidence_id") }.toSet()
        val priorOriginals = (0 until prior.length()).map { index ->
            requireNotNull(original(prior.getJSONObject(index))) { "Original diagnosis symptom is unavailable" }
        }
        val priorOutputs = priorOriginals.map(::signature).toSet()
        val priorSignals = priorOriginals.mapNotNull(::failureSignature).toSet()
        val evaluated = JSONArray()
        checks.forEach { check ->
            val id = check.getString("expectation_id")
            val expected = requireNotNull(expectations[id]) { "Unregistered expectation: $id" }
            val ref = check.getJSONObject("observation")
            val saved = requireNotNull(originals[text(ref, "evidence_id")]) { "Probe must cite its original observation" }
            require(saved.getString("sha256") == text(ref, "sha256")) { "Probe evidence digest mismatch" }
            require(saved.getLong("started_at") >= diagnosis.getLong("recorded_at") &&
                saved.getString("evidence_id") !in priorIds) {
                "Probe must be a new observation after the immutable diagnosis, not its original symptom"
            }
            val source = expected.getJSONObject("source")
            require(listOf("origin", "tool").all { source.getString(it) == saved.getString(it) }) { "Probe source differs from preregistration" }
            val output = runCatching { JSONObject(saved.getString("output_json")) }.getOrNull()
            val actual = output?.let { runCatching {
                val selected = CollaborationEvolutionExperiment.pointer(it, expected.optString("report_pointer"))
                val report = when (selected) {
                    is JSONObject -> selected
                    is String -> JSONObject(selected)
                    else -> throw IllegalArgumentException("Probe report is not a JSON object")
                }
                CollaborationEvolutionExperiment.pointer(report, expected.getString("pointer"))
            }.getOrNull() }
            val met = actual != null && scalar(actual) && equalScalar(actual, expected.get("expected"))
            val sameOutput = signature(saved) in priorOutputs
            evaluated.put(JSONObject().put("expectation_id", id).put("met", met).put("field_present", actual != null)
                .put("actual", if (actual != null && scalar(actual)) actual else JSONObject.NULL)
                .put("observed_status", saved.getString("status")).put("same_output_as_symptom", sameOutput)
                .put("same_failure_signals_as_symptom", failureSignature(saved)?.let { it in priorSignals } ?: false)
                .put("observation", ref))
        }
        val allMet = checks.size == expectations.size && (0 until evaluated.length()).all { evaluated.getJSONObject(it).getBoolean("met") }
        return JSONObject().put("state", when {
            checks.size < expectations.size -> "probe_incomplete"
            allMet -> "probe_expectations_met"
            else -> "probe_expectations_not_met"
        }).put("diagnosis", CollaborationResearchCandidates.reference(diagnosis))
            .put("gap", diagnosis.getJSONObject(CollaborationEvolutionContract.HOST).getJSONObject("gap"))
            .put("checks", evaluated).put("cause_verified", false).put("gap_resolved", false)
            .put("meaning", "Observed scalar comparisons, not proof of causality, learning, goal completion or authorization")
    }

    private fun originals(revision: JSONObject, original: (JSONObject) -> JSONObject?, coverage: (JSONObject) -> Unit): List<JSONObject> {
        val refs = revision.getJSONArray("host_observations")
        require(refs.length() > 0) { "Diagnosis and probe records require original observations; keep unobserved gaps as proposals" }
        coverage(revision)
        return (0 until refs.length()).map { index ->
            val saved = requireNotNull(original(refs.getJSONObject(index))) { "Original diagnosis evidence is missing or isolated" }
            require(saved.getString("observation_kind") == "tool_output_recorded" &&
                !saved.getString("tool").contains("recall", true)) { "Recall and self-assessment are not original diagnosis evidence" }
            saved
        }
    }

    private fun scalar(value: Any) = value == JSONObject.NULL || value is String || value is Boolean ||
        value is Number && value.toDouble().isFinite()
    private fun signature(value: JSONObject) = Triple(value.getString("tool"), value.getString("origin"), value.getString("output_sha256"))
    private fun failureSignature(value: JSONObject): Triple<String, String, String>? = CollaborationCapabilityProblem.describe(
        value.getString("output_json"), value.getString("status"),
        CollaborationEvidenceOrigin.entries.first { it.wireValue == value.getString("origin") })?.let {
        Triple(value.getString("tool"), value.getString("origin"), it.getString("signal_sha256"))
    }
    private fun equalScalar(a: Any, b: Any) = if (a is Number && b is Number)
        java.math.BigDecimal(a.toString()).compareTo(java.math.BigDecimal(b.toString())) == 0 else a == b
}

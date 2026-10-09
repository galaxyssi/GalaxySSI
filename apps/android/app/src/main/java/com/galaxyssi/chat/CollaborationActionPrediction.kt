package com.galaxyssi.chat

import java.math.BigDecimal
import org.json.JSONArray
import org.json.JSONObject
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.HOST
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.objects
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.strings
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.text
import com.galaxyssi.chat.CollaborationEvolutionExperiment.decimal

/** Explicit, scoped environment hypotheses; neither model predictions nor utility grant authority. */
internal object CollaborationActionPrediction {
    const val MODEL = "task_environment_model"
    const val FORECAST = "action_forecast"
    const val OUTCOME = "prediction_outcome"
    const val CALIBRATION = "prediction_calibration"
    val KINDS = setOf(MODEL, FORECAST, OUTCOME, CALIBRATION)
    private val BASIS = setOf("artifact", "evidence", "proposal", "counterexample", "capability_probe", "experiment_result", OUTCOME, CALIBRATION)

    fun model(value: JSONObject, revision: JSONObject, exact: (JSONObject, Set<String>) -> JSONObject,
              coverage: (JSONObject) -> Unit): JSONObject {
        require(text(value, "goal_sha256").matches(Regex("[a-f0-9]{64}"))) { "Copy the original goal_sha256" }
        listOf("criterion_id", "requirement", "domain", "environment", "scope", "mechanism", "uncertainty", "valid_when", "refresh_when")
            .forEach { text(value, it) }
        strings(value, "confounders")
        val basis = objects(value, "basis").map { exact(it, BASIS) }
        val state = objects(value, "state")
        require(state.map { text(it, "id") }.distinct().size == state.size) { "Environment state IDs must be distinct" }
        state.forEach {
            text(it, "value"); text(it, "basis")
            require(text(it, "epistemic_status") in setOf("observed", "assumed", "unknown")) { "State must distinguish observation, assumption and unknown" }
            if (it.getString("epistemic_status") == "observed") {
                val ref = it.getJSONObject("observation")
                require(objects(revision, "host_observations").any { saved ->
                    saved.getString("evidence_id") == ref.optString("evidence_id") && saved.getString("sha256") == ref.optString("sha256")
                }) { "Observed state needs a cited original observation" }
            }
        }
        if (revision.getJSONArray("host_observations").length() > 0) coverage(revision)
        val actions = objects(value, "actions")
        require(actions.size >= 2 && actions.map { text(it, "id") }.distinct().size == actions.size) { "Compare distinct actions, including an explicit defer option" }
        require(actions.any { it.optString("mode") == "defer" }) { "Preserve a defer/no-action alternative" }
        actions.forEach {
            require(text(it, "mode") in setOf("act", "probe", "defer")) { "Unknown action mode" }
            listOf("description", "preconditions", "expected_transition", "side_effects", "reversibility", "authorization").forEach { key -> text(it, key) }
        }
        val host = JSONObject().put("state", "environment_hypothesis_not_verified").put("basis", JSONArray(basis.map(CollaborationResearchCandidates::reference)))
            .put("goal_sha256", value.getString("goal_sha256")).put("criterion_id", value.getString("criterion_id"))
            .put("model_accuracy_proven", false)
        if (value.has("previous_model")) {
            val prior = exact(value.getJSONObject("previous_model"), setOf(MODEL))
            val spec = prior.getJSONObject("body").getJSONObject(MODEL)
            require(listOf("goal_sha256", "criterion_id", "requirement", "domain").all { value.getString(it) == spec.getString(it) }) {
                "A model correction must preserve its goal and domain; use a separate model for another goal"
            }
            val feedback = objects(value, "feedback").map { exact(it, setOf(OUTCOME)) }
            require(feedback.map { it.getJSONObject(HOST).getJSONObject(FORECAST).getString("object_id") }.distinct().size == feedback.size) {
                "Do not duplicate outcomes for one forecast in a model correction"
            }
            feedback.forEach { require(CollaborationResearchCandidates.same(prior, it.getJSONObject(HOST).getJSONObject(MODEL))) {
                "Correction feedback belongs to another model revision"
            } }
            listOf("changed_assumptions", "why_change", "next_discriminating_test").forEach { text(value, it) }
            host.put("previous_model", CollaborationResearchCandidates.reference(prior))
                .put("feedback", JSONArray(feedback.map(CollaborationResearchCandidates::reference))).put("correction_verified", false)
        } else require(!value.has("feedback")) { "Model feedback requires the exact previous_model" }
        return host
    }

    fun forecast(value: JSONObject, exact: (JSONObject, Set<String>) -> JSONObject): JSONObject {
        val model = exact(value.getJSONObject(MODEL), setOf(MODEL))
        CollaborationInnovationValidation.checkRecord(model, exact)
        val spec = model.getJSONObject("body").getJSONObject(MODEL)
        val qualitative = CollaborationQualitativePrediction.enabled(value)
        listOf("work_id", "executor", "horizon", "decision_rationale", "risk_tradeoff", "information_value", "revalidate_before_action")
            .forEach { text(value, it) }
        if (qualitative) require(!value.has("utility_unit")) { "Qualitative forecasts compare explicit expectations, not numeric utility" }
        else text(value, "utility_unit")
        require((value.opt("valid_until") is Long || value.opt("valid_until") is Int) && value.getLong("valid_until") > model.getLong("recorded_at")) {
            "valid_until must be an absolute observation-validity deadline chosen for this task"
        }
        val events = objects(value, "events")
        require(events.map { text(it, "id") }.distinct().size == events.size) { "Prediction event IDs must be distinct" }
        events.forEach {
            text(it, "meaning"); text(it, "unit")
            if (qualitative) require(!it.has("utility_if_true") && !it.has("utility_if_false")) {
                "Qualitative events must not declare numeric utility"
            } else { decimal(it, "utility_if_true"); decimal(it, "utility_if_false") }
            require(it.opt("expected") is String || it.opt("expected") is Boolean || it.opt("expected") is Number || it.opt("expected") == JSONObject.NULL) {
                "Prediction expected must be an explicit scalar, including explicit null"
            }
            require(it.has("expected")) { "Prediction expected is missing" }
            require(text(it, "pointer").startsWith('/')) { "Prediction pointer must address an original report field" }
        }
        val source = value.getJSONObject("source")
        require(text(source, "origin") in CollaborationEvidenceOrigin.entries.map { it.wireValue } &&
            !text(source, "tool").contains("recall", true) && source.getString("tool") != ResearchEvidenceAudit.TOOL) { "Forecast needs an actual measurement tool, not recall/self-assessment" }
        require(value.opt("report_pointer") is String && (value.getString("report_pointer").isEmpty() || value.getString("report_pointer").startsWith('/'))) {
            "report_pointer must be a JSON pointer"
        }
        val actions = objects(spec, "actions").associateBy { it.getString("id") }
        val choices = objects(value, "choices")
        require(choices.map { text(it, "action_id") }.toSet() == actions.keys && choices.size == actions.size) { "Forecast every registered action exactly once" }
        val compared = JSONArray()
        choices.forEach { choice ->
            listOf("reasoning", "uncertainty", "resources", "risk").forEach { text(choice, it) }
            if (qualitative) {
                compared.put(CollaborationQualitativePrediction.comparison(choice, events.mapTo(hashSetOf()) { it.getString("id") }))
                return@forEach
            }
            require(!choice.has("expectations")) { "Probabilistic forecasts use probabilities; select qualitative mode for expectations" }
            val probabilities = choice.getJSONObject("probabilities")
            require(probabilities.keys().asSequence().toSet() == events.map { it.getString("id") }.toSet()) { "All choices need the same event set" }
            var utility = BigDecimal.ZERO
            events.forEach { event ->
                val p = decimal(probabilities, event.getString("id"))
                require(p >= BigDecimal.ZERO && p <= BigDecimal.ONE) { "Event probability must be between zero and one" }
                utility += p * decimal(event, "utility_if_true") + (BigDecimal.ONE - p) * decimal(event, "utility_if_false")
            }
            compared.put(JSONObject().put("action_id", choice.getString("action_id")).put("expected_utility", utility.toPlainString()))
        }
        val selected = text(value, "selected_action")
        require(selected in actions) { "Select an existing action" }
        return JSONObject().put("state", "preregistered_prediction_not_outcome").put(MODEL, CollaborationResearchCandidates.reference(model))
            .put("selected_action", selected).put("comparisons", compared).put("choice_is_agent_selected", true)
            .put("utility_is_declared_not_measured", !qualitative).put("grants_permissions", false)
            .apply { if (qualitative) put(CollaborationQualitativePrediction.MODE, CollaborationQualitativePrediction.QUALITATIVE) }
            .apply { CollaborationHypothesisTest.forecast(value, exact)?.let { put(CollaborationHypothesisTest.FIELD, it) } }
            .apply { CollaborationProbeContinuation.validate(value, exact)?.let { put(CollaborationProbeContinuation.METHODS, it) } }
    }
}

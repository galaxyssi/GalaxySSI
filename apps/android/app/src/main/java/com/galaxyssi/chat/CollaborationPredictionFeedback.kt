package com.galaxyssi.chat

import java.math.BigDecimal
import java.math.MathContext
import org.json.JSONArray
import org.json.JSONObject
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.HOST
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.objects
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.text
import com.galaxyssi.chat.CollaborationEvolutionExperiment.decimal

/** Scores only observed outcomes. Missing evidence and unchosen actions are never false labels. */
internal object CollaborationPredictionFeedback {
    const val FORMAT = "galaxyssi.action-outcome.v1"

    fun outcome(value: JSONObject, revision: JSONObject, exact: (JSONObject, Set<String>) -> JSONObject,
                original: (JSONObject) -> JSONObject?, coverage: (JSONObject) -> Unit): JSONObject {
        val forecast = exact(value.getJSONObject(CollaborationActionPrediction.FORECAST), setOf(CollaborationActionPrediction.FORECAST))
        val spec = forecast.getJSONObject("body").getJSONObject(CollaborationActionPrediction.FORECAST)
        val model = exact(spec.getJSONObject(CollaborationActionPrediction.MODEL), setOf(CollaborationActionPrediction.MODEL))
        listOf("interpretation", "confounders", "model_correction", "next_action").forEach { text(value, it) }
        val checks = value.getJSONArray("checks")
        val observations = revision.getJSONArray("host_observations")
        if (observations.length() > 0) coverage(revision)
        val originals = (0 until observations.length()).associate { i ->
            val ref = observations.getJSONObject(i)
            val saved = requireNotNull(original(ref)) { "Original prediction outcome unavailable or isolated" }
            require(saved.getString("sha256") == ref.getString("sha256") && saved.getString("observation_kind") == "tool_output_recorded") {
                "Prediction outcome needs original tool evidence"
            }
            saved.getString("evidence_id") to saved
        }
        val predictions = objects(spec, "events").associateBy { it.getString("id") }
        val choice = objects(spec, "choices").single { it.getString("action_id") == spec.getString("selected_action") }
        val seen = hashSetOf<String>()
        val evaluated = JSONArray()
        repeat(checks.length()) { i ->
            val check = checks.getJSONObject(i)
            val id = text(check, "event_id")
            require(seen.add(id)) { "Do not count a prediction event twice" }
            val prediction = requireNotNull(predictions[id]) { "Unregistered prediction event" }
            val ref = check.getJSONObject("observation")
            val saved = requireNotNull(originals[ref.getString("evidence_id")]) { "Prediction check must cite original evidence" }
            require(saved.getString("sha256") == ref.getString("sha256")) { "Prediction evidence digest mismatch" }
            require(saved.getString("run_id") == forecast.getString("run_id") && saved.getString("turn_id") == forecast.getString("turn_id") &&
                saved.getString("person_id") == spec.getString("executor")) { "Outcome belongs to another run/turn/executor" }
            require(saved.getLong("started_at") >= forecast.getLong("recorded_at")) { "Outcome predates forecast registration" }
            require(listOf("origin", "tool").all { saved.getString(it) == spec.getJSONObject("source").getString(it) }) { "Outcome tool differs from preregistration" }
            val selected = runCatching { CollaborationEvolutionExperiment.pointer(JSONObject(saved.getString("output_json")), spec.getString("report_pointer")) }.getOrNull()
            val report = when (selected) { is JSONObject -> selected; is String -> runCatching { JSONObject(selected) }.getOrNull(); else -> null }
            val row = JSONObject().put("event_id", id).put("observation", ref).put("observed_status", saved.getString("status"))
                .put("within_declared_validity", saved.getLong("started_at") <= spec.getLong("valid_until"))
            if (saved.getString("status") != "returned" || report == null) {
                row.put("state", "unobserved_tool_failure")
            } else {
                require(report.optString("format") == FORMAT && report.optString("forecast_sha256") == forecast.getString("sha256") &&
                    report.optString("action_id") == spec.getString("selected_action") && report.optString("work_id") == spec.getString("work_id") &&
                    report.optString("model_sha256") == model.getString("sha256") && report.optString("environment") == model.getJSONObject("body")
                        .getJSONObject(CollaborationActionPrediction.MODEL).getString("environment")) { "Outcome forecast/action/work/model/environment binding mismatch" }
                val actual = runCatching { CollaborationEvolutionExperiment.pointer(report, prediction.getString("pointer")) }.getOrNull()
                if (actual == null || actual is JSONObject || actual is JSONArray) row.put("state", "unobserved_field") else {
                    val expected = prediction.get("expected")
                    val met = if (actual is Number && expected is Number) BigDecimal(actual.toString()).compareTo(BigDecimal(expected.toString())) == 0 else actual == expected
                    val p = decimal(choice.getJSONObject("probabilities"), id)
                    val error = p - if (met) BigDecimal.ONE else BigDecimal.ZERO
                    row.put("state", "observed").put("event_occurred", met).put("predicted_probability", p.toPlainString())
                        .put("actual", actual).put("brier_score", (error * error).toPlainString())
                        .put("utility", decimal(prediction, if (met) "utility_if_true" else "utility_if_false").toPlainString())
                }
            }
            evaluated.put(row)
        }
        predictions.keys.filter { it !in seen }.forEach { evaluated.put(JSONObject().put("event_id", it).put("state", "unobserved_no_evidence")) }
        val scored = (0 until evaluated.length()).map(evaluated::getJSONObject).filter { it.getString("state") == "observed" }
        return JSONObject().put("state", if (scored.size == predictions.size) "observed_prediction_errors" else "partial_prediction_evidence")
            .put(CollaborationActionPrediction.FORECAST, CollaborationResearchCandidates.reference(forecast))
            .put(CollaborationActionPrediction.MODEL, CollaborationResearchCandidates.reference(model)).put("checks", evaluated)
            .put("scored_events", scored.size).put("registered_events", predictions.size)
            // Squaring a validated input can double its scale; these are host-computed values, not new raw inputs.
            .put("brier_sum", scored.fold(BigDecimal.ZERO) { sum, row -> sum + BigDecimal(row.getString("brier_score")) }.toPlainString())
            .put("unchosen_actions", JSONArray(objects(spec, "choices").map { it.getString("action_id") }.filter { it != spec.getString("selected_action") }))
            .put("counterfactuals_measured", false).put("causality_proven", false).put("model_improved", false)
            .put("execution_association", "original_run_executor_and_report_binding_not_independent_harness_certification")
            .apply { CollaborationHypothesisTest.outcome(forecast, evaluated)?.let { put(CollaborationHypothesisTest.FIELD, it) } }
    }

    fun calibration(value: JSONObject, exact: (JSONObject, Set<String>) -> JSONObject): JSONObject {
        val model = exact(value.getJSONObject(CollaborationActionPrediction.MODEL), setOf(CollaborationActionPrediction.MODEL))
        listOf("sampling_scope", "selection_bias", "limitations", "next_test").forEach { text(value, it) }
        val results = objects(value, "outcomes").map { exact(it, setOf(CollaborationActionPrediction.OUTCOME)) }
        val seen = hashSetOf<String>()
        var score = BigDecimal.ZERO; var count = 0L; var expected = 0L
        results.forEach {
            val host = it.getJSONObject(HOST)
            require(CollaborationResearchCandidates.same(model, host.getJSONObject(CollaborationActionPrediction.MODEL))) { "Do not pool different model revisions or environments as one calibration" }
            require(seen.add(host.getJSONObject(CollaborationActionPrediction.FORECAST).getString("object_id"))) { "Do not cherry-pick/count two outcome snapshots for one forecast" }
            score += BigDecimal(host.getString("brier_sum")); count += host.getInt("scored_events"); expected += host.getInt("registered_events")
        }
        return JSONObject().put("state", "scoped_forecast_score_not_calibration_proof").put(CollaborationActionPrediction.MODEL, CollaborationResearchCandidates.reference(model))
            .put("prediction_feedback", JSONArray(results.map(CollaborationResearchCandidates::reference)))
            .put("scored_events", count).put("registered_events", expected).put("forecast_count", results.size)
            .put("brier_mean", if (count == 0L) JSONObject.NULL else score.divide(BigDecimal(count), MathContext.DECIMAL128).toPlainString())
            .put("general_calibration_proven", false).put("selection_bias_excluded", false)
    }
}

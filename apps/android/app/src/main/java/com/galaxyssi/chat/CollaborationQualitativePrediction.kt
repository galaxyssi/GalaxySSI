package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.objects
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.text

/** Testable predictions without invented probabilities; consistency never certifies a hypothesis. */
internal object CollaborationQualitativePrediction {
    const val MODE = "prediction_mode"
    const val QUALITATIVE = "qualitative"
    private val labels = setOf("expected", "not_expected", "unknown")

    fun enabled(value: JSONObject): Boolean {
        require(!value.has(MODE) || value.opt(MODE) is String && value.getString(MODE) in setOf("probabilistic", QUALITATIVE)) {
            "prediction_mode must be probabilistic or qualitative"
        }
        return value.optString(MODE) == QUALITATIVE
    }

    fun expectations(value: JSONObject, eventIds: Set<String>, field: String): JSONObject {
        require(value.keys().asSequence().toSet() == eventIds) { "$field must cover the exact registered event IDs" }
        eventIds.forEach { id ->
            require(value.opt(id) is String && value.getString(id) in labels) {
                "$field.$id must be expected, not_expected or unknown; do not invent a probability"
            }
        }
        return value
    }

    fun comparison(choice: JSONObject, eventIds: Set<String>): JSONObject {
        require(!choice.has("probabilities")) { "Qualitative choices use expectations, not probabilities" }
        val declared = expectations(choice.getJSONObject("expectations"), eventIds, "choices.${choice.getString("action_id")}.expectations")
        return JSONObject().put("action_id", choice.getString("action_id")).put("expectations", JSONObject(declared.toString()))
            .put("expected_utility", JSONObject.NULL)
    }

    fun hypothesisTest(value: JSONObject): JSONObject {
        val spec = value.getJSONObject(CollaborationHypothesisTest.FIELD)
        listOf("question", "assumptions", "prediction_basis", "misspecification_check").forEach { text(spec, it) }
        require(listOf("likelihoods", "likelihood_basis", CollaborationHypothesisTest.PREVIOUS).none(spec::has)) {
            "Qualitative tests do not use likelihoods or posterior carryover; cite prior feedback in the environment model"
        }
        val hypotheses = objects(spec, "hypotheses")
        val ids = hypotheses.map { text(it, "id") }
        require(ids.size >= 2 && ids.distinct().size == ids.size) { "Compare at least two distinct hypothesis IDs" }
        hypotheses.forEach {
            text(it, "claim")
            require(!it.has("prior")) { "Qualitative hypotheses do not require or accept prior probabilities" }
        }
        val registered = objects(value, "events").mapTo(hashSetOf()) { it.getString("id") }
        val events = spec.getJSONArray("event_ids").let { a -> (0 until a.length()).map { a.getString(it) } }
        require(events.isNotEmpty() && events.distinct().size == events.size && registered.containsAll(events)) {
            "Qualitative event_ids must name distinct registered observable events"
        }
        val actions = objects(value, "choices").mapTo(hashSetOf()) { it.getString("action_id") }
        val matrix = spec.getJSONObject("predictions")
        require(matrix.keys().asSequence().toSet() == actions) { "Provide qualitative predictions for every action, including defer" }
        val comparisons = JSONArray()
        actions.forEach { action ->
            val rows = matrix.getJSONObject(action)
            require(rows.keys().asSequence().toSet() == ids.toSet()) { "predictions.$action must cover the exact hypothesis IDs" }
            ids.forEach { id -> expectations(rows.getJSONObject(id), events.toSet(), "predictions.$action.$id") }
            // Opposed explicit predictions, not entropy or an estimate of the value of an experiment.
            val distinguishing = events.filter { event ->
                val values = ids.map { rows.getJSONObject(it).getString(event) }.toSet()
                "expected" in values && "not_expected" in values
            }
            comparisons.put(JSONObject().put("action_id", action).put("distinguishing_event_ids", JSONArray(distinguishing))
                .put("expected_information_gain_bits", JSONObject.NULL))
        }
        return JSONObject().put("state", "declared_qualitative_comparison").put(MODE, QUALITATIVE)
            .put("action_information", comparisons).put("selected_action", value.getString("selected_action"))
            .put("hypotheses_exhaustive_verified", false).put("causality_proven", false)
            .put("meaning", "Explicit_prediction_disagreement_not_probability_information_gain_or_truth")
    }

    fun outcome(forecast: JSONObject, checks: JSONArray): JSONObject {
        val value = forecast.getJSONObject("body").getJSONObject(CollaborationActionPrediction.FORECAST)
        val spec = value.getJSONObject(CollaborationHypothesisTest.FIELD)
        val events = spec.getJSONArray("event_ids").let { a -> (0 until a.length()).map { a.getString(it) } }
        val checked = (0 until checks.length()).map(checks::getJSONObject).associateBy { it.getString("event_id") }
        val present = events.mapNotNull(checked::get).filter { it.getString("state") == "observed" && it.getBoolean("within_declared_validity") }
            .associateBy { it.getString("event_id") }
        val refs = present.values.map { it.getJSONObject("observation") }
        require(refs.isEmpty() || refs.all { it.getString("evidence_id") == refs.first().getString("evidence_id") &&
            it.getString("sha256") == refs.first().getString("sha256") }) {
            "One qualitative test must use one original observation; do not splice different experiments"
        }
        val predictions = spec.getJSONObject("predictions").getJSONObject(value.getString("selected_action"))
        val compared = JSONArray()
        objects(spec, "hypotheses").forEach { hypothesis ->
            val id = hypothesis.getString("id")
            val rows = predictions.getJSONObject(id)
            val supported = JSONArray(); val contradicted = JSONArray(); val unresolved = JSONArray()
            events.forEach { event ->
                val expectation = rows.getString(event)
                val observed = present[event]
                when {
                    expectation == "unknown" || observed == null -> unresolved.put(event)
                    observed.getBoolean("event_occurred") == (expectation == "expected") -> supported.put(event)
                    else -> contradicted.put(event)
                }
            }
            compared.put(JSONObject().put("hypothesis_id", id)
                .put("state", when {
                    contradicted.length() > 0 -> "contradicted"
                    unresolved.length() > 0 -> "unresolved"
                    else -> "consistent_with_observation"
                }).put("matched_event_ids", supported).put("contradicted_event_ids", contradicted).put("unresolved_event_ids", unresolved))
        }
        val allContradicted = (0 until compared.length()).all { compared.getJSONObject(it).getString("state") == "contradicted" }
        return JSONObject().put(MODE, QUALITATIVE).put("state", when {
            allContradicted -> "contradicted_hypothesis_space"
            present.size < events.size -> "incomplete_observation"
            else -> "compared_with_observation"
        }).put("hypotheses", compared).put("observed_events", present.size).put("registered_events", events.size)
            .put("posterior", JSONObject.NULL).put("information_gain_bits", JSONObject.NULL)
            .put("causality_proven", false).put("hypothesis_proven", false)
            .put("meaning", "Consistency_under_declared_predictions_not_empirical_probability_or_exhaustive_identification")
    }
}

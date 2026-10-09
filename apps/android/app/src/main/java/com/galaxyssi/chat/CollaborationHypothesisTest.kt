package com.galaxyssi.chat

import java.math.BigDecimal
import java.math.MathContext
import kotlin.math.ln
import org.json.JSONArray
import org.json.JSONObject
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.HOST
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.objects
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.text

/** Finite Bayesian experimental design over declared hypotheses, not a causal or truth oracle. */
internal object CollaborationHypothesisTest {
    const val FIELD = "hypothesis_test"
    const val PREVIOUS = "prior_outcome"
    private val mc = MathContext.DECIMAL128
    private val tolerance = BigDecimal("1e-12")

    fun forecast(value: JSONObject, exact: (JSONObject, Set<String>) -> JSONObject): JSONObject? {
        if (!value.has(FIELD)) return null
        if (CollaborationQualitativePrediction.enabled(value)) return CollaborationQualitativePrediction.hypothesisTest(value)
        val spec = value.getJSONObject(FIELD)
        listOf("question", "assumptions", "likelihood_basis", "misspecification_check").forEach { text(spec, it) }
        val hypotheses = objects(spec, "hypotheses")
        val ids = hypotheses.map { text(it, "id") }
        require(ids.size >= 2 && ids.distinct().size == ids.size) { "Compare at least two distinct hypothesis IDs" }
        hypotheses.forEach { text(it, "claim") }
        val previous = spec.optJSONObject(PREVIOUS)?.let { exact(it, setOf(CollaborationActionPrediction.OUTCOME)) }
        require(!spec.has(PREVIOUS) || previous != null) { "prior_outcome must be an exact outcome reference" }
        val prior = if (previous == null) normalized(JSONObject().apply {
            hypotheses.forEach { put(it.getString("id"), probability(it, "prior")) }
        }, ids.toSet()) else {
            CollaborationInnovationValidation.checkRecord(previous, exact)
            require(hypotheses.none { it.has("prior") }) { "A chained test derives priors from the exact outcome; do not overwrite them" }
            val feedback = previous.getJSONObject(HOST).getJSONObject(FIELD)
            require(feedback.getString("state") == "updated_from_observation") { "Prior outcome has no observed posterior; keep the last supported prior" }
            val oldForecast = exact(previous.getJSONObject(HOST).getJSONObject(CollaborationActionPrediction.FORECAST), setOf(CollaborationActionPrediction.FORECAST))
            val oldSpec = oldForecast.getJSONObject("body").getJSONObject(CollaborationActionPrediction.FORECAST)
            val oldModel = exact(oldSpec.getJSONObject(CollaborationActionPrediction.MODEL), setOf(CollaborationActionPrediction.MODEL))
                .getJSONObject("body").getJSONObject(CollaborationActionPrediction.MODEL)
            val newModel = exact(value.getJSONObject(CollaborationActionPrediction.MODEL), setOf(CollaborationActionPrediction.MODEL))
                .getJSONObject("body").getJSONObject(CollaborationActionPrediction.MODEL)
            require(listOf("goal_sha256", "criterion_id", "domain", "environment").all { oldModel.getString(it) == newModel.getString(it) }) {
                "Posterior carryover requires the same goal, criterion, domain and environment"
            }
            val oldClaims = objects(oldSpec.getJSONObject(FIELD), "hypotheses").associate { it.getString("id") to it.getString("claim") }
            require(oldClaims == hypotheses.associate { it.getString("id") to it.getString("claim") } &&
                oldSpec.getJSONObject(FIELD).getString("question") == spec.getString("question")) {
                "Changed hypotheses or question need a new comparison, not relabeled posterior weights"
            }
            text(spec, "conditional_history")
            ids.associateWith { BigDecimal(feedback.getJSONObject("posterior").getString(it)) }
        }
        val events = objects(value, "events").associateBy { it.getString("id") }
        val eventIds = spec.getJSONArray("event_ids").let { a -> (0 until a.length()).map { a.getString(it) } }
        require(eventIds.size >= 2 && eventIds.distinct().size == eventIds.size && eventIds.all { it in events }) {
            "Use at least two distinct registered categorical event IDs"
        }
        val labels = eventIds.map { events.getValue(it) }
        require(labels.map { it.getString("pointer") }.distinct().size == 1) { "Hypothesis outcomes must classify the same original report field" }
        val pointer = labels.first().getString("pointer")
        require(!Regex("~(?![01])").containsMatchIn(pointer)) { "Invalid hypothesis observation JSON pointer" }
        require(labels.indices.all { i -> (0 until i).none { j -> equal(labels[i].get("expected"), labels[j].get("expected")) } }) {
            "Hypothesis outcomes must have distinct scalar values"
        }
        val choices = objects(value, "choices").associateBy { it.getString("action_id") }
        val actions = choices.keys
        val matrix = spec.getJSONObject("likelihoods")
        require(matrix.keys().asSequence().toSet() == actions) { "Provide likelihoods for every action, including defer" }
        val initialEntropy = entropy(prior.values)
        val compared = JSONArray()
        actions.forEach { action ->
            val rows = matrix.getJSONObject(action)
            require(rows.keys().asSequence().toSet() == ids.toSet()) { "Every action needs the same hypothesis set" }
            val likelihoods = ids.associateWith { normalized(rows.getJSONObject(it), eventIds.toSet()) }
            var expectedEntropy = 0.0
            val predictive = JSONObject()
            eventIds.forEach { event ->
                val weights = ids.associateWith { prior.getValue(it).multiply(likelihoods.getValue(it).getValue(event), mc) }
                val mass = weights.values.fold(BigDecimal.ZERO, BigDecimal::add)
                val marginal = CollaborationEvolutionExperiment.decimal(choices.getValue(action).getJSONObject("probabilities"), event)
                require((marginal - mass).abs() <= tolerance) {
                    "choices.$action.probabilities.$event=$marginal conflicts with hypothesis predictive probability $mass"
                }
                predictive.put(event, mass.toString())
                if (mass.signum() > 0) expectedEntropy += mass.toDouble() * entropy(weights.values.map { it.divide(mass, mc) })
            }
            compared.put(JSONObject().put("action_id", action).put("expected_information_gain_bits", (initialEntropy - expectedEntropy).coerceAtLeast(0.0))
                .put("predictive_probabilities", predictive))
        }
        return JSONObject().put("state", "declared_hypothesis_comparison").put("priors", json(prior)).put("prior_entropy_bits", initialEntropy)
            .put("action_information", compared).put("selected_action", value.getString("selected_action"))
            .put("probabilities_are_assumptions", true).put("hypotheses_exhaustive_verified", false).put("causality_proven", false)
            .apply { previous?.let { put(PREVIOUS, CollaborationResearchCandidates.reference(it)) } }
    }

    fun outcome(forecast: JSONObject, checks: JSONArray): JSONObject? {
        val prepared = forecast.getJSONObject(HOST).optJSONObject(FIELD) ?: return null
        val value = forecast.getJSONObject("body").getJSONObject(CollaborationActionPrediction.FORECAST)
        if (CollaborationQualitativePrediction.enabled(value)) return CollaborationQualitativePrediction.outcome(forecast, checks)
        val spec = value.getJSONObject(FIELD)
        val priors = prepared.getJSONObject("priors").let { p -> p.keys().asSequence().associateWith { BigDecimal(p.getString(it)) } }
        val eventIds = spec.getJSONArray("event_ids").let { a -> (0 until a.length()).map { a.getString(it) } }
        val rows = (0 until checks.length()).map(checks::getJSONObject).filter { it.getString("event_id") in eventIds }
        val result = JSONObject().put("priors", json(priors)).put("posterior", JSONObject.NULL).put("information_gain_bits", JSONObject.NULL)
            .put("causality_proven", false).put("probabilities_are_assumptions", true)
        if (rows.size != eventIds.size || rows.any { it.getString("state") != "observed" }) return result.put("state", "incomplete_observation")
        if (rows.any { !it.getBoolean("within_declared_validity") }) return result.put("state", "stale_observation")
        val refs = rows.map { it.getJSONObject("observation") }
        require(refs.all { it.getString("evidence_id") == refs.first().getString("evidence_id") && it.getString("sha256") == refs.first().getString("sha256") }) {
            "A categorical hypothesis test must use one original observation, not splice outcomes from different trials"
        }
        val matched = rows.filter { it.getBoolean("event_occurred") }
        if (matched.size != 1) return result.put("state", "unmodeled_outcome").put("observed_value", rows.first().get("actual"))
        val event = matched.single().getString("event_id")
        val action = value.getString("selected_action")
        val matrix = spec.getJSONObject("likelihoods").getJSONObject(action)
        val weights = priors.mapValues { (id, prior) -> prior.multiply(normalized(matrix.getJSONObject(id), eventIds.toSet()).getValue(event), mc) }
        val mass = weights.values.fold(BigDecimal.ZERO, BigDecimal::add)
        result.put("event_id", event).put("observation", refs.first()).put("predictive_probability", mass.toString())
        if (mass.signum() == 0) return result.put("state", "contradicted_hypothesis_space")
        val posterior = weights.mapValues { it.value.divide(mass, mc) }
        var divergence = 0.0
        posterior.forEach { (id, p) -> if (p.signum() > 0) divergence += p.toDouble() * (log2(p) - log2(priors.getValue(id))) }
        return result.put("state", "updated_from_observation").put("posterior", json(posterior))
            .put("information_gain_bits", divergence.coerceAtLeast(0.0)).put("posterior_entropy_bits", entropy(posterior.values))
            .put("entropy_change_bits", entropy(posterior.values) - entropy(priors.values))
            .put("meaning", "Bayesian_update_under_declared_conditional_likelihoods_not_empirical_probability_calibration")
    }

    private fun probability(value: JSONObject, key: String): BigDecimal = CollaborationEvolutionExperiment.decimal(value, key).also {
        require(it >= BigDecimal.ZERO && it <= BigDecimal.ONE) { "$key must be a probability between zero and one" }
    }
    private fun normalized(value: JSONObject, ids: Set<String>): Map<String, BigDecimal> {
        require(value.keys().asSequence().toSet() == ids) { "Probability distribution must cover the exact registered IDs" }
        val p = ids.associateWith { probability(value, it) }
        val total = p.values.fold(BigDecimal.ZERO, BigDecimal::add)
        require((total - BigDecimal.ONE).abs() <= tolerance) { "Probability distribution must sum to one (tolerance 1e-12)" }
        return p.mapValues { it.value.divide(total, mc) }
    }
    private fun equal(a: Any, b: Any) = if (a is Number && b is Number) BigDecimal(a.toString()).compareTo(BigDecimal(b.toString())) == 0 else a == b
    private fun json(values: Map<String, BigDecimal>) = JSONObject().apply { values.forEach { (id, p) -> put(id, p.toString()) } }
    private fun entropy(p: Collection<BigDecimal>) = p.filter { it.signum() > 0 }.sumOf { -it.toDouble() * log2(it) }
    private fun log2(value: BigDecimal): Double {
        val exponent = value.precision() - value.scale() - 1
        return (ln(value.movePointLeft(exponent).toDouble()) + exponent * ln(10.0)) / ln(2.0)
    }
}

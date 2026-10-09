package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import com.galaxyssi.chat.CollaborationActionPrediction.FORECAST
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.HOST
import com.galaxyssi.chat.CollaborationHypothesisTest.FIELD
import com.galaxyssi.chat.CollaborationQualitativePrediction.MODE

class CollaborationQualitativePredictionTest {
    private class Fixture {
        val t = CollaborationActionPredictionTest.Fixture()
        val f = t.f
        fun expectation(fast: String = "unknown") = JSONObject().put("correct", "unknown").put("fast", fast)
        val spec = JSONObject(t.forecastSpec.toString()).put(MODE, "qualitative").apply {
            remove("utility_unit")
            for (event in CollaborationEvolutionContract.objects(this, "events")) {
                event.remove("utility_if_true"); event.remove("utility_if_false")
            }
            for (choice in CollaborationEvolutionContract.objects(this, "choices")) {
                choice.remove("probabilities")
                choice.put("expectations", expectation(if (choice.getString("action_id") == "indexed") "expected" else "unknown"))
            }
        }
        val hypotheses = JSONObject().put("question", "Which mechanism predicts this probe?")
            .put("assumptions", "Synthetic competing explanations, not an exhaustive set")
            .put("prediction_basis", "Explicit qualitative fixture predictions")
            .put("misspecification_check", "Keep unexpected observations and revise the model")
            .put("hypotheses", JSONArray().put(JSONObject().put("id", "cache").put("claim", "Cache permits one parse"))
                .put(JSONObject().put("id", "parser").put("claim", "Parser requires repeated parsing")))
            .put("event_ids", JSONArray().put("fast"))
            .put("predictions", JSONObject().apply {
                for (action in listOf("indexed", "reparse", "defer")) put(action, JSONObject()
                    .put("cache", JSONObject().put("fast", if (action == "indexed") "expected" else "unknown"))
                    .put("parser", JSONObject().put("fast", if (action == "indexed") "not_expected" else "unknown")))
            })
        val forecast by lazy { f.ref(publish(spec)) }
        fun publish(value: JSONObject, id: String = "qualitative") = f.publish(id, FORECAST, value, round = 8, now = 550)
        fun report(count: Any = 1) = t.report().put("forecast_sha256", forecast.getString("sha256")).put("parse_count", count)
        fun outcome(report: JSONObject = report(), change: (JSONObject) -> Unit = {}): JSONObject =
            t.outcome(t.observe(report)) { it.put(FORECAST, forecast); change(it) }
        fun host(report: JSONObject = report()) = f.ref(outcome(report)).getJSONObject(HOST)
        fun work() = t.work().put("prediction_work", JSONObject().put("forecast", forecast))
    }

    @Test fun forecastsDoNotRequireInventedProbabilitiesOrNumericUtility() {
        val x = Fixture(); val host = x.forecast.getJSONObject(HOST)
        assertEquals("qualitative", host.getString(MODE))
        assertFalse(host.getBoolean("utility_is_declared_not_measured"))
        val comparison = host.getJSONArray("comparisons").getJSONObject(0)
        assertTrue(comparison.isNull("expected_utility"))
        assertEquals("expected", comparison.getJSONObject("expectations").getString("fast"))
        val receipt = x.f.ref(x.outcome())
        val result = x.f.workspace.read(x.f.access(round = 10), receipt.getString("object_id"), receipt.getInt("revision"))!!
            .getJSONObject(HOST)
        assertEquals("observed_qualitative_evidence", result.getString("state"))
        assertTrue(result.isNull("brier_sum")); assertEquals(0, result.getInt("scored_events"))
        assertEquals(2, result.getInt("observed_events"))
        val checks = result.getJSONArray("checks")
        assertEquals("unspecified", checks.getJSONObject(0).getString("prediction_check"))
        assertEquals("consistent_with_observation", checks.getJSONObject(1).getString("prediction_check"))
        assertTrue(checks.getJSONObject(1).isNull("predicted_probability"))
    }

    @Test fun hypothesesHaveExplicitDistinguishingPredictionsAndNoFakeEntropy() {
        val x = Fixture(); x.spec.put(FIELD, x.hypotheses)
        val planned = x.forecast.getJSONObject(HOST).getJSONObject(FIELD).getJSONArray("action_information")
        val indexed = (0 until planned.length()).map(planned::getJSONObject).single { it.getString("action_id") == "indexed" }
        assertEquals("fast", indexed.getJSONArray("distinguishing_event_ids").getString(0))
        assertTrue(indexed.isNull("expected_information_gain_bits"))
        val outcome = x.host(x.report(4)).getJSONObject(FIELD)
        assertEquals("compared_with_observation", outcome.getString("state")); assertTrue(outcome.isNull("posterior"))
        val rows = outcome.getJSONArray("hypotheses")
        assertEquals("contradicted", rows.getJSONObject(0).getString("state"))
        assertEquals("consistent_with_observation", rows.getJSONObject(1).getString("state"))
        assertFalse(outcome.getBoolean("hypothesis_proven"))
    }

    @Test fun everyExplanationCanBeContradictedInsteadOfForcingAWinner() {
        val x = Fixture(); x.spec.put(FIELD, x.hypotheses)
        x.hypotheses.getJSONObject("predictions").getJSONObject("indexed").getJSONObject("parser").put("fast", "expected")
        val result = x.host(x.report(4)).getJSONObject(FIELD)
        assertEquals("contradicted_hypothesis_space", result.getString("state"))
        assertTrue(result.isNull("posterior"))
        assertEquals(2, result.getJSONArray("hypotheses").length())
    }

    @Test fun missingFailureStaleAndUnknownAreNotScientificDisproof() {
        for (kind in listOf("missing", "failure", "stale", "unknown")) {
            val x = Fixture(); x.spec.put(FIELD, x.hypotheses)
            if (kind == "stale") x.spec.put("valid_until", 575L)
            if (kind == "unknown") {
                val rows = x.hypotheses.getJSONObject("predictions").getJSONObject("indexed")
                listOf("cache", "parser").forEach { rows.getJSONObject(it).put("fast", "unknown") }
            }
            val report = x.report(4)
            if (kind == "missing") report.remove("parse_count")
            if (kind == "failure") report.put("status", "failed").put("error", "Unavailable")
            val result = x.host(report).getJSONObject(FIELD)
            val rows = result.getJSONArray("hypotheses")
            repeat(rows.length()) { assertEquals(kind, "unresolved", rows.getJSONObject(it).getString("state")) }
            assertTrue(result.isNull("information_gain_bits"))
        }
    }

    @Test fun unknownDoesNotHideARealContradictionInAnotherMeasuredField() {
        val x = Fixture(); x.spec.put(FIELD, x.hypotheses)
        x.hypotheses.getJSONArray("event_ids").put("correct")
        val matrix = x.hypotheses.getJSONObject("predictions")
        listOf("indexed", "reparse", "defer").forEach { a -> listOf("cache", "parser").forEach { h -> matrix.getJSONObject(a).getJSONObject(h).put("correct", "unknown") } }
        val rows = x.host(x.report(4)).getJSONObject(FIELD).getJSONArray("hypotheses")
        assertEquals("contradicted", rows.getJSONObject(0).getString("state"))
        assertEquals("unresolved", rows.getJSONObject(1).getString("state"))
    }

    @Test fun malformedOrMixedModesGiveRejectionInsteadOfSilentNumericConversion() {
        for (kind in listOf("mode", "mode-null", "label", "missing", "extra", "probability", "utility", "unit")) {
            val x = Fixture()
            when (kind) {
                "mode" -> x.spec.put(MODE, "guess")
                "mode-null" -> x.spec.put(MODE, JSONObject.NULL)
                "label" -> x.spec.getJSONArray("choices").getJSONObject(0).getJSONObject("expectations").put("fast", 0.5)
                "missing" -> x.spec.getJSONArray("choices").getJSONObject(0).getJSONObject("expectations").remove("fast")
                "extra" -> x.spec.getJSONArray("choices").getJSONObject(0).getJSONObject("expectations").put("other", "unknown")
                "probability" -> x.spec.getJSONArray("choices").getJSONObject(0).put("probabilities", JSONObject())
                "utility" -> x.spec.getJSONArray("events").getJSONObject(0).put("utility_if_true", 1)
                else -> x.spec.put("utility_unit", "score")
            }
            assertEquals(kind, "rejected", x.publish(x.spec).getString("status"))
        }
    }

    @Test fun malformedHypothesisContractsAreRejected() {
        for (kind in listOf("prior", "likelihood", "carryover", "event", "action", "hypothesis", "label", "empty")) {
            val x = Fixture(); x.spec.put(FIELD, x.hypotheses)
            when (kind) {
                "prior" -> x.hypotheses.getJSONArray("hypotheses").getJSONObject(0).put("prior", 0.5)
                "likelihood" -> x.hypotheses.put("likelihoods", JSONObject())
                "carryover" -> x.hypotheses.put("prior_outcome", JSONObject())
                "event" -> x.hypotheses.getJSONArray("event_ids").put("missing")
                "action" -> x.hypotheses.getJSONObject("predictions").remove("defer")
                "hypothesis" -> x.hypotheses.getJSONObject("predictions").getJSONObject("indexed").remove("parser")
                "label" -> x.hypotheses.getJSONObject("predictions").getJSONObject("indexed").getJSONObject("cache").put("fast", "certain")
                else -> x.hypotheses.put("event_ids", JSONArray())
            }
            assertEquals(kind, "rejected", x.publish(x.spec).getString("status"))
        }
    }

    @Test fun qualitativeOutcomesCannotMasqueradeAsPerfectProbabilityCalibration() {
        val x = Fixture(); val result = x.f.ref(x.outcome())
        assertEquals("rejected", x.t.calibrate(listOf(result)).getString("status"))
        val normal = x.f.ref(x.t.outcome(x.t.observe(), id = "probabilistic-outcome"))
        assertEquals("rejected", x.t.calibrate(listOf(normal, result)).getString("status"))
    }

    @Test fun qualitativeFeedbackStillRequiresExactSourceExecutorAndProspectiveBinding() {
        for (kind in listOf("executor", "run", "tool", "early", "forecast", "action", "work", "model", "environment")) {
            val x = Fixture(); val report = x.report()
            when (kind) {
                "forecast" -> report.put("forecast_sha256", "other")
                "action" -> report.put("action_id", "defer")
                "work" -> report.put("work_id", "other")
                "model" -> report.put("model_sha256", "other")
                "environment" -> report.put("environment", "other")
            }
            val ref = x.t.observe(report, person = if (kind == "executor") "lead" else "peer",
                started = if (kind == "early") 549 else 600, run = if (kind == "run") "other" else "run",
                tool = if (kind == "tool") "other" else "fixture.predict")
            assertEquals(kind, "rejected", x.t.outcome(ref, read = kind != "run") { it.put(FORECAST, x.forecast) }.getString("status"))
        }
    }

    @Test fun correctedModelKeepsGoalAndMeasuredFeedbackWithoutInventedPosterior() {
        val x = Fixture(); x.spec.put(FIELD, x.hypotheses)
        val outcome = x.f.ref(x.outcome(x.report(4)))
        val model = JSONObject(x.t.modelSpec.toString()).put("previous_model", x.t.model).put("feedback", JSONArray().put(outcome))
            .put("changed_assumptions", "Input revision must be represented").put("why_change", "One-parse prediction contradicted")
            .put("next_discriminating_test", "Compare changed and unchanged input revisions")
        val next = x.f.ref(x.f.publish("corrected-qualitative", CollaborationActionPrediction.MODEL, model, round = 10, now = 800))
        assertFalse(next.getJSONObject(HOST).getBoolean("correction_verified"))
        assertEquals(outcome.getString("sha256"), next.getJSONObject(HOST).getJSONArray("feedback").getJSONObject(0).getString("sha256"))
    }

    @Test fun nextRoundDispatchAndStoreReopenPreserveModeAndPredictions() {
        val x = Fixture(); x.spec.put(FIELD, x.hypotheses)
        val plan = CollaborationPredictionWork.plan(x.t.record(), listOf(x.work()), { x.f.workspace }, x.f.access(round = 10), now = 1000)
        val binding = JSONObject(CollaborationPredictionWork.context(plan.work.single()).getValue(CollaborationPredictionWork.TASK))
        assertEquals("qualitative", binding.getString(MODE)); assertEquals("declared_qualitative_comparison", binding.getJSONObject(FIELD).getString("state"))
        val record = x.t.record().let { it.copy(request = it.request.copy(context = it.request.context + (CollaborationPredictionWork.CLAIMS to plan.claims))) }
        assertEquals(plan.claims, CollaborationPredictionWork.plan(record, listOf(x.work()), { x.f.reopen() }, x.f.access(round = 10), now = 2000).claims)
        val finished = x.f.completed(x.t.record(), "lead", x.f.report(listOf(x.work())).toString(), true)
        val next = CollaborationGoalLoop.advance(finished, "lead", 1000, false, candidateWorkspace = { x.f.workspace })!!
        assertTrue(next.definition.members.any { it.context[CollaborationPredictionWork.TASK]?.contains("declared_qualitative_comparison") == true })
    }

    @Test fun conflictingIndependentExperimentsCannotBeSplicedIntoOneHypothesisTest() {
        val x = Fixture(); x.spec.put(FIELD, x.hypotheses)
        x.hypotheses.getJSONArray("event_ids").put("correct")
        val matrix = x.hypotheses.getJSONObject("predictions")
        listOf("indexed", "reparse", "defer").forEach { a -> listOf("cache", "parser").forEach { h -> matrix.getJSONObject(a).getJSONObject(h).put("correct", "expected") } }
        val a = x.t.observe(x.report()); val b = x.t.observe(x.report(4))
        val refs = JSONArray().put(a).put(b); x.f.read(x.f.access("reviewer", 9, "spliced"), refs)
        val value = JSONObject().put(FORECAST, x.forecast).put("interpretation", "Mixed trials").put("confounders", "Different observations")
            .put("model_correction", "None").put("next_action", "New experiment").put("checks", JSONArray()
                .put(JSONObject().put("event_id", "correct").put("observation", a)).put(JSONObject().put("event_id", "fast").put("observation", b)))
        assertEquals("rejected", x.f.publish("spliced", CollaborationActionPrediction.OUTCOME, value, "reviewer", 9, 700, refs).getString("status"))
    }
}

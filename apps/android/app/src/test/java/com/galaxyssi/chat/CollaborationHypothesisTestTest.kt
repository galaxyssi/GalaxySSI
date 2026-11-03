package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import com.galaxyssi.chat.CollaborationActionPrediction.FORECAST
import com.galaxyssi.chat.CollaborationActionPrediction.OUTCOME
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.HOST
import com.galaxyssi.chat.CollaborationHypothesisTest.FIELD
import com.galaxyssi.chat.CollaborationHypothesisTest.PREVIOUS

class CollaborationHypothesisTestTest {
    private class Fixture {
        val t = CollaborationActionPredictionTest.Fixture()
        val f = t.f
        fun distribution(hit: Any, miss: Any) = JSONObject().put("hit", hit).put("miss", miss)
        val test = JSONObject().put("question", "Does a stale index or parser cause wrong results?")
            .put("assumptions", "Two candidate mechanisms for this local fixture only")
            .put("likelihood_basis", "Exact predictions of the two deterministic fixture mechanisms")
            .put("misspecification_check", "Unknown outcome requires a new explanation")
            .put("hypotheses", JSONArray().put(JSONObject().put("id", "cache").put("claim", "Stale index").put("prior", 0.5))
                .put(JSONObject().put("id", "parser").put("claim", "Parser defect").put("prior", 0.5)))
            .put("event_ids", JSONArray().put("hit").put("miss"))
            .put("likelihoods", JSONObject().put("indexed", JSONObject().put("cache", distribution(1, 0)).put("parser", distribution(0, 1)))
                .put("reparse", JSONObject().put("cache", distribution(0.5, 0.5)).put("parser", distribution(0.5, 0.5)))
                .put("defer", JSONObject().put("cache", distribution(0.5, 0.5)).put("parser", distribution(0.5, 0.5))))
        val spec = JSONObject(t.forecastSpec.toString()).put(FIELD, test).apply {
            getJSONArray("events").put(t.event("hit", "/category", "hit")).put(t.event("miss", "/category", "miss"))
            for (i in 0 until getJSONArray("choices").length()) getJSONArray("choices").getJSONObject(i)
                .getJSONObject("probabilities").put("hit", 0.5).put("miss", 0.5)
        }
        val forecast by lazy { f.ref(publish(spec)) }
        fun publish(value: JSONObject, id: String = "discriminate", round: Long = 8, now: Long = 550) =
            f.publish(id, FORECAST, value, round = round, now = now)
        fun original(category: Any = "hit", ref: JSONObject = forecast, started: Long = 600) =
            t.observe(t.report().put("forecast_sha256", ref.getString("sha256")).put("category", category), started = started)
        fun outcome(evidence: JSONObject = original(), ref: JSONObject = forecast, id: String = "discrimination-result", change: (JSONObject) -> Unit = {}) =
            t.outcome(evidence, id = id) { value ->
                value.put(FORECAST, ref)
                value.getJSONArray("checks").put(JSONObject().put("event_id", "hit").put("observation", evidence))
                    .put(JSONObject().put("event_id", "miss").put("observation", evidence))
                change(value)
            }
        fun host(ref: JSONObject = forecast) = ref.getJSONObject(HOST).getJSONObject(FIELD)
        fun work(ref: JSONObject = forecast) = t.work().put("prediction_work", JSONObject().put("forecast", ref))
        fun chained(result: JSONObject) = JSONObject(spec.toString()).apply {
            val test = getJSONObject(FIELD)
            test.put(PREVIOUS, result).put("conditional_history", "Fresh intervention conditional on the preceding observation")
            repeat(test.getJSONArray("hypotheses").length()) { test.getJSONArray("hypotheses").getJSONObject(it).remove("prior") }
            val posterior = result.getJSONObject(HOST).getJSONObject(FIELD).getJSONObject("posterior")
            getJSONArray("choices").getJSONObject(0).getJSONObject("probabilities")
                .put("hit", posterior.getString("cache")).put("miss", posterior.getString("parser"))
        }
    }

    @Test fun discriminatingExperimentHasInformationWhileEquivalentPredictionsDoNot() {
        val x = Fixture(); val host = x.host()
        val rows = host.getJSONArray("action_information")
        assertEquals(1.0, rows.getJSONObject(0).getDouble("expected_information_gain_bits"), 1e-12)
        assertEquals(0.0, rows.getJSONObject(1).getDouble("expected_information_gain_bits"), 1e-12)
        assertEquals(0.0, rows.getJSONObject(2).getDouble("expected_information_gain_bits"), 1e-12)
        assertTrue(host.getBoolean("probabilities_are_assumptions")); assertFalse(host.getBoolean("causality_proven"))
        val alternative = x.f.ref(x.publish(JSONObject(x.spec.toString()).put("selected_action", "defer"), "defer-test"))
        assertEquals("defer", x.host(alternative).getString("selected_action"))
    }

    @Test fun actualLocalInterventionUpdatesBeliefsAndSurvivesReopening() {
        val x = Fixture()
        val cached = JSONObject("{\"value\":7}").getInt("value")
        val fresh = JSONObject("{\"value\":9}").getInt("value")
        val category = if (cached != fresh) "hit" else "miss"
        val result = x.f.ref(x.outcome(x.original(category)))
        val host = x.host(result)
        assertEquals("updated_from_observation", host.getString("state"))
        assertEquals(1.0, host.getJSONObject("posterior").getDouble("cache"), 0.0)
        assertEquals(0.0, host.getJSONObject("posterior").getDouble("parser"), 0.0)
        assertEquals(1.0, host.getDouble("information_gain_bits"), 1e-12)
        val saved = x.f.reopen().read(x.f.access(round = 11).copy(runId = "future", turnId = "future"), result.getString("object_id"), 1)!!
        assertEquals(host.toString(), saved.getJSONObject(HOST).getJSONObject(FIELD).toString())
    }

    @Test fun uninformativeObservationDoesNotManufactureLearning() {
        val x = Fixture(); x.test.getJSONObject("likelihoods").put("indexed", JSONObject()
            .put("cache", x.distribution(0.5, 0.5)).put("parser", x.distribution(0.5, 0.5)))
        val host = x.host(x.f.ref(x.outcome()))
        assertEquals(0.5, host.getJSONObject("posterior").getDouble("cache"), 0.0)
        assertEquals(0.0, host.getDouble("information_gain_bits"), 1e-12)
    }

    @Test fun surprisingEvidenceCanIncreaseEntropyWithoutBeingDiscarded() {
        val x = Fixture()
        x.test.getJSONArray("hypotheses").getJSONObject(0).put("prior", 0.9)
        x.test.getJSONArray("hypotheses").getJSONObject(1).put("prior", 0.1)
        x.test.getJSONObject("likelihoods").put("indexed", JSONObject().put("cache", x.distribution(0.1, 0.9)).put("parser", x.distribution(0.9, 0.1)))
        x.spec.getJSONArray("choices").getJSONObject(0).getJSONObject("probabilities").put("hit", 0.18).put("miss", 0.82)
        val host = x.host(x.f.ref(x.outcome()))
        assertEquals(0.5, host.getJSONObject("posterior").getDouble("cache"), 1e-12)
        assertTrue(host.getDouble("entropy_change_bits") > 0.5)
        assertTrue(host.getDouble("information_gain_bits") > 0.0)
    }

    @Test fun missingFailedAndStaleEvidenceDoNotBecomeNegativeLabels() {
        for (mode in listOf("missing", "failed", "stale", "partial")) {
            val x = Fixture()
            if (mode == "stale") x.spec.put("valid_until", 590)
            val report = x.t.report().put("forecast_sha256", x.forecast.getString("sha256"))
            if (mode != "missing") report.put("category", "hit")
            if (mode == "failed") report.put("status", "failed").put("error", "Offline")
            val saved = x.f.ref(x.outcome(x.t.observe(report)) { if (mode == "partial") it.getJSONArray("checks").remove(3) })
            val host = x.host(saved)
            assertEquals(mode, if (mode == "stale") "stale_observation" else "incomplete_observation", host.getString("state"))
            assertTrue(host.isNull("posterior")); assertTrue(host.isNull("information_gain_bits"))
        }
    }

    @Test fun unknownCategoryAndImpossibleObservationExposeModelMisspecification() {
        val x = Fixture(); val unknown = x.host(x.f.ref(x.outcome(x.original("other"))))
        assertEquals("unmodeled_outcome", unknown.getString("state")); assertTrue(unknown.isNull("posterior"))
        val y = Fixture(); y.test.getJSONObject("likelihoods").put("indexed", JSONObject()
            .put("cache", y.distribution(0, 1)).put("parser", y.distribution(0, 1)))
        y.spec.getJSONArray("choices").getJSONObject(0).getJSONObject("probabilities").put("hit", 0).put("miss", 1)
        val impossible = y.host(y.f.ref(y.outcome()))
        assertEquals("contradicted_hypothesis_space", impossible.getString("state")); assertTrue(impossible.isNull("posterior"))
    }

    @Test fun cannotSpliceTwoDifferentExperimentsIntoOneCategoricalObservation() {
        val x = Fixture(); val a = x.original(); val b = x.original("miss")
        val refs = JSONArray().put(a).put(b); x.f.read(x.f.access("reviewer", 9, "spliced"), refs)
        val spec = JSONObject().put(FORECAST, x.forecast).put("interpretation", "Two trials").put("confounders", "Different inputs")
            .put("model_correction", "None").put("next_action", "More work").put("checks", JSONArray()
                .put(JSONObject().put("event_id", "hit").put("observation", a)).put(JSONObject().put("event_id", "miss").put("observation", b)))
        assertEquals("rejected", x.f.publish("spliced", OUTCOME, spec, "reviewer", 9, 700, refs).getString("status"))
    }

    @Test fun rejectsMalformedProbabilitiesNonexclusiveEventsAndInconsistentMarginals() {
        for (mode in listOf("sum", "negative", "nan", "action", "hypothesis", "duplicate", "pointer", "labels", "marginal")) {
            val x = Fixture()
            when (mode) {
                "sum" -> x.test.getJSONArray("hypotheses").getJSONObject(0).put("prior", 0.4)
                "negative" -> x.test.getJSONObject("likelihoods").getJSONObject("indexed").getJSONObject("cache").put("hit", -1)
                "nan" -> x.test.getJSONArray("hypotheses").getJSONObject(0).put("prior", "NaN")
                "action" -> x.test.getJSONObject("likelihoods").remove("defer")
                "hypothesis" -> x.test.getJSONObject("likelihoods").getJSONObject("indexed").remove("cache")
                "duplicate" -> x.test.getJSONArray("hypotheses").getJSONObject(1).put("id", "cache")
                "pointer" -> x.spec.getJSONArray("events").getJSONObject(3).put("pointer", "/other")
                "labels" -> x.spec.getJSONArray("events").getJSONObject(3).put("expected", "hit")
                else -> x.spec.getJSONArray("choices").getJSONObject(0).getJSONObject("probabilities").put("hit", 0.7)
            }
            assertEquals(mode, "rejected", x.publish(x.spec).getString("status"))
        }
    }

    @Test fun chainedExperimentCarriesExactPosteriorAndRejectsRelabeling() {
        val x = Fixture(); val result = x.f.ref(x.outcome()); val next = x.chained(result)
        val saved = x.f.ref(x.publish(next, "next-test", 10, 800))
        assertEquals(1.0, x.host(saved).getJSONObject("priors").getDouble("cache"), 0.0)
        assertEquals(0.0, x.host(saved).getJSONArray("action_information").getJSONObject(0).getDouble("expected_information_gain_bits"), 0.0)
        for (field in listOf("prior", "claim", "question")) {
            val changed = JSONObject(next.toString()); val test = changed.getJSONObject(FIELD)
            when (field) {
                "prior" -> test.getJSONArray("hypotheses").getJSONObject(0).put("prior", 0.5)
                "claim" -> test.getJSONArray("hypotheses").getJSONObject(0).put("claim", "New cause")
                else -> test.put("question", "Different question")
            }
            assertEquals("rejected", x.publish(changed, "changed-$field", 10, 800).getString("status"))
        }
        assertEquals("rejected", x.outcome(x.original(), ref = saved, id = "reused-evidence").getString("status"))
    }

    @Test fun incompleteOutcomeCannotSeedAPosteriorAndOrdinaryForecastIsUnchanged() {
        val x = Fixture(); val result = x.f.ref(x.outcome(x.original("unmodeled")))
        val next = JSONObject(x.spec.toString()); next.getJSONObject(FIELD).put(PREVIOUS, result)
        repeat(2) { next.getJSONObject(FIELD).getJSONArray("hypotheses").getJSONObject(it).remove("prior") }
        assertEquals("rejected", x.publish(next, "bad-prior", 10, 800).getString("status"))
        assertFalse(x.t.forecast.getJSONObject(HOST).has(FIELD))
        assertFalse(x.f.ref(x.t.outcome(x.t.observe(), id = "ordinary")).getJSONObject(HOST).has(FIELD))
    }

    @Test fun workGraphCarriesExperimentComparisonAndRecoveryPinsIt() {
        val x = Fixture(); val first = CollaborationPredictionWork.plan(x.t.record(), listOf(x.work()), { x.f.workspace }, x.f.access(round = 10), now = 900)
        val binding = JSONObject(CollaborationPredictionWork.context(first.work.single()).getValue(CollaborationPredictionWork.TASK))
        assertEquals(x.host().toString(), binding.getJSONObject(FIELD).toString())
        val restored = x.t.record().let { it.copy(request = it.request.copy(context = it.request.context + (CollaborationPredictionWork.CLAIMS to first.claims))) }
        assertEquals(first.claims, CollaborationPredictionWork.plan(restored, listOf(x.work()), { x.f.reopen() }, x.f.access(round = 10), now = 1000).claims)
        val next = CollaborationGoalLoop.advance(x.f.completed(x.t.record(), "lead", x.f.report(listOf(x.work())).toString(), true),
            "lead", 1000, false, candidateWorkspace = { x.f.workspace })!!
        assertTrue(next.definition.members.any { it.context[CollaborationPredictionWork.TASK]?.contains(FIELD) == true })
    }

    @Test fun beliefsCannotLeakToAnotherGroupOrChangeDomains() {
        val x = Fixture(); val result = x.f.ref(x.outcome()); val next = x.chained(result)
        val changedModel = JSONObject(x.t.modelSpec.toString()).put("domain", "another domain")
        val model = x.f.ref(x.f.publish("other-model", CollaborationActionPrediction.MODEL, changedModel, round = 10, now = 750))
        next.put(CollaborationActionPrediction.MODEL, model)
        assertEquals("rejected", x.publish(next, "cross-domain", 11, 800).getString("status"))
        assertNull(x.f.reopen().read(x.f.access(round = 20).copy(groupId = "other"), result.getString("object_id"), 1))
    }

    @Test fun rareObservationsKeepFiniteBayesianUpdatesWithoutRoundingPriorsToZero() {
        val x = Fixture()
        x.test.getJSONArray("hypotheses").getJSONObject(0).put("prior", "1e-128")
        x.test.getJSONArray("hypotheses").getJSONObject(1).put("prior", 1)
        x.spec.getJSONArray("choices").getJSONObject(0).getJSONObject("probabilities").put("hit", "1e-128").put("miss", 1)
        val host = x.host(x.f.ref(x.outcome()))
        assertEquals(1.0, host.getJSONObject("posterior").getDouble("cache"), 0.0)
        assertEquals(128.0 * kotlin.math.log2(10.0), host.getDouble("information_gain_bits"), 1e-10)
        assertTrue(host.getDouble("information_gain_bits").isFinite())
    }

    @Test fun explicitNullIsARealCategoryAndNumericAliasesAreNotDistinctCategories() {
        val x = Fixture(); x.spec.getJSONArray("events").getJSONObject(2).put("expected", JSONObject.NULL)
        assertEquals("updated_from_observation", x.host(x.f.ref(x.outcome(x.original(JSONObject.NULL)))).getString("state"))
        val y = Fixture()
        y.spec.getJSONArray("events").getJSONObject(2).put("expected", 0)
        y.spec.getJSONArray("events").getJSONObject(3).put("expected", 0.0)
        assertEquals("rejected", y.publish(y.spec).getString("status"))
    }

    @Test fun multipleHypothesesAndCategoriesUseTheFullDistribution() {
        val x = Fixture()
        val hypotheses = listOf("cache", "parser", "transport"); val outcomes = listOf("hit", "miss", "other")
        val priors = listOf(0.2, 0.3, 0.5)
        x.test.put("hypotheses", JSONArray(hypotheses.mapIndexed { i, h -> JSONObject().put("id", h).put("claim", h).put("prior", priors[i]) }))
            .put("event_ids", JSONArray(outcomes))
        x.spec.getJSONArray("events").put(x.t.event("other", "/category", "other"))
        for ((i, action) in listOf("indexed", "reparse", "defer").withIndex()) {
            val matrix = JSONObject()
            hypotheses.forEachIndexed { h, id -> matrix.put(id, JSONObject().apply {
                outcomes.forEachIndexed { o, event -> put(event, if (i == 0) if (h == o) 1.0 else 0.0 else priors[o]) }
            }) }
            x.test.getJSONObject("likelihoods").put(action, matrix)
            outcomes.forEachIndexed { o, event -> x.spec.getJSONArray("choices").getJSONObject(i).getJSONObject("probabilities").put(event, priors[o]) }
        }
        val expected = priors.sumOf { -it * kotlin.math.log2(it) }
        assertEquals(expected, x.host().getJSONArray("action_information").getJSONObject(0).getDouble("expected_information_gain_bits"), 1e-12)
        assertEquals(0.0, x.host().getJSONArray("action_information").getJSONObject(1).getDouble("expected_information_gain_bits"), 1e-12)
        val evidence = x.original("other")
        val result = x.f.ref(x.outcome(evidence) { it.getJSONArray("checks").put(JSONObject().put("event_id", "other").put("observation", evidence)) })
        assertEquals(1.0, x.host(result).getJSONObject("posterior").getDouble("transport"), 0.0)
    }

    @Test fun hostComputedTinyScoresSurviveOutcomeAndCalibrationWithoutInputPrecisionRejection() {
        val x = Fixture()
        x.test.getJSONArray("hypotheses").getJSONObject(0).put("prior", "1e-128")
        x.test.getJSONArray("hypotheses").getJSONObject(1).put("prior", 1)
        x.spec.getJSONArray("choices").getJSONObject(0).getJSONObject("probabilities")
            .put("hit", "1e-128").put("miss", 1).put("correct", 1).put("fast", 1)
        val result = x.f.ref(x.outcome(x.original("miss")))
        assertEquals(0, java.math.BigDecimal("1e-256").compareTo(java.math.BigDecimal(result.getJSONObject(HOST).getString("brier_sum"))))
        val calibration = x.f.ref(x.t.calibrate(listOf(result))).getJSONObject(HOST)
        assertEquals(0, java.math.BigDecimal("2.5e-257").compareTo(java.math.BigDecimal(calibration.getString("brier_mean"))))
    }
}

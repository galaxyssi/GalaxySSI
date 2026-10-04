package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import com.galaxyssi.chat.CollaborationActionPrediction.MODEL
import com.galaxyssi.chat.CollaborationActionPrediction.FORECAST
import com.galaxyssi.chat.CollaborationActionPrediction.OUTCOME
import com.galaxyssi.chat.CollaborationActionPrediction.CALIBRATION
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.HOST

class CollaborationActionPredictionTest {
    internal class Fixture {
        val f = CollaborationInnovationTest.Fixture()
        val modelSpec = JSONObject().put("goal_sha256", CollaborationSemanticGoalCoverage.source(f.goal).getString("goal_sha256"))
            .put("criterion_id", "quality").put("requirement", f.goal).put("domain", "local parsing").put("environment", "immutable fixture v1")
            .put("scope", "Same document, no network").put("mechanism", "Index avoids repeated parsing").put("uncertainty", "Cache correctness")
            .put("valid_when", "Input unchanged").put("refresh_when", "Dataset changed").put("confounders", JSONArray().put("Warm cache"))
            .put("basis", JSONArray().put(f.baseline)).put("state", JSONArray().put(JSONObject().put("id", "input").put("value", "4 identical documents")
                .put("basis", "Fixture assumption").put("epistemic_status", "assumed")))
            .put("actions", JSONArray().put(action("indexed", "act")).put(action("reparse", "act")).put(action("defer", "defer")))
        val model = f.ref(f.publish("model", MODEL, modelSpec, round = 6, now = 400))
        fun action(id: String, mode: String) = JSONObject().put("id", id).put("mode", mode).put("description", id)
            .put("preconditions", "Immutable input").put("expected_transition", "Count changes").put("side_effects", "None")
            .put("reversibility", "Discard local result").put("authorization", "Local fixture only")
        fun event(id: String, pointer: String, expected: Any) = JSONObject().put("id", id).put("meaning", id).put("unit", "boolean")
            .put("pointer", pointer).put("expected", expected).put("utility_if_true", 1).put("utility_if_false", -1)
        fun choice(id: String, p: Double) = JSONObject().put("action_id", id).put("reasoning", "Local estimate").put("uncertainty", "No real-model trials")
            .put("resources", "CPU operations").put("risk", "Stale cache").put("probabilities", JSONObject().put("correct", p).put("fast", p))
        val forecastSpec = JSONObject().put(MODEL, model).put("work_id", "predict-work").put("executor", "peer").put("horizon", "One local batch")
            .put("valid_until", Long.MAX_VALUE).put("decision_rationale", "Compare correctness and parse calls").put("risk_tradeoff", "No external side effects")
            .put("information_value", "Tests cache benefit").put("revalidate_before_action", "Hash input").put("utility_unit", "fixture score")
            .put("selected_action", "indexed").put("source", JSONObject().put("origin", "android_native_tool").put("tool", "fixture.predict"))
            .put("report_pointer", "").put("events", JSONArray().put(event("correct", "/correct", true)).put(event("fast", "/parse_count", 1)))
            .put("choices", JSONArray().put(choice("indexed", 0.8)).put(choice("reparse", 0.5)).put(choice("defer", 0.1)))
        val forecast = f.ref(f.publish("forecast", FORECAST, forecastSpec, round = 7, now = 500))
        fun record() = f.record()
        fun work() = f.work().apply { remove("innovation_work"); put("id", "predict-work"); put("prediction_work", JSONObject().put("forecast", forecast)) }
        fun report() = JSONObject().put("format", CollaborationPredictionFeedback.FORMAT).put("forecast_sha256", forecast.getString("sha256"))
            .put("model_sha256", model.getString("sha256")).put("action_id", "indexed").put("work_id", "predict-work")
            .put("environment", "immutable fixture v1").put("correct", true).put("parse_count", 1)
        fun observe(report: JSONObject = report(), person: String = "peer", started: Long = 600, run: String = "run", tool: String = "fixture.predict") =
            f.ledger.record(f.access(person, 8).copy(runId = run), "trial-${System.nanoTime()}", tool, "{}", report.toString(), started, started + 1,
                CollaborationEvidenceOrigin.ANDROID_NATIVE_TOOL)
        fun outcome(ref: JSONObject, id: String = "outcome", read: Boolean = true, change: (JSONObject) -> Unit = {}): JSONObject {
            val refs = JSONArray().put(ref)
            if (read) f.read(f.access("reviewer", 9, id), refs)
            val spec = JSONObject().put(FORECAST, forecast).put("interpretation", "Fixture observation").put("confounders", "Synthetic environment")
                .put("model_correction", "Reconsider incorrect forecasts").put("next_action", "Test future independent inputs")
                .put("checks", JSONArray().put(JSONObject().put("event_id", "correct").put("observation", ref))
                    .put(JSONObject().put("event_id", "fast").put("observation", ref))).apply(change)
            return f.publish(id, OUTCOME, spec, "reviewer", 9, 700, refs)
        }
        fun calibrate(refs: List<JSONObject>) = f.publish("calibration", CALIBRATION, JSONObject().put(MODEL, model).put("outcomes", JSONArray(refs))
            .put("sampling_scope", "Selected synthetic runs").put("selection_bias", "Not a random population")
            .put("limitations", "No general accuracy proof").put("next_test", "Held-out future tasks"), round = 10, now = 800)
    }

    @Test fun comparesAllActionsButDoesNotChooseOrAuthorizeThem() {
        val t = Fixture(); val host = t.forecast.getJSONObject(HOST)
        assertEquals("1.2", host.getJSONArray("comparisons").getJSONObject(0).getString("expected_utility"))
        assertEquals("indexed", host.getString("selected_action")); assertFalse(host.getBoolean("grants_permissions"))
        val changed = JSONObject(t.forecastSpec.toString()).put("selected_action", "defer")
        assertEquals("recorded", t.f.publish("defer-choice", FORECAST, changed, round = 8, now = 550).getString("status"))
    }

    @Test fun modelCannotCallAssumptionsObservedOrOmitAlternatives() {
        val t = Fixture()
        for (kind in listOf("observation", "defer", "duplicate")) {
            val spec = JSONObject(t.modelSpec.toString())
            when (kind) {
                "observation" -> spec.getJSONArray("state").getJSONObject(0).put("epistemic_status", "observed")
                "defer" -> spec.getJSONArray("actions").remove(2)
                else -> spec.getJSONArray("actions").getJSONObject(1).put("id", "indexed")
            }
            assertEquals("rejected", t.f.publish("bad-$kind", MODEL, spec, round = 8, now = 550).getString("status"))
        }
    }

    @Test fun predictionRequiresAllComparableEventsAndValidProbabilities() {
        val t = Fixture()
        for (kind in listOf("probability", "missing", "action", "expired", "fractional", "null", "source")) {
            val spec = JSONObject(t.forecastSpec.toString())
            when (kind) {
                "probability" -> spec.getJSONArray("choices").getJSONObject(0).getJSONObject("probabilities").put("fast", 1.1)
                "missing" -> spec.getJSONArray("choices").getJSONObject(0).getJSONObject("probabilities").remove("fast")
                "action" -> spec.getJSONArray("choices").remove(0)
                "expired" -> spec.put("valid_until", 501)
                "fractional" -> spec.put("valid_until", 999.5)
                "null" -> spec.getJSONArray("events").getJSONObject(0).remove("expected")
                else -> spec.getJSONObject("source").put("tool", "collaboration_recall")
            }
            assertEquals("rejected", t.f.publish("invalid-$kind", FORECAST, spec, round = 8, now = 550).getString("status"))
        }
    }

    @Test fun actualLocalAlgorithmProducesScoredOriginalEvidenceAndReopens() {
        val t = Fixture(); val source = "{\"value\":7}"
        var parses = 0
        val parsed = JSONObject(source).also { parses++ }
        val answers = List(4) { parsed.getInt("value") }
        val report = t.report().put("correct", answers.all { it == 7 }).put("parse_count", parses)
        val outcome = t.f.ref(t.outcome(t.observe(report))); val host = outcome.getJSONObject(HOST)
        assertEquals("observed_prediction_errors", host.getString("state"))
        assertEquals("0.08", host.getString("brier_sum")); assertFalse(host.getBoolean("counterfactuals_measured"))
        assertEquals(2, host.getJSONArray("unchosen_actions").length())
        val aggregate = t.f.ref(t.calibrate(listOf(outcome)))
        assertEquals("0.04", aggregate.getJSONObject(HOST).getString("brier_mean"))
        assertFalse(aggregate.getJSONObject(HOST).getBoolean("general_calibration_proven"))
        assertNotNull(t.f.reopen().read(t.f.access(round = 11).copy(runId = "future", turnId = "future"), outcome.getString("object_id"), 1))
    }

    @Test fun wrongPredictionsStayAsNegativeEvidence() {
        val t = Fixture(); val outcome = t.f.ref(t.outcome(t.observe(t.report().put("correct", false).put("parse_count", 4))))
        assertEquals("1.28", outcome.getJSONObject(HOST).getString("brier_sum"))
        assertFalse(outcome.getJSONObject(HOST).getBoolean("model_improved"))
    }

    @Test fun missingAndFailedObservationsAreNotFalseOutcomes() {
        for (kind in listOf("missing", "failed", "empty")) {
            val t = Fixture(); val report = t.report()
            if (kind == "missing") report.remove("correct")
            if (kind == "failed") report.put("status", "failed").put("error", "Offline")
            val result = t.f.ref(t.outcome(t.observe(report)) { if (kind == "empty") it.put("checks", JSONArray()) })
            assertEquals("partial_prediction_evidence", result.getJSONObject(HOST).getString("state"))
            assertEquals(if (kind == "missing") 1 else 0, result.getJSONObject(HOST).getInt("scored_events"))
        }
    }

    @Test fun evidenceCannotChangeTheForecastIdentity() {
        for (field in listOf("forecast_sha256", "model_sha256", "action_id", "work_id", "environment", "format")) {
            val t = Fixture()
            assertEquals(field, "rejected", t.outcome(t.observe(t.report().put(field, "wrong"))).getString("status"))
        }
    }

    @Test fun wrongExecutorSourceRunOrEarlyOutcomeIsRejected() {
        for (kind in listOf("person", "tool", "run", "early")) {
            val t = Fixture()
            val ref = t.observe(person = if (kind == "person") "outsider" else "peer", tool = if (kind == "tool") "other" else "fixture.predict",
                run = if (kind == "run") "other-run" else "run", started = if (kind == "early") 499 else 600)
            assertEquals("rejected", t.outcome(ref, read = kind != "run").getString("status"))
        }
    }

    @Test fun fullReadAndUniqueEventChecksAreRequired() {
        val t = Fixture(); val ref = t.observe()
        assertEquals("rejected", t.outcome(ref, read = false).getString("status"))
        assertEquals("rejected", t.outcome(ref, id = "duplicate") { it.getJSONArray("checks").getJSONObject(1).put("event_id", "correct") }.getString("status"))
    }

    @Test fun duplicateSnapshotsDoNotInflateCalibration() {
        val t = Fixture(); val ref = t.observe(); val a = t.f.ref(t.outcome(ref)); val b = t.f.ref(t.outcome(ref, "other-snapshot"))
        assertEquals("rejected", t.calibrate(listOf(a, a)).getString("status"))
        assertEquals("rejected", t.calibrate(listOf(a, b)).getString("status"))
    }

    @Test fun whollyUnobservedCalibrationHasNoFabricatedPerfectScore() {
        val t = Fixture(); val ref = t.observe(t.report().put("status", "failed").put("error", "Disconnected"))
        val result = t.f.ref(t.outcome(ref))
        val score = t.f.ref(t.calibrate(listOf(result))).getJSONObject(HOST)
        assertEquals(0, score.getInt("scored_events")); assertEquals(2, score.getInt("registered_events"))
        assertTrue(score.isNull("brier_mean"))
    }

    @Test fun correctionPreservesPreviousModelAndFailuresButDoesNotClaimImprovement() {
        val t = Fixture(); val outcome = t.f.ref(t.outcome(t.observe(t.report().put("correct", false))))
        val spec = JSONObject(t.modelSpec.toString()).put("previous_model", t.model).put("feedback", JSONArray().put(outcome))
            .put("changed_assumptions", "Index key must include revision").put("why_change", "Wrong cache result").put("next_discriminating_test", "Changed revision fixture")
        val updated = t.f.ref(t.f.publish("corrected", MODEL, spec, round = 10, now = 800))
        assertFalse(updated.getJSONObject(HOST).getBoolean("correction_verified"))
        assertEquals(t.model.getString("sha256"), updated.getJSONObject(HOST).getJSONObject("previous_model").getString("sha256"))
        val newForecast = JSONObject(t.forecastSpec.toString()).put(MODEL, updated).put("work_id", "next-work")
        assertEquals("recorded", t.f.publish("future-forecast", FORECAST, newForecast, round = 11, now = 900).getString("status"))
        spec.put("requirement", "Move the goalposts")
        assertEquals("rejected", t.f.publish("drift", MODEL, spec, round = 11, now = 900).getString("status"))
    }

    @Test fun forecastsAreImmutableAndPrivateAcrossGroups() {
        val t = Fixture(); val update = JSONObject(t.f.raw("revision", FORECAST, t.forecastSpec))
        update.getJSONArray("workspace").getJSONObject(0).put("object_id", t.forecast.getString("object_id")).put("base_revision", 1)
        assertEquals("rejected", t.f.workspace.publish(t.f.access("forecast", 8, "revision"), update.toString(), 550).getString("status"))
        reject { CollaborationPredictionWork.plan(t.record(), listOf(t.work()), { t.f.workspace }, t.f.access().copy(groupId = "other")) }
    }

    @Test fun admissionPinsWorkAndAllowsRecoveryWithoutRewriting() {
        val t = Fixture(); val record = t.record(); val plan = CollaborationPredictionWork.plan(record, listOf(t.work()), { t.f.workspace }, t.f.access(), now = 1000)
        val binding = JSONObject(CollaborationPredictionWork.context(plan.work.single()).getValue(CollaborationPredictionWork.TASK))
        assertFalse(binding.getBoolean("grants_permissions")); assertEquals("indexed", binding.getString("selected_action"))
        val restored = record.copy(request = record.request.copy(context = record.request.context + (CollaborationPredictionWork.CLAIMS to plan.claims)))
        assertEquals(plan.claims, CollaborationPredictionWork.plan(restored, listOf(t.work()), { t.f.reopen() }, t.f.access(), now = 2000).claims)
        reject { CollaborationPredictionWork.plan(restored, listOf(t.work().put("assignment", "Different action")), { t.f.workspace }, t.f.access()) }
        reject { CollaborationPredictionWork.plan(restored, listOf(t.work().apply { remove("prediction_work") }), { t.f.workspace }, t.f.access()) }
    }

    @Test fun admissionRejectsWrongGoalMemberWorkAndExpiredPrediction() {
        val t = Fixture()
        reject { CollaborationPredictionWork.plan(t.record().copy(request = t.record().request.copy(goal = "Other")), listOf(t.work()), { t.f.workspace }, t.f.access()) }
        reject { CollaborationPredictionWork.plan(t.record(), listOf(t.work().put("member", "lead")), { t.f.workspace }, t.f.access()) }
        reject { CollaborationPredictionWork.plan(t.record(), listOf(t.work().put("id", "other")), { t.f.workspace }, t.f.access()) }
        reject { CollaborationPredictionWork.plan(t.record(), listOf(t.work()), { t.f.workspace }, t.f.access(), JSONArray()) }
        val old = t.f.ref(t.f.publish("short", FORECAST, JSONObject(t.forecastSpec.toString()).put("valid_until", 600), round = 8, now = 550))
        reject { CollaborationPredictionWork.plan(t.record(), listOf(t.work().put("prediction_work", JSONObject().put("forecast", old))), { t.f.workspace }, t.f.access(), now = 601) }
    }

    @Test fun ordinaryWorkHasNoWorkspaceIoAndBadBatchDoesNotMutateClaims() {
        val t = Fixture(); val plain = JSONObject().put("id", "plain")
        assertSame(plain, CollaborationPredictionWork.plan(t.record(), listOf(plain), { error("No I/O") }, t.f.access()).work.single())
        val work = t.work(); val raw = work.toString()
        reject { CollaborationPredictionWork.plan(t.record(), listOf(work, t.work().put("host_prediction_work", JSONObject())), { t.f.workspace }, t.f.access()) }
        assertEquals(raw, work.toString()); assertFalse(t.record().request.context.containsKey(CollaborationPredictionWork.CLAIMS))
    }

    @Test fun nextRoundDispatchesActualBoundWorkAndCapturesCompletionOnce() {
        val t = Fixture(); val f = t.f
        val finished = f.completed(t.record(), "lead", f.report(listOf(t.work())).toString(), true)
        val next = CollaborationGoalLoop.advance(finished, "lead", 1000, true, candidateWorkspace = { f.workspace })!!
        val worker = next.definition.members.single { CollaborationPredictionWork.TASK in it.context }
        val completed = f.completed(next, worker.memberId, "Observed result")
        val outcomes = CollaborationPredictionWork.capture(completed, completed.events.mapNotNull { it.result })
        assertEquals("succeeded", JSONObject(outcomes).getJSONObject(worker.memberId).getString("status"))
        assertFalse(JSONObject(outcomes).getJSONObject(worker.memberId).getBoolean("prediction_verified"))
        assertEquals(outcomes, CollaborationPredictionWork.capture(completed.copy(request = completed.request.copy(context = completed.request.context +
            (CollaborationPredictionWork.OUTCOMES to outcomes))), completed.events.mapNotNull { it.result }))
    }

    @Test fun livePlannerDispatchesWithoutWaitingForUnrelatedMemberAndCapturesOutcome() {
        val t = Fixture(); val f = t.f; val base = t.record()
        val people = base.definition.members.map { it.copy(deliveryMode = AgentDeliveryMode.IGNORE) }
        val slow = people.last().copy(instanceId = "slow", deliveryMode = AgentDeliveryMode.OBSERVE,
            context = people.last().context + mapOf(CollaborationGoalLoop.ROSTER to "false", CollaborationGoalLoop.WORK_ID to "slow-work", CollaborationResearchWorkflow.STAGE to "EXECUTE"))
        val planner = people.first().copy(instanceId = "planner", deliveryMode = AgentDeliveryMode.OBSERVE,
            context = people.first().context + mapOf(CollaborationGoalLoop.ROSTER to "false", CollaborationLiveGraph.PLANNER to "1"))
        val final = people.first().copy(instanceId = "final", deliveryMode = AgentDeliveryMode.RESPOND,
            context = people.first().context + (CollaborationGoalLoop.ROSTER to "false"), dependsOnAgentIds = setOf("slow", "planner"))
        val live = base.copy(definition = base.definition.copy(members = people + slow + planner + final, primaryInstanceId = "final"))
        val returned = f.completed(live, "planner", JSONObject().put("format", CollaborationLiveGraph.FORMAT).put("summary", "Predict and act")
            .put("work", JSONArray().put(t.work())).toString())
        val next = CollaborationLiveGraph.update(returned, setOf("planner"), 1000, { f.workspace })
        val worker = next.definition.members.single { CollaborationPredictionWork.TASK in it.context }
        assertFalse("slow" in worker.dependsOnAgentIds)
        assertEquals(next.definition, CollaborationLiveGraph.update(next, setOf("planner"), 2000, { f.workspace }).definition)
        val complete = CollaborationLiveGraph.update(f.completed(next, worker.memberId, "Measurement recorded"), setOf(worker.memberId), 3000, { f.workspace })
        assertEquals("succeeded", JSONObject(complete.request.context.getValue(CollaborationPredictionWork.OUTCOMES).toString()).getJSONObject(worker.memberId).getString("status"))
    }

    @Test fun staleInputsBlockNewWorkButHistoricalMeasurementsRemainReadable() {
        val t = Fixture()
        val update = JSONObject(t.f.raw("changed-input", "artifact", JSONObject()))
        update.getJSONArray("workspace").getJSONObject(0).put("object_id", t.f.baseline.getString("object_id")).put("base_revision", 1)
        assertEquals("recorded", t.f.workspace.publish(t.f.access("baseline", 8, "changed-input"), update.toString(), 550).getString("status"))
        reject { CollaborationPredictionWork.plan(t.record(), listOf(t.work()), { t.f.workspace }, t.f.access()) }
        val result = t.f.ref(t.outcome(t.observe()))
        assertEquals("observed_prediction_errors", result.getJSONObject(HOST).getString("state"))
        val index = t.f.reopen().browseEvolution(t.f.access(round = 12)).revisions
        assertEquals("historical_requires_revalidation", index.single { it.getString("object_id") == t.forecast.getString("object_id") }.getString("evolution_applicability"))
    }

    @Test fun explicitNullDiffersFromMissingAndDesktopJsonTextUsesSameRules() {
        val t = Fixture()
        val spec = JSONObject(t.forecastSpec.toString()).put("report_pointer", "/stdout")
        spec.getJSONArray("events").getJSONObject(0).put("expected", JSONObject.NULL)
        val forecast = t.f.ref(t.f.publish("wrapped", FORECAST, spec, round = 8, now = 550))
        val report = t.report().put("forecast_sha256", forecast.getString("sha256")).put("correct", JSONObject.NULL)
        val ref = t.observe(JSONObject().put("stdout", report.toString()))
        val result = t.f.ref(t.outcome(ref) { it.put(FORECAST, forecast) })
        val saved = t.f.workspace.read(t.f.access(round = 10), result.getString("object_id"), result.getInt("revision"))!!
        assertTrue(saved.getJSONObject(HOST).getJSONArray("checks").getJSONObject(0).getBoolean("event_occurred"))
        report.remove("correct")
        val other = t.observe(JSONObject().put("stdout", report.toString()))
        assertEquals(1, t.f.ref(t.outcome(other, "missing-null") { it.put(FORECAST, forecast) }).getJSONObject(HOST).getInt("scored_events"))
    }

    private fun reject(block: () -> Unit) { try { block(); fail("Expected rejection") } catch (_: IllegalArgumentException) { } }
}

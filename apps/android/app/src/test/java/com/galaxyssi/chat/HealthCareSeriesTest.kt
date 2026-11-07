package com.galaxyssi.chat

import java.util.UUID
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class HealthCareSeriesTest {
    private val now = 1_793_000_000_000L
    private fun sample(at: Long = now, value: String = "6.3", unit: String = "mmol/L", condition: String = "fasting") =
        HealthCareSample(HealthCareRecordRef(UUID.randomUUID().toString(), 1), HealthMetric.GLUCOSE, at,
            mapOf("glucose" to value), unit, "4-6", condition, "", "manual", "private-origin", "private-device")
    private fun confirmed(sample: HealthCareSample) = HealthCareContext(sample.record, HealthCareTruth.YES, HealthCareTruth.NO,
        HealthCareTruth.NO, HealthCareSpecimen.LAB_PLASMA, 8, HealthCareTruth.NO, now)
    private fun assessment(sample: HealthCareSample, series: HealthCareSeries? = null) = HealthCareAssessment(sample.record,
        sample.measuredAt, sample.values.getValue("glucose"), sample.unit, sample.reference, setOf(HealthCareSignal.REPORT_HIGH), sample = sample, series = series)
    private fun request(goal: String): AgentRequest {
        val screen = ScreenContext("com.galaxyssi.chat", pageTitle = "Synthetic health review")
        return AgentRequest(goal, screen, emptyList(), memories = emptyList(), runtimeContext = AgentRuntimeContextBuilder.build(
            sessionId = "health-prompt-test", goal = goal, screen = screen, permissionMode = PermissionMode.AUTO_LOW_RISK,
            highRiskGuard = true, memoryCapture = false, callableTargets = emptyList(), memories = emptyList()))
    }
    @Test fun roundTripPreservesAllResultsAndBoundedCoverage() {
        val a = sample(); val b = sample(now - 1000, "<5.4")
        val series = HealthCareSeries(listOf(a, b), true)
        assertEquals(series, HealthCareSeries.from(JSONObject(series.json().toString())))
        assertEquals(assessment(a, series), HealthCareAssessment.from(JSONObject(assessment(a, series).json().toString())))
        assertNull(HealthCareAssessment.from(assessment(a).json()).series)
    }
    @Test fun incompleteUnitsConditionsAndSourcesAreNotSilentlyFiltered() {
        val a = sample(); val b = sample(now - 1000, "<100", "mg/dL", "after_meal").copy(origin = "different", reference = "70-100")
        val series = HealthCareSeries(listOf(a, b), false)
        val data = series.modelJson(a, confirmed(a), null)
        val gaps = data.getJSONArray("samples").getJSONObject(1).getJSONArray("gaps_against_current").toString()
        listOf("UNITS_DIFFER", "CONDITIONS_DIFFER", "SOURCE_DIFFERS", "REFERENCE_DIFFERS", "NON_EXACT_RESULT",
            "CONTEXT_UNCONFIRMED", "METHOD_UNVERIFIED").forEach { assertTrue(it, gaps.contains(it)) }
        assertTrue(data.getJSONArray("samples").getJSONObject(1).isNull("confirmed_context"))
        assertFalse(data.toString().contains("private-origin")); assertFalse(data.toString().contains("private-device"))
    }
    @Test fun matchingNumbersNeverCertifyStabilityOrSynthesizeOldContext() {
        val a = sample(); val b = sample(now - 10_000)
        val data = HealthCareSeries(listOf(a, b), false).modelJson(a, confirmed(a), null)
        assertFalse(data.getBoolean("stability_verified"))
        assertTrue(data.getJSONArray("samples").getJSONObject(1).isNull("confirmed_context"))
        val withPrior = HealthCareSeries(listOf(a, b), false).modelJson(a, confirmed(a),
            HealthCareComparison(b, HealthCareComparisonKind.NEW_RESULT, confirmed(b)))
        assertTrue(withPrior.toString().contains("METHOD_UNVERIFIED"))
        assertFalse(withPrior.toString().contains("CONTEXT_UNCONFIRMED"))
    }
    @Test fun seriesRejectsDuplicatesDisorderOverflowAndWrongCurrentSource() {
        val a = sample(); val b = sample(now - 1000)
        assertTrue(runCatching { HealthCareSeries(emptyList(), false) }.isFailure)
        assertTrue(runCatching { HealthCareSeries(listOf(a, a.copy(record = a.record.copy(revision = 2))), false) }.isFailure)
        assertTrue(runCatching { HealthCareSeries(listOf(b, a), false) }.isFailure)
        assertTrue(runCatching { HealthCareSeries((0..30).map { sample(now - it) }, true) }.isFailure)
        assertTrue(runCatching { assessment(a, HealthCareSeries(listOf(b), false)) }.isFailure)
    }
    @Test fun authorizedSnapshotIncludesRedactedHistoryAndRevision() {
        val a = sample(); val b = sample(now - 1000)
        val issue = HealthCareConcern(UUID.randomUUID().toString(), HealthMetric.GLUCOSE, 1, now, now, "clock",
            assessment(a, HealthCareSeries(listOf(a, b), true)))
        val snapshot = JSONObject(HealthCareDiscussionPolicy.snapshot(issue))
        assertEquals("clock", snapshot.getString("input_version"))
        assertTrue(snapshot.getJSONObject("measurement_history").getBoolean("has_earlier"))
        assertFalse(snapshot.getJSONObject("assessment").has("series"))
        assertFalse(snapshot.toString().contains("private-origin")); assertFalse(snapshot.toString().contains("device_group"))
    }
    @Test fun maintenanceIsInvalidatedEvenWhenOlderChangedRecordIsOutsideRecentWindow() {
        val a = sample()
        val issue = HealthCareConcern(UUID.randomUUID().toString(), HealthMetric.GLUCOSE, 1, now, now, "old",
            assessment(a), stage = HealthCareStage.MAINTENANCE, reviewNote = "Prior review", reviewedBy = "user")
        val updated = HealthCarePolicy.reconcile(issue, issue.metric, issue.assessment, "new", now + 1)!!
        assertEquals(HealthCareStage.REASSESS, updated.stage)
        assertEquals(HealthCareStage.PAUSED, HealthCarePolicy.reconcile(issue.copy(stage = HealthCareStage.PAUSED),
            issue.metric, issue.assessment, "new", now + 1)!!.stage)
        assertEquals(issue, HealthCarePolicy.reconcile(issue, issue.metric, issue.assessment, "old", now))
    }
    @Test fun planningAndContinuationKeepTheCompleteAuthorizedHistoryAndVersion() {
        val a = sample()
        val series = HealthCareSeries(listOf(a) + (1..29).map { sample(now - it * 1000L) }, true)
        val issue = HealthCareConcern(UUID.randomUUID().toString(), HealthMetric.GLUCOSE, 1, now, now, "a".repeat(64),
            assessment(a, series))
        val snapshot = HealthCareDiscussionPolicy.snapshot(issue)
        val goal = HealthCareDiscussionPolicy.prompt("Read the earliest result without modifying any plan", snapshot)
        assertTrue(goal.length > 8000)
        assertTrue(HealthCareDiscussionPolicy.hasStructuredContext(goal))
        assertTrue(HealthCareDiscussionPolicy.hasStructuredContext(goal + " User question: quoted text"))
        val request = request(goal)
        val expected = JSONObject(snapshot).toString()
        listOf(AgentSupervisedProjectLoop.planningPrompt(request), AgentSupervisedProjectLoop.continuationPrompt(request)).forEach { prompt ->
            val payload = prompt.substringAfter("Authorized concern snapshot:").substringBefore("User question:").trim()
            assertEquals(expected, JSONObject(payload).toString())
            assertTrue(prompt.contains("Read the earliest result without modifying any plan"))
        }
        val observed = request.copy(executionHistory = (1..6).map { index ->
            AgentAction("source-$index", AgentActionKind.CALL_NATIVE_TOOL, "galaxyssi.web.intelligence.fetch",
                AgentRisk.LOW, AgentActionStatus.COMPLETED, "Read synthetic source $index",
                parameters = mapOf("tool_id" to "galaxyssi.web.intelligence.fetch"),
                evidence = "Source $index: " + "Synthetic source paragraph with complete source evidence. ".repeat(180) + " latest-evidence-$index")
        })
        val continued = AgentSupervisedProjectLoop.continuationPrompt(observed)
        assertEquals(expected, JSONObject(continued.substringAfter("Authorized concern snapshot:")
            .substringBefore("User question:").trim()).toString())
        assertTrue(continued.contains("latest-evidence-6"))
        assertTrue(continued.length <= 196_608)
    }
    @Test fun oversizedHealthGoalFailsExplicitlyInsteadOfSendingPartialEvidence() {
        val a = sample()
        val issue = HealthCareConcern(UUID.randomUUID().toString(), HealthMetric.GLUCOSE, 1, now, now, "clock", assessment(a))
        val goal = HealthCareDiscussionPolicy.prompt("x".repeat(70_000), HealthCareDiscussionPolicy.snapshot(issue))
        val failed = runCatching { AgentSupervisedProjectLoop.planningPrompt(request(goal)) }
        assertTrue(failed.exceptionOrNull() is IllegalArgumentException)
        assertFalse(HealthCareDiscussionPolicy.hasStructuredContext("Read health data: {\"input_version\":\"clock\"}"))
    }
    @Test fun cursorIsPairedExactAndUsesSourceId() {
        assertNull(HealthCareHistoryTool.cursor(emptyMap()))
        val id = UUID.randomUUID().toString()
        assertEquals(HealthPageCursor(now, id), HealthCareHistoryTool.cursor(mapOf("before_time" to now, "before_id" to id)))
        listOf(mapOf("before_id" to id), mapOf("before_time" to now), mapOf("before_time" to -1, "before_id" to id),
            mapOf("before_time" to 1.5, "before_id" to id), mapOf("before_time" to now, "before_id" to "other")).forEach {
            assertTrue(runCatching { HealthCareHistoryTool.cursor(it) }.isFailure)
        }
    }
    @Test fun nativeToolScopeAndSchemaCannotSelectOtherMetricsOrPeople() {
        var called = false
        val definition = HealthCareHistoryTool.definition { _, _ -> called = true; JSONObject().put("done", true) }
        val registry = AgentNativeToolRegistry().register(definition)
        registry.invoke(HealthCareHistoryTool.ID, mapOf("input_version" to "x", "profile" to "other"), AgentNativeToolInvocationContext())
        assertFalse(called)
        registry.invoke(HealthCareHistoryTool.ID, mapOf("input_version" to "x"), AgentNativeToolInvocationContext())
        assertTrue(called)
        assertEquals(AgentNativeToolEffect.READ_ONLY, definition.descriptor.effect)
        assertTrue(HealthCareHistoryTool.ID in HealthCareDiscussionPolicy.discussionTools)
        assertTrue(PhoneAssistantToolPolicy.allowsRemotePhoneTool(HealthCareHistoryTool.ID))
    }
    @Test fun observationCompactionRetainsWholeRowsAndResumesBeforeFirstOmittedRow() {
        val latest = sample()
        val samples = listOf(latest) + (1..29).map { sample(now - it * 1000) }
        val raw = JSONObject().put("protocol", HealthCareHistoryObservation.PROTOCOL).put("input_version", "a".repeat(64))
            .put("metric", "GLUCOSE").put("page_start", JSONObject.NULL).put("history", HealthCareSeries(samples, false).modelJson(latest, null, null))
            .put("next", JSONObject.NULL).put("done", true).put("stability_verified", false).toString()
        val saved = AgentSessionPersistencePolicy.compactActionText(raw)
        val compact = AgentPlannerObservation.sanitize(saved, 1200)!!
        assertTrue(compact.length <= 1200)
        val result = JSONObject(compact); val shown = result.getJSONObject("history").getJSONArray("samples")
        assertTrue(shown.length() in 1..29); assertFalse(result.getBoolean("done"))
        assertTrue(result.getJSONObject("history").getBoolean("has_earlier"))
        val last = shown.getJSONObject(shown.length() - 1)
        assertEquals(last.getJSONObject("record").getString("id"), result.getJSONObject("next").getString("before_id"))
        assertEquals(last.getLong("measured_at"), result.getJSONObject("next").getLong("before_time"))
        assertEquals(compact, HealthCareHistoryObservation.compact(compact, 1200))
        assertFalse(result.getBoolean("stability_verified"))
    }
    @Test fun insufficientObservationBudgetDoesNotAdvanceHistoryCursor() {
        val latest = sample()
        val start = JSONObject().put("before_time", now + 1000).put("before_id", UUID.randomUUID().toString())
        val raw = JSONObject().put("protocol", HealthCareHistoryObservation.PROTOCOL).put("input_version", "a".repeat(64))
            .put("metric", "GLUCOSE").put("page_start", start).put("history", HealthCareSeries(listOf(latest), false).modelJson(latest, null, null))
            .put("next", JSONObject.NULL).put("done", true).toString()
        val result = JSONObject(HealthCareHistoryObservation.compact(raw, 550)!!)
        assertTrue(result.getBoolean("read_again")); assertFalse(result.getBoolean("done"))
        assertEquals(start.toString(), result.getJSONObject("next").toString())
    }
    @Test fun malformedHistoryAndTinyBudgetsCannotCrashGenericObservationHandling() {
        assertNull(HealthCareHistoryObservation.compact("not JSON", 100))
        val raw = JSONObject().put("protocol", HealthCareHistoryObservation.PROTOCOL).put("payload", "x".repeat(5000)).toString()
        assertTrue(JSONObject(HealthCareHistoryObservation.compact(raw, 1200)!!).has("error"))
        assertEquals("{}", HealthCareHistoryObservation.compact(raw, 2))
        assertEquals("", HealthCareHistoryObservation.compact(raw, 0))
    }
}

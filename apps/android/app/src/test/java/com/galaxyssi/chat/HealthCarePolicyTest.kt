package com.galaxyssi.chat

import java.util.UUID
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class HealthCarePolicyTest {
    private val now = 1_793_000_000_000L
    private fun reading(value: String = "6.3", reference: String = "4-6", unit: String = "mmol/L", at: Long = now,
        metric: HealthMetric = HealthMetric.GLUCOSE, condition: String = "fasting") = HealthObservation(UUID.randomUUID().toString(), 1,
        HealthDraft(metric, mapOf(metric.fields.single() to value), unit, at, condition = condition, reference = reference), at)
    private fun ref(r: HealthObservation) = HealthCareRecordRef(r.id, r.revision)
    private fun verified(r: HealthObservation) = HealthCareContext(ref(r), HealthCareTruth.YES, HealthCareTruth.NO,
        HealthCareTruth.NO, HealthCareSpecimen.LAB_PLASMA, 8, confirmedAt = now)
    private fun assess(r: HealthObservation, context: HealthCareContext? = null) =
        requireNotNull(HealthCarePolicy.assess(r.draft.metric, listOf(r), context))
    private fun concern(r: HealthObservation = reading()) = requireNotNull(HealthCarePolicy.reconcile(null, r.draft.metric, assess(r), "clock1", now))

    @Test fun noTargetIsInferredFromReferenceMidpointOrNearBoundary() {
        val r = reading("5.8")
        val c = concern(r)
        assertFalse(HealthCareSignal.REPORT_HIGH in c.assessment.signals)
        assertNull(c.target)
        assertNull(c.assessment.guideline)
        assertEquals(setOf(HealthCareSignal.GLUCOSE_CONTEXT), c.assessment.signals)
    }
    @Test fun glucoseIsNotDiagnosedOrGivenARetestDeadlineFromOneReading() {
        val r = reading(); val a = assess(r, verified(r))
        assertTrue(HealthCareSignal.GUIDELINE_REVIEW in a.signals)
        assertNotNull(a.guideline)
        val c = HealthCarePolicy.reconcile(null, r.draft.metric, a, "v", now)!!
        assertTrue(c.actions.isEmpty()); assertNull(c.nextDue); assertNull(c.target)
    }
    @Test fun guidelineRequiresAdultNonpregnantLaboratoryFastingWithoutKnownDiabetes() {
        val r = reading(); val context = verified(r)
        val exclusions = listOf(context.copy(adult = HealthCareTruth.UNKNOWN), context.copy(adult = HealthCareTruth.NO),
            context.copy(pregnant = HealthCareTruth.UNKNOWN), context.copy(pregnant = HealthCareTruth.YES),
            context.copy(diagnosedDiabetes = HealthCareTruth.UNKNOWN), context.copy(diagnosedDiabetes = HealthCareTruth.YES),
            context.copy(fastingHours = 7), context.copy(fastingHours = null),
            context.copy(specimen = HealthCareSpecimen.HOME_CAPILLARY), context.copy(specimen = HealthCareSpecimen.INTERSTITIAL),
            context.copy(specimen = HealthCareSpecimen.UNKNOWN))
        exclusions.forEach { assertNull(assess(r, it).guideline) }
    }
    @Test fun measurementConditionAndCatalogLaboratoryFlagDoNotSubstituteForConfirmedContext() {
        val r = reading(condition = "fasting")
        assertNull(assess(r).guideline)
        assertTrue(HealthCareSignal.GLUCOSE_CONTEXT in assess(r).signals)
    }
    @Test fun knownOutOfScopeContextRequestsApplicableEvidenceInsteadOfRepeatingTheSameQuestion() {
        val r = reading()
        val a = assess(r, verified(r).copy(diagnosedDiabetes = HealthCareTruth.YES))
        assertNull(a.guideline)
        assertTrue(HealthCareSignal.GUIDELINE_SCOPE in a.signals)
        assertFalse(HealthCareSignal.GLUCOSE_CONTEXT in a.signals)
    }
    @Test fun aPostMealReadingDoesNotUseTheFastingScreeningThreshold() {
        val r = reading("6.3", reference = "", condition = "after_meal")
        assertTrue(assess(r).signals.isEmpty())
        assertNull(HealthCarePolicy.reconcile(null, r.draft.metric, assess(r), "post-meal", now))
    }
    @Test fun confirmationDoesNotLeakAcrossMeasurementRevisionsOrOtherMeasurements() {
        val r = reading(); val c = verified(r)
        assertNull(assess(r.copy(revision = 2), c).guideline)
        assertNull(assess(reading(), c).guideline)
    }
    @Test fun publishedUnitBoundariesAreNotChangedByRoundingConversion() {
        for ((v, unit, matches) in listOf(Triple("99.9", "mg/dL", false), Triple("100", "mg/dL", true),
            Triple("5.59", "mmol/L", false), Triple("5.6", "mmol/L", true))) {
            val r = reading(v, "", unit)
            assertEquals(matches, assess(r, verified(r)).guideline != null)
        }
    }
    @Test fun reportedComparisonAndRangesAreNotExactMeasurements() {
        listOf(">6.3", "<6.3", "5-7", "positive").forEach { value ->
            val r = reading(value)
            assertNull(assess(r, verified(r)).guideline)
            assertTrue(HealthCareSignal.RESULT_NOT_EXACT in assess(r).signals)
        }
    }
    @Test fun referenceOperatorBoundariesAreRespectedForAllSupportedForms() {
        for ((range, high) in listOf("<6" to true, "<=6" to false, "4-6" to false)) {
            assertEquals(high, HealthCareSignal.REPORT_HIGH in assess(reading("6", range)).signals)
        }
        assertTrue(HealthCareSignal.REPORT_LOW in assess(reading("4", ">4")).signals)
        assertFalse(HealthCareSignal.REPORT_LOW in assess(reading("4", ">=4")).signals)
    }
    @Test fun noIssueForNormalSingleResultAndNoInventedGoal() {
        val r = reading("5.0")
        assertNull(HealthCarePolicy.reconcile(null, r.draft.metric, assess(r), "v", now))
    }
    @Test fun anImprovedResultDoesNotAutomaticallyCloseAnExistingIssue() {
        val old = concern(); val r = reading("5.0", at = now + 1)
        val next = HealthCarePolicy.reconcile(old, r.draft.metric, assess(r), "v2", now + 2)!!
        assertEquals(old.id, next.id); assertEquals(HealthCareStage.REASSESS, next.stage)
        assertNull(next.target)
    }
    @Test fun duplicateEvaluationDoesNotCreateAnotherRevision() {
        val c = concern()
        assertEquals(c, HealthCarePolicy.reconcile(c, c.metric, c.assessment, c.inputVersion, now + 100))
    }
    @Test fun sourceRemovalInvalidatesAssessmentWithoutPretendingTheIssueIsResolved() {
        val c = concern(); val next = HealthCarePolicy.reconcile(c, c.metric, null, "deleted", now + 1)!!
        assertNull(next.assessment.record); assertEquals(setOf(HealthCareSignal.SOURCE_REMOVED), next.assessment.signals)
        assertEquals(HealthCareStage.VERIFY_CONTEXT, next.stage)
    }
    @Test fun pauseSurvivesNewMeasurementsWithoutDiscardingEvidence() {
        val c = concern().copy(stage = HealthCareStage.PAUSED)
        val next = HealthCarePolicy.reconcile(c, c.metric, assess(reading("6.8")), "v2", now + 1)!!
        assertEquals(HealthCareStage.PAUSED, next.stage); assertEquals("6.8", next.assessment.value)
    }
    @Test fun baselineUsesComparableMeasurementsAndNeverBecomesATarget() {
        val r = reading("6.3")
        val before = listOf(reading("5.7", at = now - 86_400_000), reading("5.4", at = now - 2 * 86_400_000))
        val a = HealthCarePolicy.assess(r.draft.metric, listOf(r) + before, verified(r))!!
        assertNotNull(a.baseline); assertTrue(HealthCareSignal.RISING_SERIES in a.signals)
        val c = HealthCarePolicy.reconcile(null, r.draft.metric, a, "v", now)!!
        assertNull(c.target)
        val mixed = before.map { it.copy(draft = it.draft.copy(condition = "after_meal")) }
        assertNull(HealthCarePolicy.assess(r.draft.metric, listOf(r) + mixed, null)!!.baseline)
    }
    @Test fun recordsFromAnotherProfileOrMetricNeverEnterTheEvidence() {
        val wrong = reading("99").copy(profileId = "someone-else")
        assertNull(HealthCarePolicy.assess(HealthMetric.GLUCOSE, listOf(wrong), null))
        assertNull(HealthCarePolicy.assess(HealthMetric.HBA1C, listOf(reading()), null))
    }
    @Test fun maintenanceRequiresExplicitReviewButDoesNotForceAnInventedNumericTarget() {
        val c = concern()
        assertTrue(runCatching { HealthCarePolicy.review(c, HealthCareStage.MAINTENANCE, "", "user", now) }.isFailure)
        assertTrue(runCatching { c.copy(stage = HealthCareStage.CLOSED) }.isFailure)
        val reviewed = HealthCarePolicy.review(c, HealthCareStage.MAINTENANCE, "Clinician reviewed; no numerical target indicated", "user-reported clinician review", now)
        assertEquals(HealthCareStage.MAINTENANCE, reviewed.stage); assertNull(reviewed.target)
        assertEquals(HealthCareStage.CLOSED, HealthCarePolicy.review(c, HealthCareStage.CLOSED, "Reviewed with clinician", "user", now).stage)
    }
    @Test fun targetsRequireAnExplicitBasisAndConfirmation() {
        assertTrue(runCatching { HealthCareTarget("glucose", "5", "5", "mmol/L", "", "", "", now) }.isFailure)
        assertTrue(runCatching { HealthCareTarget("glucose", "6", "4", "mmol/L", "reason", "source", "clinician", now) }.isFailure)
    }
    @Test fun proposedActionsDoNotScheduleNotificationsUntilConfirmed() {
        val proposed = HealthCareAction(UUID.randomUUID().toString(), HealthCareActionKind.RECHECK, "Discuss repeat testing",
            "Individual review needed", "Clinician recommendation", dueFrom = now + 10, dueUntil = now + 20)
        val c = concern().copy(actions = listOf(proposed))
        assertNull(c.nextDue)
        val confirmed = proposed.copy(state = HealthCareActionState.CONFIRMED, confirmedAt = now)
        assertEquals(now + 10, c.copy(actions = listOf(confirmed)).nextDue)
        assertNull(c.copy(actions = listOf(confirmed), stage = HealthCareStage.PAUSED).nextDue)
        assertTrue(runCatching { proposed.copy(state = HealthCareActionState.CONFIRMED) }.isFailure)
    }
    @Test fun allFourEvidenceBasesRemainDistinctAcrossSerialization() {
        val r = reading(); val a = assess(r, verified(r))
        val c = concern(r).copy(assessment = a, context = verified(r), target = HealthCareTarget("glucose", "4.5", "5.5", "mmol/L",
            "Synthetic clinician target, not a recommendation", "test clinical plan", "fixture clinician", now))
        assertEquals(c, HealthCareConcern.from(JSONObject(c.json().toString())))
        assertEquals("4-6", c.assessment.reportReference); assertNull(c.assessment.baseline)
        assertEquals("4.5", c.target!!.low); assertEquals("2026", c.assessment.guideline!!.version)
    }
}

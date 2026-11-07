package com.galaxyssi.chat

import java.util.UUID
import org.junit.Assert.*
import org.junit.Test

class HealthCarePriorityTest {
    private val now = 1_793_000_000_000L
    private fun reading(s: String = "181", d: String = "80", unit: String = "mmHg", at: Long = now) =
        HealthObservation(UUID.randomUUID().toString(), 1, HealthDraft(HealthMetric.BLOOD_PRESSURE,
            mapOf("systolic" to s, "diastolic" to d), unit, at, condition = "resting"), at)
    private fun assessment(r: HealthObservation) = HealthCarePolicy.assess(HealthMetric.BLOOD_PRESSURE, listOf(r), null)!!

    @Test fun eitherComponentCanRequirePriorityWithoutAReportRange() {
        assertTrue(HealthCarePriority.needsReview(reading("181", "80").draft))
        assertTrue(HealthCarePriority.needsReview(reading("170", "121").draft))
        assertTrue(HealthCarePriority.needsReview(reading("181", "121").draft))
    }
    @Test fun publishedStrictBoundariesDoNotBecomeGreaterOrEqual() {
        listOf(reading("180", "120"), reading("179.9", "119.9"), reading("120", "80")).forEach {
            assertFalse(HealthCarePriority.needsReview(it.draft))
        }
    }
    @Test fun kpaComparisonDoesNotRoundTheMeasurementOrThreshold() {
        assertFalse(HealthCarePriority.needsReview(reading("23.998032", "15.998688", "kPa").draft))
        assertTrue(HealthCarePriority.needsReview(reading("23.998033", "10", "kPa").draft))
        assertTrue(HealthCarePriority.needsReview(reading("23", "15.998689", "kPa").draft))
    }
    @Test fun incompleteInvalidOrOtherMetricValuesAreNotClassifiedAsBloodPressure() {
        val draft = reading().draft
        listOf(draft.copy(values = mapOf("systolic" to "181")), draft.copy(unit = "mg/dL"),
            draft.copy(values = mapOf("systolic" to "error", "diastolic" to "80")),
            draft.copy(metric = HealthMetric.GLUCOSE, values = mapOf("glucose" to "190"), unit = "mg/dL")).forEach {
            assertFalse(HealthCarePriority.needsReview(it))
        }
    }
    @Test fun pulseNeverBecomesBloodPressureAndDoesNotUsePressureUnitsInTheSummary() {
        val r = reading("120", "80").let { it.copy(draft = it.draft.copy(values = it.draft.values + ("pulse" to "190"))) }
        val a = assessment(r)
        assertEquals(0, HealthCarePriority.rank(a)); assertEquals("120 / 80", a.value)
        assertEquals("bpm", a.sample!!.unitFor("pulse"))
    }
    @Test fun historicalReadingCarriesItsTimestampWithoutClaimingCurrentEmergency() {
        val a = assessment(reading(at = now - 365L * 86_400_000))
        val issue = HealthCarePolicy.reconcile(null, HealthMetric.BLOOD_PRESSURE, a, "v", now)!!
        val handoff = HealthCarePriority.handoff(issue)!!
        assertFalse(handoff.getBoolean("current_emergency_established"))
        assertEquals("unknown", handoff.getString("current_symptoms"))
        assertEquals(a.measuredAt, handoff.getLong("recorded_at"))
        assertTrue(issue.actions.isEmpty()); assertNull(issue.target); assertNull(issue.nextDue)
    }
    @Test fun unknownOrOutOfScopeContextCannotBePresentedAsConfirmedEligibility() {
        val r = reading(); val ref = HealthCareRecordRef(r.id, 1)
        listOf(null, HealthCareContext(ref, adult = HealthCareTruth.NO, confirmedAt = now),
            HealthCareContext(ref, pregnant = HealthCareTruth.YES, confirmedAt = now)).forEach { c ->
            val a = HealthCarePolicy.assess(HealthMetric.BLOOD_PRESSURE, listOf(r), c)!!
            assertEquals(1, HealthCarePriority.rank(a))
            assertTrue(a.guideline!!.applicability.contains("must not be assumed"))
        }
    }
    @Test fun latestCorrectedValueCanRemoveTheWarningButCannotAutomaticallyCloseTracking() {
        val r = reading(); val a = assessment(r)
        val issue = HealthCarePolicy.reconcile(null, HealthMetric.BLOOD_PRESSURE, a, "v1", now)!!
        val corrected = r.copy(revision = 2, draft = r.draft.copy(values = mapOf("systolic" to "120", "diastolic" to "80")))
        val next = HealthCarePolicy.reconcile(issue, issue.metric, assessment(corrected), "v2", now + 1)!!
        assertEquals(0, HealthCarePriority.rank(next.assessment)); assertTrue(next.open)
        assertEquals(HealthCareStage.REASSESS, next.stage); assertNull(HealthCarePriority.handoff(next))
    }
    @Test fun assessmentAndSignalRoundTripWithoutLosingSourceOrTimestamp() {
        val a = assessment(reading())
        assertEquals(a, HealthCareAssessment.from(a.json()))
        assertEquals(HealthCarePriority.SOURCE, a.guideline!!.url)
        assertEquals(1, HealthCarePriority.rank(a))
    }
    @Test fun newRuleVersionOnlyInvalidatesBloodPressureEvaluationCache() {
        HealthMetric.entries.forEach {
            assertEquals(if (it == HealthMetric.BLOOD_PRESSURE) HealthCarePriority.BLOOD_PRESSURE_VERSION else "",
                HealthCarePriority.evaluationVersion(it))
        }
    }
    @Test fun authorizedSnapshotCarriesWarningAndPromptDoesNotRequireWaitingForResearch() {
        val issue = HealthCarePolicy.reconcile(null, HealthMetric.BLOOD_PRESSURE, assessment(reading()), "v", now)!!
        val snapshot = HealthCareDiscussionPolicy.snapshot(issue)
        assertTrue(snapshot.contains("priority_notice")); assertTrue(snapshot.contains("current_symptoms"))
        val prompt = HealthCareDiscussionPolicy.prompt("What next?", snapshot)
        assertTrue(prompt.contains("Never delay emergency help"))
        assertTrue(prompt.contains("old imported record"))
    }
}

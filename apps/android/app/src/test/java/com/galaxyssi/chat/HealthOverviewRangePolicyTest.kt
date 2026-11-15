package com.galaxyssi.chat

import java.util.UUID
import org.junit.Assert.*
import org.junit.Test

class HealthOverviewRangePolicyTest {
    private val now = 1_760_000_000_000L
    private fun record(value: String, reference: String): HealthObservation = HealthObservationPolicy.observation(
        HealthDraft(HealthMetric.GLUCOSE, mapOf("glucose" to value), "mmol/L", now, condition = "fasting", reference = reference), now)

    @Test fun usesOnlyTheRecordedRangeAndHonorsInclusiveAndExclusiveBounds() {
        for ((value, range, expected) in listOf(
            Triple("3.8", "3.9-6.1", HealthOverviewRangePosition.BELOW),
            Triple("6.1", "3.9-6.1", HealthOverviewRangePosition.WITHIN),
            Triple("6.2", "3.9-6.1", HealthOverviewRangePosition.ABOVE),
            Triple("6.1", "<6.1", HealthOverviewRangePosition.ABOVE),
            Triple("6.1", "<=6.1", HealthOverviewRangePosition.WITHIN),
            Triple("3.9", ">3.9", HealthOverviewRangePosition.BELOW),
            Triple("3.9", ">=3.9", HealthOverviewRangePosition.WITHIN),
            Triple("<6.2", "3.9-6.1", HealthOverviewRangePosition.NOT_COMPARABLE)
        )) {
            val bound = requireNotNull(HealthOverviewRangePolicy.report(record(value, range)))
            assertEquals(expected, bound.position)
            assertEquals(range, bound.bounds)
        }
        assertNull(HealthOverviewRangePolicy.report(record("6.2", "")))
        assertNull(HealthOverviewRangePolicy.report(record("6.2", "70-110 mg/dL")))
        assertNull(HealthOverviewRangePolicy.report(record("6.2", "normal")))
    }

    @Test fun bloodPressureTargetIsAppliedOnlyToItsBoundComponentAndRecordRevision() {
        val sample = HealthObservationPolicy.observation(HealthDraft(values = mapOf("systolic" to "127", "diastolic" to "78"),
            measuredAt = now), now)
        val assessment = requireNotNull(HealthCarePolicy.assess(HealthMetric.BLOOD_PRESSURE, listOf(sample), null))
        val issue = HealthCareConcern(UUID.randomUUID().toString(), HealthMetric.BLOOD_PRESSURE, 1, now, now, "fixture", assessment)
        val target = HealthCareTarget("systolic", "100", "125", "mmHg", "fixture", "source", "user", now,
            planId = UUID.randomUUID().toString(), basis = HealthCareTargetPolicy.basis(issue))
        val active = issue.copy(target = target)
        val bound = requireNotNull(HealthOverviewRangePolicy.target(sample, active))
        assertEquals("systolic", bound.field)
        assertEquals("100\u2013125", bound.bounds)
        assertEquals(HealthOverviewRangePosition.ABOVE, bound.position)
        assertNull(HealthOverviewRangePolicy.target(sample.copy(revision = 2), active))
        assertNull(HealthOverviewRangePolicy.target(sample, active.copy(inputVersion = "changed")))
        assertNull(HealthOverviewRangePolicy.target(sample, active.copy(stage = HealthCareStage.PAUSED)))
    }
}

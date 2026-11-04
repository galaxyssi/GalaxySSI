package com.galaxyssi.chat

import java.math.BigDecimal
import java.time.LocalDate
import java.time.ZoneId
import org.junit.Assert.*
import org.junit.Test

class HealthWeeklyReportTest {
    private val first = LocalDate.of(2026, 10, 28)
    private val zone = ZoneId.of("America/New_York")
    private val scope = HealthWeeklyScope(first.plusDays(6), zone)
    private fun row(metric: HealthMetric, day: Int, value: String, unit: String = metric.units.first(), hour: Int = 12) =
        HealthObservation("$day:$hour", 1, HealthDraft(metric, metric.requiredFields.associateWith { value }, unit,
            first.plusDays(day.toLong()).atTime(hour, 0).atZone(zone).toInstant().toEpochMilli()), 0)
    private fun accumulator(metric: HealthMetric) = HealthWeeklyAccumulator(metric, first, 7, zone)
    private fun equal(expected: String, actual: BigDecimal?) = assertEquals(0, BigDecimal(expected).compareTo(requireNotNull(actual)))

    @Test fun weeklyRangeUsesCalendarDaysAcrossFallDst() {
        assertEquals(first, scope.first)
        assertEquals(169L, (scope.until - scope.from) / 3_600_000L)
        assertEquals(scope.first.minusDays(14), scope.baselineFirst)
        assertEquals(scope.from, scope.baselineScope().until)
    }
    @Test fun sleepNormalizesHoursAndMinutesAndGivesDaysEqualWeight() {
        val metric = HealthMetric.SLEEP_DURATION
        val builder = accumulator(metric)
        builder.add(row(metric, 0, "6", "h"))
        builder.add(row(metric, 0, "480", "min", 13))
        builder.add(row(metric, 1, "360", "min"))
        val result = builder.finish()
        equal("390", result.mean)
        assertEquals(2, result.validDays)
        assertEquals(3L, result.records)
    }
    @Test fun stepsUseLatestDayCountRegardlessOfScanOrderAndKeepExplicitZero() {
        val metric = HealthMetric.STEPS
        val builder = accumulator(metric)
        builder.add(row(metric, 0, "8000", hour = 20))
        builder.add(row(metric, 0, "3000", hour = 8))
        builder.add(row(metric, 3, "0"))
        val result = builder.finish()
        equal("4000", result.mean)
        assertEquals(2, result.validDays)
    }
    @Test fun pressureCountsCompletePairsWithoutTreatingPulseAsAnotherReading() {
        val metric = HealthMetric.BLOOD_PRESSURE
        val builder = accumulator(metric)
        val a = row(metric, 0, "100")
        builder.add(a.copy(draft = a.draft.copy(values = mapOf("systolic" to "120", "diastolic" to "80", "pulse" to "72"))))
        val b = row(metric, 0, "110", "kPa", 17)
        builder.add(b.copy(draft = b.draft.copy(values = mapOf("systolic" to "16", "diastolic" to "10"))))
        val result = builder.finish()
        assertEquals(2L, result.exactRecords)
        assertEquals(1, result.validDays)
        assertNull(result.mean)
    }
    @Test fun temperatureNormalizesFahrenheitWithoutMixingRawUnits() {
        val metric = HealthMetric.TEMPERATURE
        val builder = accumulator(metric)
        builder.add(row(metric, 0, "98.6", "\u00b0F"))
        builder.add(row(metric, 1, "37", "\u00b0C"))
        equal("37", builder.finish().mean)
    }
    @Test fun emptyAndNonExactDaysNeverBecomeZeroOrUsableDays() {
        val metric = HealthMetric.SLEEP_DURATION
        val builder = accumulator(metric)
        assertNull(builder.finish().mean)
        builder.add(row(metric, 1, "<8", "h"))
        val result = builder.finish()
        assertEquals(1, result.recordedDays)
        assertEquals(0, result.validDays)
        assertNull(result.mean)
    }
    @Test fun baselineComparisonIsSuppressedUntilBothWindowsHaveCoverage() {
        val metric = HealthMetric.SLEEP_DURATION
        val current = HealthWeeklyStat(metric, 6, 6, 6, 6, BigDecimal(384))
        val baseline = HealthWeeklyStat(metric, 12, 12, 12, 12, BigDecimal(432))
        equal("-48", HealthWeeklyComparison(current, baseline).deltaMinutes)
        assertNull(HealthWeeklyComparison(current.copy(validDays = 4), baseline).deltaMinutes)
        assertNull(HealthWeeklyComparison(current, baseline.copy(validDays = 9)).deltaMinutes)
    }
    @Test fun exclusionsDoNotReadBaselineWithoutBothSleepAndComparison() {
        assertTrue(scope.hasBaseline)
        assertFalse(scope.copy(comparison = false).hasBaseline)
        assertFalse(scope.copy(metrics = setOf(HealthMetric.STEPS)).hasBaseline)
    }
}

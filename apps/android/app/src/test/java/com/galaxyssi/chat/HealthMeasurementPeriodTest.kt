package com.galaxyssi.chat

import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import org.junit.Assert.*
import org.junit.Test

class HealthMeasurementPeriodTest {
    private val week = HealthMeasurementPeriodKind.WEEK
    private val month = HealthMeasurementPeriodKind.MONTH
    private fun period(kind: HealthMeasurementPeriodKind, date: String) = HealthMeasurementPeriod.of(kind, LocalDate.parse(date))
    private fun sample(id: String, time: Long, value: String = "5.4", condition: String = "fasting", unit: String = "mmol/L") =
        HealthObservation(id, 1, HealthDraft(HealthMetric.GLUCOSE, mapOf("glucose" to value), unit, time, condition, reference = "4-6"), time + 5_000_000)
    @Test fun naturalWeekStartsOnMondayAndIncludesSunday() {
        val a = period(week, "2026-11-16"); val b = period(week, "2026-11-22")
        assertEquals(a, b); assertEquals(LocalDate.parse("2026-11-23"), a.end)
    }
    @Test fun adjacentMondayBelongsToANewWeek() { assertNotEquals(period(week, "2026-11-22"), period(week, "2026-11-23")) }
    @Test fun weekCanCrossCalendarYearWithoutSplittingByUploadDate() {
        assertEquals(period(week, "2025-12-29"), period(week, "2026-01-04"))
    }
    @Test fun calendarMonthsAreNotThirtyDayWindows() {
        val february = period(month, "2024-02-29")
        assertEquals(LocalDate.parse("2024-02-01"), february.first); assertEquals(LocalDate.parse("2024-03-01"), february.end)
        assertEquals(LocalDate.parse("2024-01-01"), february.previous().first)
    }
    @Test fun monthBoundaryUsesSamplingTimezone() {
        val instant = Instant.parse("2026-10-31T16:30:00Z")
        assertEquals(LocalDate.parse("2026-11-01"), HealthMeasurementPeriod.of(month, instant.atZone(ZoneId.of("Asia/Shanghai")).toLocalDate()).first)
        assertEquals(LocalDate.parse("2026-10-01"), HealthMeasurementPeriod.of(month, instant.atZone(ZoneId.of("UTC")).toLocalDate()).first)
    }
    @Test fun daylightSavingMonthUsesCalendarBoundariesNotFixedMilliseconds() {
        val p = period(month, "2026-03-15"); val zone = ZoneId.of("America/New_York")
        assertEquals(31L * 24 * 3_600_000 - 3_600_000, p.until(zone) - p.from(zone))
    }
    @Test fun persistedSelectionRequiresACanonicalPeriod() {
        val p = period(week, "2026-11-18")
        assertEquals(p, HealthMeasurementPeriod.parse(p.key)); assertNull(HealthMeasurementPeriod.parse("WEEK:2026-11-18"))
        assertNull(HealthMeasurementPeriod.parse("job:00000000-0000-0000-0000-000000000000"))
    }
    @Test fun epochWeekDoesNotDropFirstDaysOf1970() {
        assertEquals(LocalDate.parse("1969-12-29"), period(week, "1970-01-01").first)
    }
    @Test fun repeatedMeasurementsCountRecordsAndRetainActualLatestValueNotAMean() {
        val builder = HealthMeasurementPeriods.Builder()
        builder.add(sample("a", 2000, "5.1")); builder.add(sample("b", 1000, "6.3"))
        val result = builder.finish(null).series.single()
        assertEquals(2L, result.count); assertEquals("5.1", result.latest.draft.values["glucose"]); assertEquals(1L, result.outsideCount)
    }
    @Test fun fastingPostMealUnitsAndSideAreSeparateSeries() {
        val builder = HealthMeasurementPeriods.Builder()
        builder.add(sample("a", 1)); builder.add(sample("b", 2, condition = "after_meal_2h")); builder.add(sample("c", 3, unit = "mg/dL"))
        builder.add(sample("d", 4).let { it.copy(draft = it.draft.copy(side = "left")) })
        assertEquals(4, builder.finish(null).series.size)
    }
    @Test fun otherProfilesAndStepCountersAreNotClinicalPeriodRecords() {
        val builder = HealthMeasurementPeriods.Builder()
        builder.add(sample("a", 1).copy(profileId = "other"))
        builder.add(HealthObservation("b", 1, HealthDraft(HealthMetric.STEPS, mapOf("steps" to "10"), "steps", 2), 2))
        assertTrue(builder.finish(null).series.isEmpty())
    }
}

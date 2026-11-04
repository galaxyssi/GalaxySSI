package com.galaxyssi.chat

import java.math.BigDecimal
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import java.util.UUID
import org.junit.Assert.*
import org.junit.Test

class HealthTrendPolicyTest {
    private val now = Instant.parse("2026-11-04T12:00:00Z").toEpochMilli()
    private val start = LocalDate.of(2026, 10, 1)
    private fun spec(metric: HealthMetric = HealthMetric.STEPS, days: Long = 7, zone: ZoneId = ZoneId.of("UTC")) =
        HealthTrendSpec(metric, start, start.plusDays(days - 1), zone, metric.units.first())
    private fun record(s: HealthTrendSpec, day: Long, value: String, unit: String = s.unit, hour: Int = 12): HealthObservation {
        val values = s.metric.requiredFields.associateWith { value }
        return HealthObservationPolicy.observation(HealthDraft(s.metric, values, unit,
            s.first.plusDays(day).atTime(hour, 0).atZone(s.zone).toInstant().toEpochMilli()), now)
    }
    private fun build(s: HealthTrendSpec, vararg records: HealthObservation) = HealthTrendBuilder(s).apply { records.forEach(::add) }.finish()
    @Test fun noMeasurementsProduceNoPointsOrFabricatedNormalValues() {
        val result = build(spec()); assertTrue(result.points.isEmpty()); assertEquals(0L, result.eligible); assertEquals(7L, result.missingDays); assertNull(result.latest)
    }
    @Test fun anExplicitZeroIsARealPointNotAMissingDay() {
        val s = spec(); val result = build(s, record(s, 2, "0"))
        assertEquals(BigDecimal.ZERO, result.points.single().value); assertEquals(1, result.numericDays); assertEquals(6L, result.missingDays)
    }
    @Test fun missingDaysAreNotFilledWithZeroOrBridgedByALine() {
        val s = spec(); val result = build(s, record(s, 0, "100"), record(s, 2, "300"))
        assertEquals(listOf(0, 2), result.points.map { it.bucket }); assertTrue(result.points.last().gapBefore)
        assertEquals(2L, result.eligible); assertEquals(5L, result.missingDays)
    }
    @Test fun adjacentRecordedDaysCanBeConnected() {
        val s = spec(); assertFalse(build(s, record(s, 0, "100"), record(s, 1, "200")).points.last().gapBefore)
    }
    @Test fun decimalMeansAreComputedWithoutBinaryFloatingPointError() {
        val s = spec(HealthMetric.GLUCOSE); val result = build(s, record(s, 0, "0.1", hour = 10), record(s, 0, "0.2", hour = 12))
        assertEquals(BigDecimal("0.15"), result.points.single().value); assertEquals(2L, result.points.single().count); assertEquals("", result.points.single().recordId)
    }
    @Test fun aSingleRecordPointRetainsTheExactOriginalRecordId() {
        val s = spec(); val raw = record(s, 0, "100"); assertEquals(raw.id, build(s, raw).points.single().recordId)
    }
    @Test fun minimumAndMaximumNavigateToTheActualContributingRecords() {
        val s = spec(); val low = record(s, 0, "100", hour = 10); val high = record(s, 0, "500", hour = 11)
        assertEquals(low.id, build(s.copy(aggregation = HealthTrendAggregation.MINIMUM), low, high).points.single().recordId)
        assertEquals(high.id, build(s.copy(aggregation = HealthTrendAggregation.MAXIMUM), low, high).points.single().recordId)
    }
    @Test fun equalExtremaUseTheLatestActualRecordIndependentlyOfInputOrder() {
        val s = spec().copy(aggregation = HealthTrendAggregation.MINIMUM); val old = record(s, 0, "100", hour = 10); val recent = record(s, 0, "100", hour = 12)
        assertEquals(recent.id, build(s, recent, old).points.single().recordId)
        assertEquals(build(s, recent, old).points, build(s, old, recent).points)
    }
    @Test fun pressureComponentsShareOneObservationAndDoNotMixPulseUnits() {
        val s = spec(HealthMetric.BLOOD_PRESSURE); val raw = HealthObservationPolicy.observation(HealthDraft(s.metric,
            mapOf("systolic" to "124", "diastolic" to "82", "pulse" to "68"), "mmHg", s.from + 43_200_000), now)
        val result = build(s, raw)
        assertEquals(1L, result.eligible); assertEquals(setOf("systolic", "diastolic"), result.points.map { it.field }.toSet()); assertEquals(1, result.numericDays)
    }
    @Test fun differentUnitsRemainSeparateInsteadOfBeingAveragedTogether() {
        val s = spec(HealthMetric.GLUCOSE); val result = build(s, record(s, 0, "5.4"), record(s, 1, "97", unit = "mg/dL"))
        assertEquals(1L, result.otherUnits); assertEquals(BigDecimal("5.4"), result.points.single().value); assertEquals(1, result.reportedDays)
    }
    @Test fun boundsRangesAndLabelsDoNotBecomeNumericThresholdsOrMidpoints() {
        val s = spec(HealthMetric.CRP); val result = build(s, record(s, 0, "<0.1"), record(s, 1, "1-2"), record(s, 2, "negative"))
        assertEquals(3L, result.nonNumeric); assertTrue(result.points.isEmpty()); assertEquals(3, result.reportedDays); assertEquals(0, result.numericDays)
    }
    @Test fun unitlessQualitativeResultsKeepActualCoverageWithoutANumericCurve() {
        val s = spec(HealthMetric.URINE_PROTEIN); val result = build(s, record(s, 0, "negative"), record(s, 1, "++"))
        assertEquals(2L, result.nonNumeric); assertEquals(2, result.reportedDays); assertEquals(5L, result.missingDays); assertTrue(result.points.isEmpty())
    }
    @Test fun manualFilteringDoesNotTreatAnUnknownDeviceAsManual() {
        val s = spec().copy(source = HealthTrendSource(manualOnly = true)); val manual = record(s, 0, "100"); val device = record(s, 1, "200").copy(source = "device")
        val result = build(s, manual, device); assertEquals(1L, result.total); assertEquals(manual.id, result.latest!!.id)
    }
    @Test fun originalIdentityFiltersNeverUseOnlyAVisibleFileName() {
        val one = UUID.randomUUID().toString(); val two = UUID.randomUUID().toString(); val s = spec().copy(source = HealthTrendSource(originalId = one))
        fun source(record: HealthObservation, id: String) = record.copy(source = "ocr", draft = record.draft.copy(evidence = HealthEvidence(id, UUID.randomUUID().toString(), "reading", "a".repeat(64), 1, "fixture", confirmed = true)))
        assertEquals(1L, build(s, source(record(s, 0, "100"), one), source(record(s, 1, "200"), two)).total)
    }
    @Test fun dateIntervalsIncludeTheirStartButExcludeTheFollowingMidnight() {
        val s = spec(days = 1); val before = record(s, 0, "1").let { it.copy(draft = it.draft.copy(measuredAt = s.from - 1)) }
        val first = record(s, 0, "2").let { it.copy(draft = it.draft.copy(measuredAt = s.from)) }
        val after = record(s, 0, "3").let { it.copy(draft = it.draft.copy(measuredAt = s.until)) }
        assertEquals(1L, build(s, before, first, after).total)
    }
    @Test fun springDaylightSavingUsesCalendarDaysNotSeventyTwoFixedHours() {
        val s = spec(zone = ZoneId.of("America/New_York")).copy(first = LocalDate.of(2026, 3, 7), last = LocalDate.of(2026, 3, 9))
        assertEquals(71L * 3_600_000, s.until - s.from)
        assertEquals(2, build(s, record(s, 0, "100"), record(s, 2, "200")).numericDays)
    }
    @Test fun repeatedFallHoursRemainTwoMeasurementsOnOneCalendarDay() {
        val zone = ZoneId.of("America/New_York"); val day = LocalDate.of(2026, 11, 1); val s = spec(zone = zone).copy(first = day, last = day)
        val a = record(s, 0, "100").let { it.copy(draft = it.draft.copy(measuredAt = day.atTime(LocalTime.of(1, 30)).atZone(zone).withEarlierOffsetAtOverlap().toInstant().toEpochMilli())) }
        val b = record(s, 0, "300").let { it.copy(draft = it.draft.copy(measuredAt = day.atTime(LocalTime.of(1, 30)).atZone(zone).withLaterOffsetAtOverlap().toInstant().toEpochMilli())) }
        assertEquals(25L * 3_600_000, s.until - s.from); assertEquals(1, build(s, a, b).numericDays); assertEquals(BigDecimal("2E+2"), build(s, a, b).points.single().value)
    }
    @Test fun theSelectedTimezoneDeterminesTheCalendarBucket() {
        val s = spec(zone = ZoneId.of("Asia/Shanghai")); val raw = record(s, 0, "100").let { it.copy(draft = it.draft.copy(measuredAt = Instant.parse("2026-10-01T23:00:00Z").toEpochMilli())) }
        assertEquals(1, build(s, raw).points.single().bucket)
    }
    @Test fun longWindowsRetainAllCountsButBoundPlotMemoryAndExposeBucketDates() {
        val s = spec().copy(first = LocalDate.of(1970, 1, 1), last = start)
        val builder = HealthTrendBuilder(s)
        repeat(400) { index -> builder.add(record(s, index * 50L, "${index + 1}")) }
        val result = builder.finish(); assertEquals(400L, result.eligible); assertTrue(result.points.size <= HealthTrendSpec.MAX_POINTS)
        assertTrue(result.points.all { it.first >= s.first && it.last <= s.last }); assertEquals(400, result.numericDays)
    }
    @Test fun theFinalPartialBucketDoesNotExtendPastTheRequestedEnd() {
        val s = spec().copy(first = LocalDate.of(2026, 1, 1), last = LocalDate.of(2026, 5, 1)); val result = build(s, record(s, 120, "100"))
        assertEquals(2, s.bucketDays); assertEquals(s.last, result.points.single().last)
    }
    @Test fun numericPointCohortsRejectOtherUnitsAndNonNumericResults() {
        val s = spec(HealthMetric.CRP)
        assertTrue(s.matches(record(s, 0, "1"), true)); assertFalse(s.matches(record(s, 0, "<1"), true)); assertFalse(s.matches(record(s, 0, "1", "mg/dL"), true))
    }
    @Test fun invalidDatesUnitsAndConflictingSourcesCannotCreateAQueryScope() {
        val s = spec()
        assertTrue(runCatching { s.copy(last = s.first.minusDays(1)) }.isFailure)
        assertTrue(runCatching { s.copy(first = LocalDate.of(1960, 1, 1)) }.isFailure)
        assertTrue(runCatching { s.copy(unit = "invented") }.isFailure)
        assertTrue(runCatching { HealthTrendSource(UUID.randomUUID().toString(), true) }.isFailure)
    }
    @Test fun aWrongMetricCannotSilentlyContaminateTheSeries() {
        assertTrue(runCatching { HealthTrendBuilder(spec()).add(record(spec(HealthMetric.WEIGHT), 0, "68")) }.isFailure)
    }
    @Test fun sourceMeasurementsAndReportedNotationAreNeverModifiedByAggregation() {
        val s = spec(HealthMetric.GLUCOSE); val raw = record(s, 0, "005,60"); val before = raw.json().toString()
        build(s, raw); assertEquals(before, raw.json().toString()); assertEquals("005,60", raw.draft.reportedValues["glucose"])
    }
}

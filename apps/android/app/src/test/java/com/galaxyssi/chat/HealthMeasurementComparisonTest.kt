package com.galaxyssi.chat

import java.math.BigDecimal
import java.time.LocalDate
import java.time.ZoneId
import org.junit.Assert.*
import org.junit.Test

class HealthMeasurementComparisonTest {
    private fun record(value: String = "5.4", condition: String = "fasting", unit: String = "mmol/L", source: String = "manual") =
        HealthObservation("a", 1, HealthDraft(HealthMetric.GLUCOSE, mapOf("glucose" to value), unit, 1, condition), 1, source)
    @Test fun exactDifferenceDoesNotDeclareImprovement() {
        assertEquals(BigDecimal("0.3"), HealthMeasurementPeriods.delta(record("5.1"), record(), "glucose"))
    }
    @Test fun differentUnitsNeverProduceArithmeticDelta() { assertNull(HealthMeasurementPeriods.delta(record(), record(unit = "mg/dL"), "glucose")) }
    @Test fun differentCollectionConditionsNeverProduceArithmeticDelta() { assertNull(HealthMeasurementPeriods.delta(record(), record(condition = "after_meal_2h"), "glucose")) }
    @Test fun unspecifiedCollectionConditionsAreNotEvidenceOfComparability() { assertNull(HealthMeasurementPeriods.delta(record(condition = "unspecified"), record(condition = "unspecified"), "glucose")) }
    @Test fun inequalityAndQualitativeResultsNeverBecomeExactNumbers() { assertNull(HealthMeasurementPeriods.delta(record("<5.1"), record(), "glucose")) }
    @Test fun missingAndOtherProfileReadingsAreExcluded() {
        assertNull(HealthMeasurementPeriods.delta(null, record(), "glucose"))
        assertNull(HealthMeasurementPeriods.delta(record().copy(profileId = "other"), record(), "glucose"))
    }
    @Test fun differentSourceTypesAreNotImplicitlyComparable() { assertNull(HealthMeasurementPeriods.delta(record(), record(source = "ocr"), "glucose")) }
    @Test fun trendFilterKeepsConditionSideAndSource() {
        val filter = HealthTrendSource(condition = "fasting", side = "left", recordSource = "manual")
        assertFalse(filter.accepts(record()))
        assertTrue(filter.accepts(record().let { it.copy(draft = it.draft.copy(side = "left")) }))
        assertFalse(filter.accepts(record(condition = "after_meal_1h").let { it.copy(draft = it.draft.copy(side = "left")) }))
    }
    @Test fun filteredTrendNeverAveragesFastingWithPostMeal() {
        val first = LocalDate.of(2026, 1, 1)
        val spec = HealthTrendSpec(HealthMetric.GLUCOSE, first, first, ZoneId.of("UTC"), "mmol/L", source = HealthTrendSource(condition = "fasting"))
        val time = spec.from + 1_000
        val result = HealthTrendBuilder(spec).apply {
            add(record("5.4").let { it.copy(draft = it.draft.copy(measuredAt = time)) })
            add(record("8.0", "after_meal_2h").let { it.copy(draft = it.draft.copy(measuredAt = time)) })
        }.finish()
        assertEquals(1L, result.eligible); assertEquals(BigDecimal("5.4"), result.points.single().value)
    }
    @Test fun latestReportPointsKeepActualValuesAndNeverImplyMethodContinuity() {
        val first = LocalDate.of(2026, 1, 1)
        val spec = HealthTrendSpec(HealthMetric.GLUCOSE, first, first.plusDays(2), ZoneId.of("UTC"), "mmol/L",
            HealthTrendAggregation.LATEST, HealthTrendSource(condition = "fasting", recordSource = "ocr"))
        fun sample(id: String, offset: Long, value: String) = record(value, source = "ocr").let {
            it.copy(id = id, draft = it.draft.copy(measuredAt = spec.from + offset))
        }
        val result = HealthTrendBuilder(spec).apply {
            add(sample("a", 1000, "5.1")); add(sample("b", 2000, "5.4")); add(sample("c", 86_401_000, "5.6"))
        }.finish()
        assertEquals(listOf("5.4", "5.6"), result.points.map { it.value.toPlainString() })
        assertEquals("b", result.points.first().recordId); assertTrue(result.points.all { it.gapBefore })
        val preview = HealthTrendAnalysis.project(result, "")
        assertNull(preview.facts.single().delta)
    }
}

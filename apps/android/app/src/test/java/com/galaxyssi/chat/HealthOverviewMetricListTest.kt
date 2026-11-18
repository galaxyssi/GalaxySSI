package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class HealthOverviewMetricListTest {
    private fun item(metric: HealthMetric, position: HealthOverviewRangePosition? = null, recorded: Boolean = true): HealthOverviewMetric {
        val draft = HealthDraft(HealthMetric.GLUCOSE, mapOf("glucose" to "5.1"), "mmol/L", 1_760_000_000_000L)
        val record = if (recorded) HealthObservationPolicy.observation(draft, draft.measuredAt) else null
        return HealthOverviewMetric(metric, record, if (recorded) HealthOverviewFreshness.RECENT else HealthOverviewFreshness.MISSING,
            position?.let { listOf(HealthOverviewRange("glucose", HealthOverviewRangeSource.REPORT, "4-6", "mmol/L", it)) }.orEmpty())
    }
    @Test fun emptySelectionHasNoHiddenRows() {
        assertTrue(HealthOverviewPolicy.measurementRows(emptyList(), false).isEmpty())
        assertEquals(0, HealthOverviewPolicy.measurementPreviewSize(emptyList()))
    }
    @Test fun stepTileNeverBecomesAMeasurementRow() {
        assertEquals(listOf(HealthMetric.WEIGHT), HealthOverviewPolicy.measurementRows(listOf(item(HealthMetric.STEPS), item(HealthMetric.WEIGHT)), false).map { it.metric })
    }
    @Test fun abnormalFilterIncludesOnlyActuallyOutOfRangeValues() {
        val input = listOf(item(HealthMetric.GLUCOSE, HealthOverviewRangePosition.WITHIN), item(HealthMetric.LDL, HealthOverviewRangePosition.ABOVE),
            item(HealthMetric.HDL, HealthOverviewRangePosition.BELOW), item(HealthMetric.WEIGHT),
            item(HealthMetric.CHOLESTEROL, HealthOverviewRangePosition.NOT_COMPARABLE), item(HealthMetric.SLEEP_DURATION, recorded = false))
        assertEquals(listOf(HealthMetric.LDL, HealthMetric.HDL), HealthOverviewPolicy.measurementRows(input, true).map { it.metric })
    }
    @Test fun normalLatestValueIsNotAbnormalBecauseAnotherReadingUsedToBeHigh() {
        val normal = item(HealthMetric.GLUCOSE, HealthOverviewRangePosition.WITHIN)
        assertTrue(HealthOverviewPolicy.measurementRows(listOf(normal), true).isEmpty())
        assertEquals(listOf(normal), HealthOverviewPolicy.measurementRows(listOf(normal), false))
    }
    @Test fun previewRetainsEveryAbnormalRowEvenWhenThereAreMoreThanFive() {
        val items = HealthMetric.entries.filter { it != HealthMetric.STEPS }.take(8).map { item(it, HealthOverviewRangePosition.ABOVE) }
        assertEquals(8, HealthOverviewPolicy.measurementPreviewSize(HealthOverviewPolicy.measurementRows(items, true)))
    }
    @Test fun expandingContinuesTheStablePreviewWithoutDuplicatesOrReordering() {
        val input = listOf(item(HealthMetric.GLUCOSE, HealthOverviewRangePosition.ABOVE), item(HealthMetric.LDL, HealthOverviewRangePosition.WITHIN),
            item(HealthMetric.HDL), item(HealthMetric.TRIGLYCERIDES), item(HealthMetric.CHOLESTEROL), item(HealthMetric.WEIGHT),
            item(HealthMetric.SLEEP_DURATION, recorded = false))
        val ordered = HealthOverviewPolicy.measurementRows(input, false)
        val size = HealthOverviewPolicy.measurementPreviewSize(ordered)
        assertEquals(5, size)
        assertEquals(ordered, ordered.take(size) + ordered.drop(size))
        assertEquals(ordered.size, ordered.map { it.metric }.distinct().size)
        assertEquals(input, ordered)
    }
    @Test fun recordedNormalValuesPrecedeMissingPlaceholdersWithoutChangingTheirRelativeOrder() {
        val missing = item(HealthMetric.SLEEP_DURATION, recorded = false)
        val weight = item(HealthMetric.WEIGHT)
        val hdl = item(HealthMetric.HDL)
        assertEquals(listOf(weight, hdl, missing), HealthOverviewPolicy.measurementRows(listOf(missing, weight, hdl), false))
    }
}

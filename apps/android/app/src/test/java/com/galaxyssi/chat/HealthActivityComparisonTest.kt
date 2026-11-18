package com.galaxyssi.chat

import java.time.LocalDate
import org.junit.Assert.*
import org.junit.Test

class HealthActivityComparisonTest {
    private val first = LocalDate.of(2026, 11, 1)
    private val steps = HealthActivityKind.STEPS
    private fun day(offset: Long, value: Long, kind: HealthActivityKind = steps) = HealthActivityDay(kind, first.plusDays(offset), value)
    private fun compare(vararg rows: HealthActivityDay) = HealthActivityComparison.build(first, first.plusDays(6), rows.toList(), steps)
    @Test fun missingDaysAreNotFabricatedZeros() {
        val result = compare(day(1, 200))
        assertNull(result.current[0]); assertEquals(200L, result.current[1]); assertTrue(result.paired.isEmpty())
    }
    @Test fun explicitZeroIsPreserved() {
        val result = compare(day(0, 0), day(-7, 50))
        assertEquals(listOf(0), result.paired); assertEquals(0L, result.currentPaired); assertEquals(-100.0, result.changePercent!!, 0.001)
    }
    @Test fun onlyMatchingOffsetsContributeToChange() {
        val result = compare(day(0, 200), day(1, 10_000), day(-7, 100), day(-5, 50_000))
        assertEquals(200L, result.currentPaired); assertEquals(100L, result.previousPaired); assertEquals(100.0, result.changePercent!!, 0.001)
    }
    @Test fun zeroBaselineDoesNotProduceInfinity() { assertNull(compare(day(0, 1), day(-7, 0)).changePercent) }
    @Test fun activityKindsAreNeverMixed() { assertNull(compare(day(0, 90_000, HealthActivityKind.CYCLING)).current[0]) }
    @Test fun equalLengthPreviousPeriodDoesNotOverlapCurrent() {
        val result = compare(day(-1, 60), day(0, 100))
        assertEquals(60L, result.previous[6]); assertEquals(100L, result.current[0]); assertEquals(7, result.current.size)
    }
    @Test fun leapDayAndYearBoundaryUseCalendarDates() {
        val from = LocalDate.of(2024, 2, 28)
        val result = HealthActivityComparison.build(from, from.plusDays(2), listOf(HealthActivityDay(steps, LocalDate.of(2024, 2, 29), 42)), steps)
        assertEquals(listOf(null, 42L, null), result.current)
    }
    @Test fun customPeriodIsBoundedButNotHistoryRetention() {
        assertEquals(366, HealthActivityComparison.build(first, first.plusDays(365), emptyList(), steps).current.size)
        assertThrows(IllegalArgumentException::class.java) { HealthActivityComparison.build(first, first.plusDays(366), emptyList(), steps) }
    }
    @Test fun everyPresetIncludesTodayAndHasExactlyItsRequestedLength() {
        listOf(7, 30, 90).forEach { days ->
            val window = HealthActivityComparison.trailing(days, first)
            assertEquals(first, window.endInclusive)
            assertEquals(first.minusDays(days.toLong() - 1), window.start)
        }
    }
    @Test fun trailingRangeHandlesYearAndLeapBoundaries() {
        assertEquals(LocalDate.of(2025, 12, 26), HealthActivityComparison.trailing(7, LocalDate.of(2026, 1, 1)).start)
        assertEquals(LocalDate.of(2024, 2, 29), HealthActivityComparison.trailing(2, LocalDate.of(2024, 3, 1)).start)
    }
    @Test fun customRangeCanEndTodayButNeverInTheFuture() {
        assertTrue(HealthActivityComparison.validDates(first, first, first))
        assertTrue(HealthActivityComparison.validDates(first.minusDays(365), first, first))
        assertFalse(HealthActivityComparison.validDates(first, first.plusDays(1), first))
        assertFalse(HealthActivityComparison.validDates(first.minusDays(366), first, first))
        assertFalse(HealthActivityComparison.validDates(first, first.minusDays(1), first))
    }
    @Test fun liveTotalUpdatesOnlyItsCurrentDayWithoutChangingPreviousPeriod() {
        val before = compare(day(0, 100), day(-7, 80))
        val after = before.withDay(first, 130)
        assertEquals(130L, after.current.first()); assertEquals(100L, before.current.first())
        assertEquals(before.previous, after.previous)
    }
    @Test fun staleLiveTotalCannotDecreaseArchivedSteps() {
        assertEquals(100L, compare(day(0, 100)).withDay(first, 20).current.first())
    }
    @Test fun missingLiveValueStaysUnknownWhileObservedZeroIsKnown() {
        assertNull(compare().withDay(first, null).current.first())
        assertEquals(0L, compare().withDay(first, 0).current.first())
    }
    @Test fun liveDayOutsideSelectedHistoricalRangeIsIgnored() {
        val before = compare(day(0, 100))
        assertEquals(before, before.withDay(first.minusDays(1), 400))
        assertEquals(before, before.withDay(first.plusDays(7), 400))
    }
}

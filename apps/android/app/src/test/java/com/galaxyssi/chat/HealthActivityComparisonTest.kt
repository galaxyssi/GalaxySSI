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
        assertEquals(listOf(null, 200L, null, null, null, null, null), result.current)
    }
    @Test fun explicitZeroIsPreserved() {
        val result = compare(day(0, 0), day(-7, 50))
        assertEquals(0L, result.current.first())
    }
    @Test fun outOfRangeActivityDoesNotAffectPlottedValues() {
        val result = compare(day(-8, 80_000), day(-1, 50_000), day(0, 200), day(4, 40), day(7, 10_000))
        assertEquals(listOf(200L, null, null, null, 40L, null, null), result.current)
    }
    @Test fun activityKindsAreNeverMixed() { assertNull(compare(day(0, 90_000, HealthActivityKind.CYCLING)).current[0]) }
    @Test fun chartDateTicksIncludeBothEndpointsWithoutDuplicates() {
        val oneDay = HealthActivityComparison.build(first, first, emptyList(), steps)
        assertEquals(listOf(0), oneDay.dateTickIndices(7))
        val week = compare()
        assertEquals((0..6).toList(), week.dateTickIndices(7))
        assertEquals(listOf(0, 3, 6), week.dateTickIndices(3))
        listOf(30, 90, 366).forEach { days ->
            val last = first.plusDays(days.toLong() - 1)
            val period = HealthActivityComparison.build(first, last, emptyList(), steps)
            val ticks = period.dateTickIndices(5)
            assertEquals(5, ticks.distinct().size)
            assertEquals(first, period.dayAt(ticks.first()))
            assertEquals(last, period.dayAt(ticks.last()))
        }
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
    @Test fun liveTotalUpdatesTodayWithoutChangingEarlierDays() {
        val before = compare(day(0, 100), day(6, 80))
        val after = before.withDay(first.plusDays(6), 130)
        assertEquals(listOf(100L, null, null, null, null, null, 130L), after.current)
        assertEquals(80L, before.current.last())
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

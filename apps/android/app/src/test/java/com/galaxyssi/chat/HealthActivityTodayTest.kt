package com.galaxyssi.chat

import java.time.LocalDate
import java.time.ZoneId
import org.junit.Assert.*
import org.junit.Test

class HealthActivityTodayTest {
    private val today = LocalDate.of(2026, 11, 18)
    private val zone = ZoneId.of("Asia/Shanghai")
    private val wall = today.atTime(12, 0).atZone(zone).toInstant().toEpochMilli()
    @Test fun stepsUseTodaysObservedCounter() {
        assertEquals(1234L, healthActivityStepDay(HealthPhoneStepLedger(today, 1234, 80), today)?.total)
    }
    @Test fun yesterdayDoesNotMasqueradeAsZeroToday() {
        assertNull(healthActivityStepDay(HealthPhoneStepLedger(today.minusDays(1), 1234, 80), today))
    }
    @Test fun absentAndUnobservedCountersAreUnknown() {
        assertNull(healthActivityStepDay(null, today))
        assertNull(healthActivityStepDay(HealthPhoneStepLedger(today), today))
    }
    @Test fun realZeroAndPausedNonzeroStepsRemainVisible() {
        assertEquals(0L, healthActivityStepDay(HealthPhoneStepLedger(today, counter = 80), today)?.total)
        assertEquals(250L, healthActivityStepDay(HealthPhoneStepLedger(today, 250), today)?.total)
    }
    @Test fun absentOrDisabledCyclingIsNotInventedAsZero() {
        assertNull(healthActivityCyclingDay(null, wall, zone))
        assertNull(healthActivityCyclingDay(HealthCyclingState(), wall, zone))
    }
    @Test fun enabledCyclingCanHaveAnActualZeroDay() {
        assertEquals(0L, healthActivityCyclingDay(HealthCyclingState(enabled = true), wall, zone)?.total)
    }
    @Test fun settledCyclingRemainsVisibleAfterDisabling() {
        val state = HealthCyclingState(ledger = HealthCyclingLedger(1, 50, days = mapOf(today to 600_000)))
        assertEquals(600_000L, healthActivityCyclingDay(state, wall, zone)?.total)
    }
    @Test fun ongoingCyclingIncludesConfirmedDurationAndEarlierRidesExactlyOnce() {
        val start = HealthCyclingStart(100_000, wall - 1_800_000, evidence = 1_900_000)
        val state = HealthCyclingState(true, HealthCyclingLedger(1, 1_900_000, start, mapOf(today to 600_000)))
        assertEquals(2_400_000L, healthActivityCyclingDay(state, wall, zone)?.total)
        assertEquals(600_000L, state.ledger.days[today])
    }
    @Test fun cyclingDoesNotExtrapolateBeyondLastConfirmedEvidence() {
        val state = HealthCyclingState(true, HealthCyclingLedger(1, 1_900_000,
            HealthCyclingStart(100_000, wall - 1_800_000, evidence = 1_900_000)))
        assertEquals(1_800_000L, healthActivityCyclingDay(state, wall + 300_000, zone)?.total)
    }
    @Test fun crossingMidnightCountsOnlyTodaysPart() {
        val midnight = today.atStartOfDay(zone).toInstant().toEpochMilli()
        val state = HealthCyclingState(true, HealthCyclingLedger(1, 7_300_000,
            HealthCyclingStart(100_000, midnight - 3_600_000, evidence = 7_300_000)))
        assertEquals(3_600_000L, healthActivityCyclingDay(state, wall, zone)?.total)
    }
    @Test fun provisionalCyclingCanBeCorrectedWithoutPoisoningStoredHistory() {
        val state = HealthCyclingState(true, HealthCyclingLedger(1, 1_900_000,
            HealthCyclingStart(100_000, wall - 1_800_000, evidence = 1_900_000)))
        val base = HealthActivityComparison.build(today, today, emptyList(), HealthActivityKind.CYCLING)
        assertEquals(1_800_000L, base.withDay(today, healthActivityCyclingDay(state, wall, zone)?.total).current.single())
        val corrected = state.copy(ledger = state.ledger.copy(start = state.ledger.start!!.copy(gap = 1_000_000)))
        assertEquals(900_000L, base.withDay(today, healthActivityCyclingDay(corrected, wall, zone)?.total).current.single())
        assertTrue(state.ledger.days.isEmpty()); assertNull(base.current.single())
    }
}

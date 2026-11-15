package com.galaxyssi.chat

import java.time.LocalDate
import java.time.Period
import org.junit.Assert.*
import org.junit.Test

class HealthOverviewGuidanceTest {
    @Test fun sleepBandsMatchAgeAtMeasurement() {
        val birth = LocalDate.of(1965, 11, 15)
        val birthdays = mapOf(
            0 to HealthOverviewGuidance.SleepBand.MONTHS_0_3,
            1 to HealthOverviewGuidance.SleepBand.YEARS_1_2,
            3 to HealthOverviewGuidance.SleepBand.YEARS_3_5,
            6 to HealthOverviewGuidance.SleepBand.YEARS_6_12,
            13 to HealthOverviewGuidance.SleepBand.YEARS_13_17,
            18 to HealthOverviewGuidance.SleepBand.YEARS_18_60,
            60 to HealthOverviewGuidance.SleepBand.YEARS_18_60,
            61 to HealthOverviewGuidance.SleepBand.YEARS_61_64,
            64 to HealthOverviewGuidance.SleepBand.YEARS_61_64,
            65 to HealthOverviewGuidance.SleepBand.YEARS_65_PLUS,
        )
        birthdays.forEach { (years, expected) ->
            assertEquals(expected, HealthOverviewGuidance.sleep(HealthOverviewGuidance.ageOn(birth, birth.plusYears(years.toLong()))))
        }
        assertEquals(HealthOverviewGuidance.SleepBand.MONTHS_4_12, HealthOverviewGuidance.sleep(Period.ofMonths(4)))
        assertEquals(HealthOverviewGuidance.SleepBand.YEARS_18_60,
            HealthOverviewGuidance.sleep(HealthOverviewGuidance.ageOn(birth, birth.plusYears(61).minusDays(1))))
        assertNull(HealthOverviewGuidance.ageOn(birth, birth.minusDays(1)))
        assertEquals(HealthOverviewGuidance.SleepBand.ADULT_UNSPECIFIED, HealthOverviewGuidance.sleep(null))
        assertTrue(HealthOverviewGuidance.adultReference(null))
        assertFalse(HealthOverviewGuidance.adultReference(Period.ofYears(17)))
        assertTrue(HealthOverviewGuidance.adultReference(Period.ofYears(18)))
    }

    @Test fun stepProgressRequiresAnOptInGoalAndPermittedTodayCount() {
        val today = HealthOverviewFreshness.RECENT
        assertEquals(0.75, requireNotNull(HealthOverviewGuidance.stepProgress(8_000, 6_000, today, true)), 0.0)
        assertEquals(1.25, requireNotNull(HealthOverviewGuidance.stepProgress(8_000, 10_000, today, true)), 0.0)
        assertEquals(0.0, requireNotNull(HealthOverviewGuidance.stepProgress(8_000, 0, today, true)), 0.0)
        assertNull(HealthOverviewGuidance.stepProgress(8_000, 6_000, HealthOverviewFreshness.STALE, true))
        assertNull(HealthOverviewGuidance.stepProgress(8_000, 6_000, HealthOverviewFreshness.MISSING, true))
        assertNull(HealthOverviewGuidance.stepProgress(8_000, 6_000, today, false))
        assertNull(HealthOverviewGuidance.stepProgress(8_000, null, today, true))
        assertNull(HealthOverviewGuidance.stepProgress(null, 6_000, today, true))
        assertNull(HealthOverviewGuidance.stepProgress(0, 6_000, today, true))
    }
}

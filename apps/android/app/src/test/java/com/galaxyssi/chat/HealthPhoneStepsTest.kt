package com.galaxyssi.chat

import java.time.LocalDate
import org.junit.Assert.assertEquals
import org.junit.Test

class HealthPhoneStepsTest {
    private val today = LocalDate.of(2026, 11, 15)

    @Test fun countsHardwareDeltasWithoutCountingPreexistingSteps() {
        val first = HealthPhoneStepLedger(today).observe(9_054, 3, today, today)
        assertEquals(0L, first.total)
        val next = first.observe(9_069, 3, today, today)
        assertEquals(15L, next.total)
        assertEquals(next, next.observe(9_069, 3, today, today))
        assertEquals(20L, next.observe(9_074, 3, today, today).total)
    }

    @Test fun midnightResetsDisplayAndIgnoresLateEventsFromYesterday() {
        val before = HealthPhoneStepLedger(today, 8_000, 12_000, 3)
        val tomorrow = today.plusDays(1)
        assertEquals(0L, before.today(tomorrow).total)
        val late = before.observe(12_005, 3, tomorrow, today)
        assertEquals(0L, late.total)
        assertEquals(10L, late.observe(12_015, 3, tomorrow, tomorrow).total)
    }

    @Test fun rebootAndSensorResetPreserveTodaysAlreadyCountedSteps() {
        val before = HealthPhoneStepLedger(today, 800, 6900, 3)
        val reboot = before.observe(7000, 4, today, today)
        assertEquals(800L, reboot.total)
        val reset = reboot.observe(2, 4, today, today)
        assertEquals(800L, reset.total)
        assertEquals(805L, reset.observe(7, 4, today, today).total)
    }

    @Test fun explicitlyStoppingDiscardsTheBaselineSoPausedStepsAreNotAdded() {
        val paused = HealthPhoneStepLedger(today, 800, 6900, 3).copy(counter = null)
        val resumed = paused.observe(7010, 3, today, today)
        assertEquals(800L, resumed.total)
        assertEquals(805L, resumed.observe(7015, 3, today, today).total)
    }
}

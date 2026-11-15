package com.galaxyssi.chat

import java.time.Instant
import java.time.ZoneId
import com.galaxyssi.chat.HealthCyclingMotion.*
import org.junit.Assert.*
import org.junit.Test

class HealthCyclingLedgerTest {
    private val zone = ZoneId.of("Asia/Shanghai")
    private val wall = Instant.parse("2026-11-15T07:00:00Z").toEpochMilli()
    private val ledger = HealthCyclingLedger(4, -1)
    private val minute = 60_000L
    private fun HealthCyclingLedger.event(motion: HealthCyclingMotion, seconds: Long) =
        observe(HealthCyclingSignal(motion, seconds * 1000), seconds * 1000, wall + seconds * 1000, zone)

    @Test fun periodicSamplesRecoverMissingEnterAndLiveTotalCountsOnce() {
        val candidate = ledger.event(PEDALLING, 60)
        assertFalse(candidate.riding(60_000))
        val active = candidate.event(PEDALLING, 80).event(ENTER, 85).event(PEDALLING, 120)
        assertTrue(active.riding(120_000))
        assertEquals(minute, active.today(wall, zone))
        assertEquals(active, active.event(EXIT, 119))
        val closed = active.event(FOOT, 120 + 1L).event(FOOT, 145).event(FOOT, 171)
        assertFalse(closed.riding(171_000))
        assertEquals(61_000L, closed.today(wall, zone))
        assertEquals(closed, closed.event(FOOT, 171))
    }

    @Test fun ninetyMinuteRideKeepsRedLightsWalkingNoiseAndIntermittentTransitionExitsInOneRide() {
        var log = ledger.event(ENTER, 0)
        for (block in 0L until 9L) {
            val from = 600L * block
            for (offset in 20L..600L step 20L) {
                val motion = when (offset) {
                    200L -> EXIT
                    220L, 240L, 260L, 280L -> STILL
                    400L -> FOOT
                    else -> PEDALLING
                }
                log = log.event(motion, from + offset)
                assertTrue(log.riding((from + offset) * 1000))
                assertTrue(log.days.isEmpty())
            }
        }
        assertEquals(90 * minute, log.today(wall, zone))
        val done = log.event(FOOT, 5401).event(FOOT, 5426).event(FOOT, 5451)
        assertFalse(done.riding(5_451_000))
        assertEquals(90 * minute + 1000, done.today(wall, zone))
    }

    @Test fun aRideCrossingLocalMidnightSplitsAcrossTheCorrectDays() {
        val midnight = Instant.parse("2026-11-15T16:00:00Z").toEpochMilli()
        val started = ledger.observe(HealthCyclingSignal(ENTER, 100_000), 100_000, midnight - 40_000, zone)
        val ended = started.observe(HealthCyclingSignal(MOTOR, 200_000), 230_000, midnight + 90_000, zone)
            .observe(HealthCyclingSignal(MOTOR, 230_000), 230_000, midnight + 90_000, zone)
        assertEquals(40_000L, ended.today(midnight - 1, zone))
        assertEquals(60_000L, ended.today(midnight, zone))
    }

    @Test fun ignoresUncertainClassificationsAndSingleTransientNonCyclingSamples() {
        assertNull(cyclingMotion(64, 0, 68, 3))
        assertEquals(PEDALLING, cyclingMotion(73, 32, 9, 21))
        assertEquals(FOOT, cyclingMotion(3, 78, 21, 2))
        assertEquals(MOTOR, cyclingMotion(10, 30, 82, 4))
        assertEquals(STILL, cyclingMotion(6, 1, 5, 80))
        val active = ledger.event(ENTER, 1).event(MOTOR, 35).event(PEDALLING, 59).event(FOOT, 79).event(PEDALLING, 130)
        assertTrue(active.riding(130_000))
        assertEquals(129_000L, active.today(wall, zone))
        assertEquals(active, active.observe(HealthCyclingSignal(EXIT, 140_000), 131_000, wall + 131_000, zone))
    }

    @Test fun rebootKeepsPriorTotalsAndObservedPartOfAnOpenRideWithoutExtendingIt() {
        val day = HealthCyclingLedger.localDate(wall, zone)
        val active = ledger.copy(days = mapOf(day to 26 * minute)).event(ENTER, 1).event(PEDALLING, 61)
        val restored = active.onBoot(5, wall, zone)
        assertFalse(restored.riding(1_500))
        val strayExit = restored.event(EXIT, 2)
        assertEquals(27 * minute, strayExit.today(wall, zone))
    }

    @Test fun longStopEndsAtFirstConfirmedGapAndDoesNotAddTheStationaryTime() {
        val stopped = ledger.event(ENTER, 0).event(PEDALLING, 100).event(EXIT, 120).event(STILL, 125)
        assertTrue(stopped.riding(290_000))
        assertFalse(stopped.riding(305_000))
        val confirmed = stopped.event(STILL, 365)
        assertNull(confirmed.start)
        assertEquals(2 * minute, confirmed.today(wall, zone))
    }

    @Test fun missingExitAndMissingSamplesOnlyKeepObservedTime() {
        val opened = ledger.event(ENTER, 0).event(PEDALLING, 60)
        val stale = opened.event(EXIT, 1000)
        assertNull(stale.start)
        assertEquals(minute, stale.today(wall, zone))
    }

    @Test fun longGapCannotTurnTwoUnrelatedSamplesIntoOneRide() {
        val isolated = ledger.event(PEDALLING, 2).event(PEDALLING, 100)
        assertFalse(isolated.riding(100_000))
        assertEquals(0L, isolated.today(wall, zone))
        assertNull(isolated.event(STILL, 101).possibleStart)
    }
}

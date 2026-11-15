package com.galaxyssi.chat

import java.time.Instant
import java.time.ZoneId
import org.junit.Assert.*
import org.junit.Test

class HealthCyclingLedgerTest {
    private val zone = ZoneId.of("Asia/Shanghai")
    private val wall = Instant.parse("2026-11-15T07:00:00Z").toEpochMilli()
    private val ledger = HealthCyclingLedger(4, -1)

    @Test fun onlyCompletedRidesContributeAndRepeatedCallbacksAreIdempotent() {
        val active = ledger.transition(true, 60_000, 61_000, wall + 1000, zone)
        assertTrue(active.riding(62_000))
        assertEquals(0L, active.today(wall, zone))
        val duplicate = active.transition(true, 65_000, 65_500, wall + 5500, zone)
        assertEquals(active.start, duplicate.start)
        val closed = duplicate.transition(false, 180_000, 185_000, wall + 125_000, zone)
        assertFalse(closed.riding(185_000))
        assertEquals(120_000L, closed.today(wall, zone))
        assertEquals(closed, closed.transition(false, 180_000, 185_000, wall + 125_000, zone))
    }

    @Test fun multipleRideSegmentsDoNotCountTheGap() {
        fun event(log: HealthCyclingLedger, enter: Boolean, time: Long) =
            log.transition(enter, time, time, wall + time, zone)
        var log = event(ledger, true, 1_000)
        log = event(log, false, 61_000)
        log = event(log, true, 181_000)
        log = event(log, false, 241_000)
        assertEquals(120_000L, log.today(wall, zone))
    }

    @Test fun aRideCrossingLocalMidnightSplitsAcrossTheCorrectDays() {
        val midnight = Instant.parse("2026-11-15T16:00:00Z").toEpochMilli()
        val started = ledger.transition(true, 100_000, 100_000, midnight - 40_000, zone)
        val ended = started.transition(false, 200_000, 230_000, midnight + 90_000, zone)
        assertEquals(40_000L, ended.today(midnight - 1, zone))
        assertEquals(60_000L, ended.today(midnight, zone))
    }

    @Test fun ignoresShortTripsMissingStartsAndFutureOrStaleEvents() {
        val noStart = ledger.transition(false, 1000, 1000, wall, zone)
        assertEquals(0L, noStart.today(wall, zone))
        assertEquals(noStart, noStart.transition(true, 2000, 1500, wall, zone))
        assertEquals(noStart, noStart.transition(true, 999, 1500, wall, zone))
        val short = noStart.transition(true, 2_000, 2_000, wall, zone)
            .transition(false, 29_000, 29_000, wall + 27_000, zone)
        assertEquals(0L, short.today(wall, zone))
        assertFalse(short.riding(30_000))
    }

    @Test fun rebootKeepsConfirmedTotalWithoutClosingAnOldOngoingRide() {
        val day = HealthCyclingLedger.localDate(wall, zone)
        val active = ledger.copy(days = mapOf(day to 123_000)).transition(true, 1_000, 1_000, wall, zone)
        val restored = active.onBoot(5)
        assertFalse(restored.riding(1_500))
        val strayExit = restored.transition(false, 1500, 2000, wall, zone)
        assertEquals(123_000L, strayExit.today(wall, zone))
    }

    @Test fun missingExitDoesNotGenerateAnAllDayRide() {
        val opened = ledger.transition(true, 0, 0, wall, zone)
        val nextDay = 86_400_000L
        assertFalse(opened.riding(nextDay))
        val stale = opened.transition(false, nextDay, nextDay, wall + nextDay, zone)
        assertTrue(stale.days.isEmpty())
    }
}

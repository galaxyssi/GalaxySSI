package com.galaxyssi.chat

import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import org.junit.Assert.*
import org.junit.Test

class HealthReminderPolicyTest {
    private val utc = ZoneId.of("UTC")
    private val settings = HealthReminderSettings(enabled = true)
    private fun at(iso: String) = Instant.parse(iso).toEpochMilli()

    @Test fun firstUseDoesNotScheduleOrSendAnything() {
        val initial = HealthReminderSettings()
        assertNull(HealthReminderPolicy.due(initial, at("2026-11-04T09:00:00Z"), utc))
        assertNull(HealthReminderPolicy.nextDaily(initial, at("2026-11-04T09:00:00Z"), utc))
        assertFalse(initial.notifications)
        assertTrue(initial.hideOnLock)
    }
    @Test fun dueTimeProducesOneDateScopedPlanSnapshot() {
        assertNull(HealthReminderPolicy.due(settings, at("2026-11-04T08:29:59Z"), utc))
        val now = at("2026-11-04T08:30:00Z")
        val event = HealthReminderPolicy.due(settings.copy(target = HealthReminderTarget.MEASUREMENTS), now, utc)!!
        assertEquals(LocalDate.parse("2026-11-04"), event.day)
        assertEquals(now, event.dueAt)
        assertEquals(HealthReminderTarget.MEASUREMENTS, event.target)
        assertEquals(at("2026-11-05T08:30:00Z"), HealthReminderPolicy.nextDaily(settings, now, utc))
    }
    @Test fun optInAfterTodaysTimeDoesNotBackfill() {
        val start = at("2026-11-04T09:00:00Z")
        assertNull(HealthReminderPolicy.due(settings.copy(effectiveAt = start), start, utc))
        assertEquals(at("2026-11-05T08:30:00Z"), HealthReminderPolicy.nextDaily(settings.copy(effectiveAt = start), start, utc))
    }
    @Test fun pauseDoesNotReplayMissedDays() {
        val pause = at("2026-11-05T09:00:00Z")
        val config = settings.copy(pauseUntil = pause)
        assertNull(HealthReminderPolicy.due(config, at("2026-11-04T09:00:00Z"), utc))
        assertNull(HealthReminderPolicy.due(config, pause, utc))
        assertEquals(at("2026-11-06T08:30:00Z"), HealthReminderPolicy.nextDaily(config, at("2026-11-04T09:00:00Z"), utc))
    }
    @Test fun quietHoursCrossMidnightAndEndExclusively() {
        val end = at("2026-11-05T08:00:00Z")
        assertEquals(end, HealthReminderPolicy.quietUntil(settings, at("2026-11-04T23:00:00Z"), utc))
        assertEquals(end, HealthReminderPolicy.quietUntil(settings, at("2026-11-05T07:59:59Z"), utc))
        assertNull(HealthReminderPolicy.quietUntil(settings, end, utc))
        assertNull(HealthReminderPolicy.quietUntil(settings.copy(quiet = false), at("2026-11-04T23:00:00Z"), utc))
    }
    @Test fun quietHoursCanBeWithinSameDay() {
        val config = settings.copy(quietStart = 8 * 60, quietEnd = 10 * 60)
        assertEquals(at("2026-11-04T10:00:00Z"), HealthReminderPolicy.quietUntil(config, at("2026-11-04T08:00:00Z"), utc))
        assertNull(HealthReminderPolicy.quietUntil(config, at("2026-11-04T02:00:00Z"), utc))
    }
    @Test fun aSpringGapShiftsForwardAndFallOverlapUsesEarlierTime() {
        val zone = ZoneId.of("America/New_York")
        assertEquals(at("2026-03-08T07:30:00Z"), HealthReminderPolicy.at(LocalDate.parse("2026-03-08"), 150, zone))
        assertEquals(at("2026-11-01T05:30:00Z"), HealthReminderPolicy.at(LocalDate.parse("2026-11-01"), 90, zone))
    }
    @Test fun switchingZoneRecomputesTheWallTimeWithoutChangingPreference() {
        val now = at("2026-11-04T00:00:00Z")
        assertEquals(at("2026-11-04T08:30:00Z"), HealthReminderPolicy.nextDaily(settings, now, utc))
        assertEquals(at("2026-11-04T00:30:00Z"), HealthReminderPolicy.nextDaily(settings, now, ZoneId.of("Asia/Shanghai")))
        assertEquals(510, settings.minute)
    }
    @Test fun pauseAndQuietHoursUseTheLaterBoundaryInTheActiveZone() {
        val now = at("2026-11-04T23:00:00Z")
        val quietEnd = at("2026-11-05T08:00:00Z")
        val pauseEnd = quietEnd + HealthReminderPolicy.HOUR
        val longerPause = settings.copy(pauseUntil = pauseEnd)
        assertEquals(pauseEnd, HealthReminderPolicy.deliveryDeferredUntil(longerPause, now, utc))
        assertEquals(quietEnd, HealthReminderPolicy.deliveryDeferredUntil(settings.copy(pauseUntil = now + 1), now, utc))
        assertEquals(pauseEnd, HealthReminderPolicy.deliveryDeferredUntil(longerPause, now, ZoneId.of("Asia/Shanghai")))
        assertNull(HealthReminderPolicy.deliveryDeferredUntil(longerPause, pauseEnd, utc))
    }
    @Test fun deliveryWindowNeverTreatsFutureOrExpiredTimestampsAsDue() {
        val now = at("2026-11-04T23:00:00Z")
        assertFalse(HealthReminderPolicy.deliveryDue(now + 1, now))
        assertTrue(HealthReminderPolicy.deliveryDue(now, now))
        assertTrue(HealthReminderPolicy.deliveryDue(now - HealthReminderPolicy.DAY + 1, now))
        assertFalse(HealthReminderPolicy.deliveryDue(now - HealthReminderPolicy.DAY, now))
    }
}

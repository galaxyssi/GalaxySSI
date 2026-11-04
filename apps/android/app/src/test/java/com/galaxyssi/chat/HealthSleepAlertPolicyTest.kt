package com.galaxyssi.chat

import java.math.BigDecimal
import java.time.LocalDate
import java.time.ZoneId
import org.junit.Assert.*
import org.junit.Test

class HealthSleepAlertPolicyTest {
    private val metric = HealthMetric.SLEEP_DURATION
    private val zone = ZoneId.of("UTC")
    private val end = LocalDate.of(2025, 1, 14)
    private val now = 1_740_000_000_000L
    private val settings = HealthReminderSettings(sleepChanges = true)
    private fun report(recent: Int = 360, days: Int = 7, baselineDays: Int = 14, date: LocalDate = end): HealthWeeklySnapshot {
        val scope = HealthWeeklyScope(date, zone, setOf(metric))
        val current = HealthWeeklyStat(metric, days.toLong(), days.toLong(), days, days, BigDecimal(recent),
            List(7) { if (it < days) BigDecimal(recent) else null })
        val baseline = HealthWeeklyStat(metric, baselineDays.toLong(), baselineDays.toLong(), baselineDays, baselineDays, BigDecimal(420))
        return HealthWeeklySnapshot(scope, mapOf(metric to "metric-stamp"), now, listOf(current), HealthWeeklyComparison(current, baseline))
    }
    private fun evidence(recent: Int = 360, date: LocalDate = end) = requireNotNull(HealthSleepAlertPolicy.evidence(settings, report(recent, date = date)))
    private fun alert() = HealthSleepAlert("episode", now, evidence())

    @Test fun optInAndSufficientCoverageAreRequired() {
        assertNull(HealthSleepAlertPolicy.evidence(settings.copy(sleepChanges = false), report()))
        assertNull(HealthSleepAlertPolicy.evidence(settings, report(days = 4)))
        assertNull(HealthSleepAlertPolicy.evidence(settings, report(baselineDays = 9)))
        assertNotNull(HealthSleepAlertPolicy.evidence(settings, report(days = 5, baselineDays = 10)))
    }
    @Test fun onlyADecreaseAtOrAboveTheSelectedBoundaryTriggers() {
        assertNull(HealthSleepAlertPolicy.evidence(settings, report(recent = 376)))
        assertNull(HealthSleepAlertPolicy.evidence(settings, report(recent = 480)))
        assertEquals(BigDecimal(45), evidence(375).decrease)
        assertNull(HealthSleepAlertPolicy.evidence(settings.copy(sleepDecrease = 90), report()))
    }
    @Test fun mergedUpdatePreservesFirstEvidenceIdentityAndDelivery() {
        val alert = alert().copy(delivery = HealthReminderDelivery.POSTED)
        val next = HealthSleepAlertPolicy.changes(alert, now, evidence(350, end.plusDays(1)), now + HealthReminderPolicy.DAY, true).single()
        assertEquals(alert.id, next.id)
        assertEquals(alert.trigger, next.trigger)
        assertEquals(BigDecimal(70), next.evidence.decrease)
        assertEquals(HealthReminderDelivery.POSTED, next.delivery)
    }
    @Test fun aResolvedOrInsufficientWindowClosesTheActiveAlert() {
        val alert = alert()
        val closed = HealthSleepAlertPolicy.changes(alert, now, null, now + 1, true).single()
        assertEquals(HealthReminderState.STALE, closed.state)
        assertFalse(closed.open)
        assertFalse(closed.actionable)
        assertTrue(HealthSleepAlertPolicy.changes(null, now, evidence(), now + 2, true).isEmpty())
    }
    @Test fun unmergedOngoingChangeStillHonorsCooldownAndSameWindowDeduplication() {
        val alert = alert()
        val later = now + HealthSleepAlertPolicy.COOLDOWN
        assertTrue(HealthSleepAlertPolicy.changes(alert, now, evidence(), later, false).isEmpty())
        val repeat = HealthSleepAlertPolicy.changes(alert, now, evidence(date = end.plusDays(7)), later, false)
        assertEquals(2, repeat.size)
        assertEquals(HealthReminderState.STALE, repeat[0].state)
        assertNotEquals(alert.id, repeat[1].id)
        assertTrue(repeat[1].actionable)
    }
    @Test fun completedEpisodeDoesNotReopenWhenMerged() {
        val complete = alert().copy(state = HealthReminderState.COMPLETE, handledAt = now + 3)
        val changed = HealthSleepAlertPolicy.changes(complete, now, evidence(350, end.plusDays(7)), now + HealthSleepAlertPolicy.COOLDOWN, true).single()
        assertEquals(HealthReminderState.COMPLETE, changed.state)
        assertEquals(complete.handledAt, changed.handledAt)
        assertFalse(changed.actionable)
    }
}

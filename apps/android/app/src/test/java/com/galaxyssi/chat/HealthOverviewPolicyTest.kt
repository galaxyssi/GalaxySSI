package com.galaxyssi.chat

import java.math.BigDecimal
import java.time.LocalDate
import java.time.ZoneId
import org.junit.Assert.*
import org.junit.Test

class HealthOverviewPolicyTest {
    private val zone = ZoneId.of("America/New_York")
    private val today = LocalDate.of(2025, 11, 3)
    private val now = time(today, 12)
    private fun time(date: LocalDate, hour: Int) = date.atTime(hour, 0).atZone(zone).toInstant().toEpochMilli()
    private fun alert(end: LocalDate = today.minusDays(1), version: String = "current") = HealthSleepAlert("alert", now - 20,
        HealthSleepAlertEvidence(end, zone.id, version, now - 20, 1, 45, BigDecimal(360), BigDecimal(420), List(7) { BigDecimal(360) }, 14, 7))

    @Test fun sevenDayFreshnessUsesLocalCalendarIncludingDst() {
        val metric = HealthMetric.BLOOD_PRESSURE
        assertEquals(HealthOverviewFreshness.RECENT, HealthOverviewPolicy.freshness(metric, time(today.minusDays(6), 0), now, zone))
        assertEquals(HealthOverviewFreshness.STALE, HealthOverviewPolicy.freshness(metric, time(today.minusDays(7), 23), now, zone))
    }
    @Test fun stepsAreCurrentOnlyOnTheSameLocalDate() {
        val metric = HealthMetric.STEPS
        assertEquals(HealthOverviewFreshness.STALE, HealthOverviewPolicy.freshness(metric, time(today.minusDays(1), 23), now, zone))
        assertEquals(HealthOverviewFreshness.RECENT, HealthOverviewPolicy.freshness(metric, time(today, 0), now, zone))
        assertEquals(HealthOverviewFreshness.MISSING, HealthOverviewPolicy.freshness(metric, now + 1, now, zone))
        assertEquals(HealthOverviewFreshness.MISSING, HealthOverviewPolicy.freshness(metric, null, now, zone))
    }
    @Test fun attentionIsBoundToEvidenceVersionDateAndCurrentPreferences() {
        val scope = HealthWeeklyScope(today.minusDays(1), zone, setOf(HealthMetric.SLEEP_DURATION))
        val settings = HealthReminderSettings(sleepChanges = true)
        assertNotNull(HealthOverviewPolicy.activeChange(alert(), settings, scope, "current"))
        assertNull(HealthOverviewPolicy.activeChange(alert(version = "old"), settings, scope, "current"))
        assertNull(HealthOverviewPolicy.activeChange(alert(today.minusDays(2)), settings, scope, "current"))
        assertNull(HealthOverviewPolicy.activeChange(alert(), settings.copy(sleepDecrease = 60), scope, "current"))
        assertNull(HealthOverviewPolicy.activeChange(alert(), settings.copy(sleepChanges = false), scope, "current"))
        assertNull(HealthOverviewPolicy.activeChange(alert().copy(state = HealthReminderState.SNOOZED), settings, scope, "current"))
    }
    @Test fun orderingHonorsPreferenceThenFreshnessWithoutAClinicalScore() {
        val change = HealthOverviewAttention.Change(alert())
        val a = HealthOverviewAttention.Review("a", HealthOverviewReviewKind.OCR, now)
        val b = HealthOverviewAttention.Review("b", HealthOverviewReviewKind.TABLE, now - 5)
        val input = listOf(b, change, a)
        assertEquals(listOf(change, a, b), HealthOverviewPolicy.sort(input, HealthOverviewOrder.CHANGES_FIRST))
        assertEquals(listOf(a, b, change), HealthOverviewPolicy.sort(input, HealthOverviewOrder.REVIEW_FIRST))
        assertEquals(listOf(a, b, change), HealthOverviewPolicy.sort(input, HealthOverviewOrder.MOST_RECENT))
    }
    @Test fun sourceAttentionRequiresASelectedUnresolvedUnacknowledgedIncident() {
        val first = HealthSyncIncident("11111111-1111-4111-8111-111111111111", HealthConnectScope.STEPS,
            HealthSyncOutcome.NETWORK, now, now - 1000)
        val others = listOf(first.copy(acknowledgedAt = now), first.copy(resolvedAt = now),
            first.copy(scope = HealthConnectScope.SLEEP))
        assertEquals(listOf(HealthOverviewAttention.Connection(first)),
            HealthOverviewPolicy.activeConnections(listOf(first) + others, setOf(HealthConnectScope.STEPS)))
        assertTrue(HealthOverviewPolicy.activeConnections(listOf(first), emptySet()).isEmpty())
    }
    @Test fun sourceIssuesUseTheSamePreferenceAndStableTimeOrderingWithoutBecomingHealthChanges() {
        val change = HealthOverviewAttention.Change(alert())
        val review = HealthOverviewAttention.Review("review", HealthOverviewReviewKind.OCR, now - 5)
        val source = HealthOverviewAttention.Connection(HealthSyncIncident("22222222-2222-4222-8222-222222222222",
            HealthConnectScope.STEPS, HealthSyncOutcome.TIMEOUT, now, 0))
        val items = listOf(source, review, change)
        assertEquals(listOf(change, source, review), HealthOverviewPolicy.sort(items, HealthOverviewOrder.CHANGES_FIRST))
        assertEquals(listOf(review, source, change), HealthOverviewPolicy.sort(items, HealthOverviewOrder.REVIEW_FIRST))
        assertEquals(listOf(source, review, change), HealthOverviewPolicy.sort(items, HealthOverviewOrder.MOST_RECENT))
    }
}

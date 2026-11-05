package com.galaxyssi.chat

import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

internal enum class HealthOverviewFreshness { RECENT, STALE, MISSING }
internal enum class HealthOverviewOrder { CHANGES_FIRST, REVIEW_FIRST, MOST_RECENT }
internal enum class HealthOverviewReviewKind { OCR, TABLE }

internal sealed interface HealthOverviewAttention {
    val time: Long
    data class Change(val alert: HealthSleepAlert) : HealthOverviewAttention { override val time get() = alert.evidence.computedAt }
    data class Review(val jobId: String, val kind: HealthOverviewReviewKind, override val time: Long, val name: String = "") : HealthOverviewAttention
    data class Connection(val incident: HealthSyncIncident) : HealthOverviewAttention { override val time get() = incident.failedAt }
}

internal object HealthOverviewPolicy {
    val keyMetrics = listOf(HealthMetric.BLOOD_PRESSURE, HealthMetric.SLEEP_DURATION, HealthMetric.RESTING_HEART_RATE, HealthMetric.STEPS)
    val metrics = keyMetrics + listOf(HealthMetric.TEMPERATURE, HealthMetric.OXYGEN_SATURATION)
    const val REVIEW_LIMIT = 30

    fun freshness(metric: HealthMetric, time: Long?, now: Long, zone: ZoneId): HealthOverviewFreshness {
        if (time == null || time > now) return HealthOverviewFreshness.MISSING
        val today = localDay(now, zone)
        val first = if (metric == HealthMetric.STEPS) today else today.minusDays(6)
        return if (localDay(time, zone) < first) HealthOverviewFreshness.STALE else HealthOverviewFreshness.RECENT
    }
    fun localDay(time: Long, zone: ZoneId): LocalDate = Instant.ofEpochMilli(time).atZone(zone).toLocalDate()
    fun activeChange(alert: HealthSleepAlert?, settings: HealthReminderSettings, scope: HealthWeeklyScope, token: String): HealthSleepAlert? =
        alert?.takeIf {
            settings.sleepChanges && it.open && it.state == HealthReminderState.PENDING &&
                it.evidence.end == scope.end && it.evidence.zone == scope.zone.id &&
                it.evidence.rule == HealthSleepAlertPolicy.VERSION && it.evidence.threshold == settings.sleepDecrease && it.evidence.metricVersion == token
        }

    fun sort(items: List<HealthOverviewAttention>, order: HealthOverviewOrder): List<HealthOverviewAttention> {
        fun priority(item: HealthOverviewAttention) = when (order) {
            HealthOverviewOrder.MOST_RECENT -> 0
            HealthOverviewOrder.CHANGES_FIRST -> if (item is HealthOverviewAttention.Change) 0 else 1
            HealthOverviewOrder.REVIEW_FIRST -> if (item is HealthOverviewAttention.Review) 0 else 1
        }
        return items.sortedWith(compareBy<HealthOverviewAttention> { priority(it) }.thenByDescending { it.time }
            .thenBy { when (it) {
                is HealthOverviewAttention.Change -> it.alert.id
                is HealthOverviewAttention.Review -> it.jobId
                is HealthOverviewAttention.Connection -> it.incident.id
            } })
    }

    fun activeConnections(incidents: List<HealthSyncIncident>, selected: Set<HealthConnectScope>): List<HealthOverviewAttention.Connection> =
        incidents.filter { it.scope in selected && !it.handled }.map { HealthOverviewAttention.Connection(it) }
}

package com.galaxyssi.chat

import java.math.BigDecimal
import java.time.LocalDate
import java.time.ZoneId
import java.util.UUID
import org.json.JSONArray
import org.json.JSONObject

internal data class HealthSleepAlertEvidence(
    val end: LocalDate, val zone: String, val metricVersion: String, val computedAt: Long, val rule: Int, val threshold: Int,
    val recent: BigDecimal, val baseline: BigDecimal, val daily: List<BigDecimal?>, val baselineDays: Int, val records: Long
) {
    val recentDays get() = daily.count { it != null }
    val decrease get() = baseline - recent
    val first: LocalDate get() = end.minusDays(6)
    val baselineFirst: LocalDate get() = first.minusDays(14)
    val baselineLast: LocalDate get() = first.minusDays(1)
    init {
        ZoneId.of(zone)
        require(daily.size == 7 && recentDays >= 5 && baselineDays in 10..14 && records >= recentDays)
        require(rule > 0 && computedAt >= 0 && threshold > 0 && decrease >= BigDecimal(threshold))
    }
    fun json() = JSONObject().put("end", end.toString()).put("zone", zone).put("version", metricVersion).put("computed", computedAt)
        .put("rule", rule).put("threshold", threshold).put("recent", recent.toPlainString()).put("baseline", baseline.toPlainString())
        .put("days", JSONArray(daily.map { it?.toPlainString() ?: JSONObject.NULL })).put("baselineDays", baselineDays).put("records", records)

    companion object {
        fun from(j: JSONObject) = HealthSleepAlertEvidence(LocalDate.parse(j.getString("end")), j.getString("zone"), j.getString("version"),
            j.getLong("computed"), j.getInt("rule"), j.getInt("threshold"), j.getString("recent").toBigDecimal(),
            j.getString("baseline").toBigDecimal(), j.getJSONArray("days").let { a -> (0 until a.length()).map { i ->
                if (a.isNull(i)) null else a.getString(i).toBigDecimal()
            } }, j.getInt("baselineDays"), j.getLong("records"))
    }
}

internal data class HealthSleepAlert(
    val id: String, val openedAt: Long, val trigger: HealthSleepAlertEvidence, val evidence: HealthSleepAlertEvidence = trigger,
    val state: HealthReminderState = HealthReminderState.PENDING, val delivery: HealthReminderDelivery = HealthReminderDelivery.WAITING,
    val endedAt: Long = 0, val resumeAt: Long = 0, val revision: String = UUID.randomUUID().toString(), val handledAt: Long = 0
) {
    val open get() = endedAt == 0L
    val actionable get() = open && state in listOf(HealthReminderState.PENDING, HealthReminderState.SNOOZED)
    fun json() = JSONObject().put("id", id).put("opened", openedAt).put("trigger", trigger.json()).put("evidence", evidence.json())
        .put("state", state.name).put("delivery", delivery.name).put("ended", endedAt).put("resume", resumeAt).put("revision", revision)
        .put("handled", handledAt)

    companion object {
        fun from(j: JSONObject) = HealthSleepAlert(j.getString("id"), j.getLong("opened"), HealthSleepAlertEvidence.from(j.getJSONObject("trigger")),
            HealthSleepAlertEvidence.from(j.getJSONObject("evidence")), HealthReminderState.valueOf(j.getString("state")),
            HealthReminderDelivery.valueOf(j.getString("delivery")), j.getLong("ended"), j.getLong("resume"), j.getString("revision"), j.getLong("handled"))
    }
}

internal object HealthSleepAlertPolicy {
    const val VERSION = 1
    const val COOLDOWN = 7 * HealthReminderPolicy.DAY
    val thresholds = listOf(30, 45, 60, 90)

    fun evidence(settings: HealthReminderSettings, snapshot: HealthWeeklySnapshot): HealthSleepAlertEvidence? {
        if (!settings.sleepChanges) return null
        val sleep = snapshot.sleep ?: return null
        val delta = sleep.deltaMinutes ?: return null
        if (delta.negate() < BigDecimal(settings.sleepDecrease)) return null
        return HealthSleepAlertEvidence(snapshot.scope.end, snapshot.scope.zone.id, snapshot.versions.getValue(HealthMetric.SLEEP_DURATION),
            snapshot.calculatedAt, VERSION, settings.sleepDecrease, requireNotNull(sleep.current.mean), requireNotNull(sleep.baseline.mean),
            sleep.current.dailyMinutes, sleep.baseline.validDays, sleep.current.exactRecords)
    }

    fun changes(active: HealthSleepAlert?, lastOpened: Long?, evidence: HealthSleepAlertEvidence?, now: Long, merge: Boolean): List<HealthSleepAlert> {
        fun close(alert: HealthSleepAlert) = alert.copy(endedAt = now, resumeAt = 0, revision = UUID.randomUUID().toString(),
            state = if (alert.state == HealthReminderState.COMPLETE) alert.state else HealthReminderState.STALE)
        if (evidence == null) return listOfNotNull(active?.let(::close))
        val cooling = lastOpened != null && now - lastOpened < COOLDOWN
        if (active != null && (merge || cooling || active.evidence.end == evidence.end)) {
            return if (active.evidence == evidence) emptyList() else listOf(active.copy(evidence = evidence, revision = UUID.randomUUID().toString()))
        }
        if (cooling) return emptyList()
        val next = HealthSleepAlert(UUID.randomUUID().toString(), now, evidence)
        return listOfNotNull(active?.let(::close), next)
    }
}

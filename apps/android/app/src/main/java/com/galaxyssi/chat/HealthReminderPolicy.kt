package com.galaxyssi.chat

import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.UUID
import org.json.JSONObject

internal enum class HealthReminderTarget { SLEEP, MEASUREMENTS }
internal enum class HealthReminderState { PENDING, SNOOZED, COMPLETE, DISABLED, STALE }
internal enum class HealthReminderDelivery { WAITING, POSTED, IN_APP_ONLY }
internal enum class HealthReminderFilter { PENDING, HANDLED, ALL }
internal enum class HealthReminderAction { COMPLETE, SNOOZE, DISABLE }

internal data class HealthReminderSettings(
    val enabled: Boolean = false,
    val minute: Int = 510,
    val target: HealthReminderTarget = HealthReminderTarget.SLEEP,
    val notifications: Boolean = false,
    val quiet: Boolean = true,
    val quietStart: Int = 1320,
    val quietEnd: Int = 480,
    val hideOnLock: Boolean = true,
    val pauseUntil: Long = 0,
    val effectiveAt: Long = 0,
    val revision: String = "",
    val sleepChanges: Boolean = false,
    val sleepDecrease: Int = 45,
    val mergeSleepChanges: Boolean = true,
    val reportReviews: Boolean = true
) {
    init {
        require(minute in 0..1439 && quietStart in 0..1439 && quietEnd in 0..1439 && quietStart != quietEnd)
        require(pauseUntil >= 0 && effectiveAt >= 0)
        require(sleepDecrease in HealthSleepAlertPolicy.thresholds)
    }

    fun json() = JSONObject().put("enabled", enabled).put("minute", minute).put("target", target.name)
        .put("notifications", notifications).put("quiet", quiet).put("quietStart", quietStart).put("quietEnd", quietEnd)
        .put("hideOnLock", hideOnLock).put("pauseUntil", pauseUntil).put("effectiveAt", effectiveAt).put("revision", revision)
        .put("sleepChanges", sleepChanges).put("sleepDecrease", sleepDecrease).put("mergeSleepChanges", mergeSleepChanges)
        .put("reportReviews", reportReviews)

    companion object {
        fun from(j: JSONObject) = HealthReminderSettings(j.getBoolean("enabled"), j.getInt("minute"),
            HealthReminderTarget.valueOf(j.getString("target")), j.getBoolean("notifications"), j.getBoolean("quiet"),
            j.getInt("quietStart"), j.getInt("quietEnd"), j.getBoolean("hideOnLock"), j.getLong("pauseUntil"),
            j.getLong("effectiveAt"), j.getString("revision"), j.optBoolean("sleepChanges", false),
            j.optInt("sleepDecrease", 45), j.optBoolean("mergeSleepChanges", true), j.optBoolean("reportReviews", true))
    }
}

internal data class HealthReminderOccurrence(
    val day: LocalDate, val dueAt: Long, val createdAt: Long, val zone: String,
    val target: HealthReminderTarget, val state: HealthReminderState = HealthReminderState.PENDING,
    val delivery: HealthReminderDelivery = HealthReminderDelivery.WAITING,
    val resumeAt: Long = 0, val handledAt: Long = 0, val revision: String = UUID.randomUUID().toString()
) {
    fun json() = JSONObject().put("day", day.toString()).put("dueAt", dueAt).put("createdAt", createdAt).put("zone", zone)
        .put("target", target.name).put("state", state.name).put("delivery", delivery.name).put("resumeAt", resumeAt)
        .put("handledAt", handledAt).put("revision", revision)

    companion object {
        fun from(j: JSONObject) = HealthReminderOccurrence(LocalDate.parse(j.getString("day")), j.getLong("dueAt"),
            j.getLong("createdAt"), j.getString("zone"), HealthReminderTarget.valueOf(j.getString("target")),
            HealthReminderState.valueOf(j.getString("state")), HealthReminderDelivery.valueOf(j.getString("delivery")),
            j.getLong("resumeAt"), j.getLong("handledAt"), j.getString("revision"))
    }
}

internal object HealthReminderPolicy {
    const val HOUR = 3_600_000L
    const val DAY = 24 * HOUR

    fun day(now: Long, zone: ZoneId): LocalDate = Instant.ofEpochMilli(now).atZone(zone).toLocalDate()

    // A gap shifts forward, and an overlap uses the earlier occurrence once.
    fun at(day: LocalDate, minute: Int, zone: ZoneId): Long =
        day.atTime(minute / 60, minute % 60).atZone(zone).toInstant().toEpochMilli()

    fun due(settings: HealthReminderSettings, now: Long, zone: ZoneId): HealthReminderOccurrence? {
        if (!settings.enabled || now < settings.pauseUntil) return null
        val day = day(now, zone)
        val due = at(day, settings.minute, zone)
        return if (due in maxOf(settings.effectiveAt, settings.pauseUntil)..now)
            HealthReminderOccurrence(day, due, now, zone.id, settings.target) else null
    }

    fun nextDaily(settings: HealthReminderSettings, now: Long, zone: ZoneId): Long? {
        if (!settings.enabled) return null
        val earliest = maxOf(now + 1, settings.pauseUntil, settings.effectiveAt)
        val day = day(earliest, zone)
        val today = at(day, settings.minute, zone)
        return if (today >= earliest) today else at(day.plusDays(1), settings.minute, zone)
    }

    fun quietUntil(settings: HealthReminderSettings, now: Long, zone: ZoneId): Long? {
        if (!settings.quiet) return null
        val today = day(now, zone)
        val crossesMidnight = settings.quietEnd < settings.quietStart
        for (day in listOf(today.minusDays(1), today)) {
            val start = at(day, settings.quietStart, zone)
            val end = at(if (crossesMidnight) day.plusDays(1) else day, settings.quietEnd, zone)
            if (now >= start && now < end) return end
        }
        return null
    }

    fun deliveryDeferredUntil(settings: HealthReminderSettings, now: Long, zone: ZoneId): Long? =
        maxOf(settings.pauseUntil, quietUntil(settings, now, zone) ?: 0L).takeIf { it > now }

    fun deliveryDue(at: Long, now: Long) = at > now - DAY && at <= now
}

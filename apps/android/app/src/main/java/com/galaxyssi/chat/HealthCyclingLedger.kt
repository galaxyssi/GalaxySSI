package com.galaxyssi.chat

import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

internal data class HealthCyclingStart(val elapsed: Long, val wall: Long)

internal data class HealthCyclingLedger(
    val boot: Int,
    val lastEvent: Long,
    val start: HealthCyclingStart? = null,
    val days: Map<LocalDate, Long> = emptyMap(),
) {
    fun onBoot(boot: Int): HealthCyclingLedger =
        if (this.boot == boot) this else copy(boot = boot, start = null, lastEvent = -1)

    fun transition(enter: Boolean, eventElapsed: Long, elapsed: Long, wall: Long, zone: ZoneId): HealthCyclingLedger {
        if (eventElapsed <= lastEvent || eventElapsed < 0 || eventElapsed > elapsed) return this
        val eventWall = wall - (elapsed - eventElapsed)
        val today = localDate(wall, zone)
        val recent = days.filterKeys { it in today.minusDays(DAYS - 1)..today }
        if (enter) {
            val active = start?.takeIf { eventElapsed - it.elapsed <= MAX_SESSION_MS }
            return copy(lastEvent = eventElapsed, start = active ?: HealthCyclingStart(eventElapsed, eventWall), days = recent)
        }
        val finished = copy(lastEvent = eventElapsed, start = null, days = recent)
        val began = start ?: return finished
        val duration = eventElapsed - began.elapsed
        if (duration !in MIN_SESSION_MS..MAX_SESSION_MS) return finished
        val totals = recent.toMutableMap()
        for (offset in 0L until DAYS) {
            val date = today.minusDays(offset)
            val part = intersection(date, zone, began.wall, began.wall + duration)
            if (part > 0) {
                val max = date.plusDays(1).atStartOfDay(zone).toInstant().toEpochMilli() - date.atStartOfDay(zone).toInstant().toEpochMilli()
                totals[date] = ((totals[date] ?: 0) + part).coerceAtMost(max)
            }
        }
        return finished.copy(days = totals)
    }

    fun today(wall: Long, zone: ZoneId): Long = days[localDate(wall, zone)] ?: 0
    fun riding(elapsed: Long): Boolean = start?.let { elapsed - it.elapsed in 0..MAX_SESSION_MS } == true

    companion object {
        const val DAYS = 8L
        private const val MIN_SESSION_MS = 30_000L
        private const val MAX_SESSION_MS = 12 * 60 * 60 * 1000L
        fun localDate(wall: Long, zone: ZoneId): LocalDate = Instant.ofEpochMilli(wall).atZone(zone).toLocalDate()

        private fun intersection(day: LocalDate, zone: ZoneId, start: Long, end: Long): Long {
            val from = day.atStartOfDay(zone).toInstant().toEpochMilli()
            val until = day.plusDays(1).atStartOfDay(zone).toInstant().toEpochMilli()
            return (minOf(end, until) - maxOf(start, from)).coerceAtLeast(0)
        }
    }
}

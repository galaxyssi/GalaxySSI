package com.galaxyssi.chat

import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

internal enum class HealthCyclingMotion { ENTER, PEDALLING, EXIT, STILL, FOOT, MOTOR }
internal data class HealthCyclingSignal(val motion: HealthCyclingMotion, val elapsed: Long)
internal fun cyclingMotion(bike: Int, foot: Int, motor: Int, still: Int): HealthCyclingMotion? = when {
    bike >= 60 && bike >= maxOf(foot, motor, still) + 10 -> HealthCyclingMotion.PEDALLING
    motor >= 75 && motor >= maxOf(bike, foot, still) + 10 -> HealthCyclingMotion.MOTOR
    foot >= 70 && foot >= maxOf(bike, motor, still) + 10 -> HealthCyclingMotion.FOOT
    still >= 75 && still >= maxOf(bike, foot, motor) + 10 -> HealthCyclingMotion.STILL
    else -> null
}
internal data class HealthCyclingDeparture(val motion: HealthCyclingMotion, val from: Long, val last: Long)
internal data class HealthCyclingStart(
    val elapsed: Long, val wall: Long, val evidence: Long = elapsed, val gap: Long? = null,
    val stillSince: Long? = null, val departure: HealthCyclingDeparture? = null,
) {
    val confirmedThrough get() = gap ?: evidence
}

internal data class HealthCyclingLedger(
    val boot: Int,
    val lastEvent: Long,
    val start: HealthCyclingStart? = null,
    val days: Map<LocalDate, Long> = emptyMap(),
    val possibleStart: Long? = null,
) {
    fun onBoot(boot: Int, wall: Long, zone: ZoneId, resetUnknownBoot: Boolean = false): HealthCyclingLedger =
        if (this.boot == boot && !(boot < 0 && resetUnknownBoot)) this
        else settle(wall, zone).copy(boot = boot, lastEvent = -1)

    fun settle(wall: Long, zone: ZoneId): HealthCyclingLedger =
        start?.let { finish(it, it.confirmedThrough, wall, zone) } ?: copy(possibleStart = null)

    fun observe(signal: HealthCyclingSignal, now: Long, wall: Long, zone: ZoneId): HealthCyclingLedger {
        val time = signal.elapsed
        if (time <= lastEvent || time < 0 || time > now) return this
        val bike = signal.motion == HealthCyclingMotion.ENTER || signal.motion == HealthCyclingMotion.PEDALLING
        val base = start?.takeIf { !isRiding(it, time) }?.let { finish(it, it.confirmedThrough, wall, zone) } ?: this
        val ride = base.start
        if (ride == null) {
            val candidate = base.possibleStart?.takeIf { time - it in 1..SAMPLE_CONTINUITY_MS }
            if (!bike && base.possibleStart == null) return base
            if (!bike) return base.copy(lastEvent = time, possibleStart = null)
            if (signal.motion == HealthCyclingMotion.ENTER || (candidate != null && time - candidate >= START_CONFIRM_MS)) {
                val began = candidate ?: time
                return base.copy(lastEvent = time, possibleStart = null,
                    start = HealthCyclingStart(began, wall - (now - began), evidence = time))
            }
            return base.copy(lastEvent = time, possibleStart = candidate ?: time)
        }
        val updated = when (signal.motion) {
            HealthCyclingMotion.ENTER, HealthCyclingMotion.PEDALLING ->
                ride.copy(evidence = time, gap = null, stillSince = null, departure = null)
            HealthCyclingMotion.EXIT ->
                ride.copy(gap = ride.gap ?: time)
            HealthCyclingMotion.STILL ->
                ride.copy(gap = ride.gap ?: time, stillSince = ride.stillSince ?: time, departure = null)
            HealthCyclingMotion.FOOT, HealthCyclingMotion.MOTOR -> {
                val departure = ride.departure?.takeIf {
                    it.motion == signal.motion && time - it.last <= SAMPLE_CONTINUITY_MS
                }?.copy(last = time) ?: HealthCyclingDeparture(signal.motion, time, time)
                val required = if (signal.motion == HealthCyclingMotion.MOTOR) MOTOR_CONFIRM_MS else FOOT_CONFIRM_MS
                if (time - departure.from >= required) {
                    return base.finish(ride, minOf(ride.confirmedThrough, departure.from), wall, zone).copy(lastEvent = time)
                }
                ride.copy(gap = ride.gap ?: time, stillSince = null, departure = departure)
            }
        }
        return base.copy(lastEvent = time, start = updated)
    }

    private fun finish(ride: HealthCyclingStart, until: Long, wall: Long, zone: ZoneId): HealthCyclingLedger {
        val today = localDate(wall, zone)
        val totals = days.filterKeys { it in today.minusDays(DAYS - 1)..today }.toMutableMap()
        val end = ride.wall + (until - ride.elapsed).coerceIn(0, MAX_SESSION_MS)
        for (offset in 0L until DAYS) {
            val date = today.minusDays(offset)
            val part = intersection(date, zone, ride.wall, end)
            if (part > 0) {
                totals[date] = ((totals[date] ?: 0) + part).coerceAtMost(dayLimit(date, zone))
            }
        }
        return copy(start = null, possibleStart = null, days = totals)
    }

    fun today(wall: Long, zone: ZoneId): Long {
        val date = localDate(wall, zone)
        val active = start?.let {
            intersection(date, zone, it.wall, it.wall + (it.confirmedThrough - it.elapsed).coerceIn(0, MAX_SESSION_MS))
        } ?: 0
        return ((days[date] ?: 0) + active).coerceAtMost(dayLimit(date, zone))
    }

    fun riding(elapsed: Long): Boolean = start?.let { isRiding(it, elapsed) } == true

    private fun isRiding(ride: HealthCyclingStart, elapsed: Long) =
        elapsed - ride.elapsed in 0..MAX_SESSION_MS && elapsed - ride.confirmedThrough < MAX_SILENCE_MS &&
            (ride.stillSince?.let { elapsed - it < STILL_GRACE_MS } != false)

    companion object {
        const val DAYS = 8L
        private const val MAX_SESSION_MS = 12 * 60 * 60 * 1000L
        private const val START_CONFIRM_MS = 15_000L
        private const val SAMPLE_CONTINUITY_MS = 90_000L
        private const val MOTOR_CONFIRM_MS = 25_000L
        private const val FOOT_CONFIRM_MS = 50_000L
        private const val STILL_GRACE_MS = 3 * 60_000L
        private const val MAX_SILENCE_MS = 8 * 60_000L
        fun localDate(wall: Long, zone: ZoneId): LocalDate = Instant.ofEpochMilli(wall).atZone(zone).toLocalDate()

        private fun dayLimit(day: LocalDate, zone: ZoneId) =
            day.plusDays(1).atStartOfDay(zone).toInstant().toEpochMilli() - day.atStartOfDay(zone).toInstant().toEpochMilli()

        private fun intersection(day: LocalDate, zone: ZoneId, start: Long, end: Long): Long {
            val from = day.atStartOfDay(zone).toInstant().toEpochMilli()
            val until = day.plusDays(1).atStartOfDay(zone).toInstant().toEpochMilli()
            return (minOf(end, until) - maxOf(start, from)).coerceAtLeast(0)
        }
    }
}

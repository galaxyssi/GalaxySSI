package com.galaxyssi.chat

import java.time.LocalDate
import java.time.temporal.ChronoUnit

internal enum class HealthActivityKind { STEPS, CYCLING }
internal data class HealthActivityDay(val kind: HealthActivityKind, val day: LocalDate, val total: Long)
internal data class HealthActivityComparison(val first: LocalDate, val last: LocalDate,
    val current: List<Long?>) {
    fun dayAt(index: Int): LocalDate = first.plusDays(index.toLong())

    fun dateTickIndices(limit: Int): List<Int> {
        val count = limit.coerceIn(2, 7).coerceAtMost(current.size)
        if (count <= 1) return current.indices.toList()
        return List(count) { it * current.lastIndex / (count - 1) }
    }

    fun withDay(day: LocalDate, total: Long?): HealthActivityComparison {
        if (total == null || day !in first..last) return this
        require(total >= 0)
        val index = ChronoUnit.DAYS.between(first, day).toInt()
        return copy(current = current.toMutableList().apply { this[index] = maxOf(this[index] ?: 0, total) })
    }
    companion object {
        fun trailing(days: Int, today: LocalDate): ClosedRange<LocalDate> {
            require(days in 1..366)
            return today.minusDays(days.toLong() - 1)..today
        }
        fun validDates(first: LocalDate, last: LocalDate, today: LocalDate) =
            ChronoUnit.DAYS.between(first, last) in 0..365 && !last.isAfter(today)
        fun build(first: LocalDate, last: LocalDate, rows: List<HealthActivityDay>, kind: HealthActivityKind): HealthActivityComparison {
            val size = (ChronoUnit.DAYS.between(first, last) + 1).toInt()
            require(size in 1..366)
            val totals = rows.filter { it.kind == kind }.associate { it.day to it.total }
            return HealthActivityComparison(first, last, List(size) { totals[first.plusDays(it.toLong())] })
        }
    }
}

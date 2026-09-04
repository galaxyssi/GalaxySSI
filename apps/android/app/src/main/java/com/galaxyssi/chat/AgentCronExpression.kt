package com.galaxyssi.chat

import java.time.Instant
import java.time.ZoneId
import java.time.ZonedDateTime

class AgentCronExpression private constructor(
    val expression: String,
    private val minute: Field,
    private val hour: Field,
    private val day: Field,
    private val month: Field,
    private val weekday: Field
) {
    fun matches(value: ZonedDateTime): Boolean {
        val cronWeekday = value.dayOfWeek.value % 7
        val dayMatches = value.dayOfMonth in day.values
        val weekdayMatches = cronWeekday in weekday.values
        val calendarMatches = when {
            day.wildcard && weekday.wildcard -> true
            day.wildcard -> weekdayMatches
            weekday.wildcard -> dayMatches
            else -> dayMatches || weekdayMatches
        }
        return value.minute in minute.values &&
            value.hour in hour.values &&
            value.monthValue in month.values &&
            calendarMatches
    }

    fun nextAfter(timestampMillis: Long, zoneId: String): Long {
        val zone = parseZone(zoneId)
        var candidate = Instant.ofEpochMilli(timestampMillis)
            .atZone(zone)
            .withSecond(0)
            .withNano(0)
            .plusMinutes(1)
        repeat(MAX_SCAN_MINUTES) {
            if (matches(candidate)) return candidate.toInstant().toEpochMilli()
            candidate = candidate.plusMinutes(1)
        }
        throw IllegalArgumentException("Cron has no occurrence within six years")
    }

    fun previousAtOrBefore(timestampMillis: Long, zoneId: String): Long {
        val zone = parseZone(zoneId)
        var candidate = Instant.ofEpochMilli(timestampMillis)
            .atZone(zone)
            .withSecond(0)
            .withNano(0)
        repeat(MAX_SCAN_MINUTES) {
            if (matches(candidate)) return candidate.toInstant().toEpochMilli()
            candidate = candidate.minusMinutes(1)
        }
        throw IllegalArgumentException("Cron has no occurrence within six years")
    }

    private data class Field(
        val values: Set<Int>,
        val wildcard: Boolean
    )

    companion object {
        private const val MAX_SCAN_MINUTES = 3_200_000
        private val MONTH_NAMES = mapOf(
            "jan" to 1,
            "feb" to 2,
            "mar" to 3,
            "apr" to 4,
            "may" to 5,
            "jun" to 6,
            "jul" to 7,
            "aug" to 8,
            "sep" to 9,
            "oct" to 10,
            "nov" to 11,
            "dec" to 12
        )
        private val WEEKDAY_NAMES = mapOf(
            "sun" to 0,
            "mon" to 1,
            "tue" to 2,
            "wed" to 3,
            "thu" to 4,
            "fri" to 5,
            "sat" to 6
        )

        fun parse(expression: String): AgentCronExpression {
            val parts = expression.trim().split(Regex("\\s+"))
            require(parts.size == 5) { "Cron requires five fields" }
            return AgentCronExpression(
                expression = parts.joinToString(" "),
                minute = parseField(parts[0], 0, 59),
                hour = parseField(parts[1], 0, 23),
                day = parseField(parts[2], 1, 31),
                month = parseField(parts[3], 1, 12, MONTH_NAMES),
                weekday = parseField(parts[4], 0, 6, WEEKDAY_NAMES, sundayAlias = true)
            )
        }

        fun parseZone(zoneId: String): ZoneId = runCatching {
            ZoneId.of(zoneId.ifBlank { "UTC" })
        }.getOrElse {
            throw IllegalArgumentException("Unknown time zone: $zoneId")
        }

        private fun parseField(
            text: String,
            minimum: Int,
            maximum: Int,
            aliases: Map<String, Int> = emptyMap(),
            sundayAlias: Boolean = false
        ): Field {
            val clean = text.trim().lowercase()
            require(clean.isNotBlank()) { "Cron field is blank" }
            val output = linkedSetOf<Int>()
            clean.split(",").forEach { clause ->
                val parts = clause.split("/", limit = 2)
                val base = parts[0]
                val step = if (parts.size == 2) {
                    parts[1].toIntOrNull() ?: throw IllegalArgumentException("Invalid cron step")
                } else {
                    1
                }
                require(step > 0) { "Cron step must be positive" }
                val range = when {
                    base == "*" -> minimum..maximum
                    "-" in base -> {
                        val edges = base.split("-", limit = 2)
                        numeric(edges[0], aliases, sundayAlias)..numeric(edges[1], aliases, sundayAlias)
                    }
                    else -> {
                        val value = numeric(base, aliases, sundayAlias)
                        value..value
                    }
                }
                require(range.first in minimum..maximum && range.last in minimum..maximum) {
                    "Cron value is outside $minimum..$maximum"
                }
                require(range.last >= range.first) { "Cron ranges cannot wrap" }
                range.step(step).forEach(output::add)
            }
            require(output.isNotEmpty()) { "Cron field has no values" }
            return Field(output, clean == "*")
        }

        private fun numeric(
            raw: String,
            aliases: Map<String, Int>,
            sundayAlias: Boolean
        ): Int {
            val clean = raw.trim().lowercase()
            aliases[clean]?.let { return it }
            val value = clean.toIntOrNull() ?: throw IllegalArgumentException("Invalid cron token: $raw")
            return if (sundayAlias && value == 7) 0 else value
        }
    }
}

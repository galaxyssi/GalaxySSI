package com.galaxyssi.chat

import java.math.BigDecimal
import java.math.MathContext
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.ChronoUnit

internal val healthWeeklyMetrics = listOf(HealthMetric.SLEEP_DURATION, HealthMetric.STEPS, HealthMetric.RESTING_HEART_RATE,
    HealthMetric.BLOOD_PRESSURE, HealthMetric.TEMPERATURE, HealthMetric.OXYGEN_SATURATION)

internal data class HealthWeeklyScope(val end: LocalDate, val zone: ZoneId,
    val metrics: Set<HealthMetric> = healthWeeklyMetrics.toSet(), val records: Boolean = false, val comparison: Boolean = true) {
    val first: LocalDate get() = end.minusDays(6)
    val from: Long get() = first.atStartOfDay(zone).toInstant().toEpochMilli()
    val until: Long get() = end.plusDays(1).atStartOfDay(zone).toInstant().toEpochMilli()
    val baselineFirst: LocalDate get() = first.minusDays(14)
    val baselineLast: LocalDate get() = first.minusDays(1)
    val hasBaseline get() = comparison && HealthMetric.SLEEP_DURATION in metrics
    init { require(metrics.isNotEmpty() && metrics.all { it in healthWeeklyMetrics } && !baselineFirst.isBefore(LocalDate.of(1970, 1, 2))) }
    fun recordScope() = HealthRecordExportScope(metrics, from, until, zone.id)
    fun baselineScope() = HealthRecordExportScope(setOf(HealthMetric.SLEEP_DURATION), baselineFirst.atStartOfDay(zone).toInstant().toEpochMilli(), from, zone.id)
    companion object { const val MAX_PDF_RECORDS = 500L }
}

internal data class HealthWeeklyStat(val metric: HealthMetric, val records: Long, val exactRecords: Long,
    val recordedDays: Int, val validDays: Int, val mean: BigDecimal?)
internal data class HealthWeeklyComparison(val current: HealthWeeklyStat, val baseline: HealthWeeklyStat) {
    val deltaMinutes: BigDecimal? get() = if (current.validDays >= 5 && baseline.validDays >= 10)
        current.mean?.let { currentMean -> baseline.mean?.let { currentMean - it } } else null
}
internal data class HealthWeeklySnapshot(val scope: HealthWeeklyScope, val versions: Map<HealthMetric, String>,
    val calculatedAt: Long, val stats: List<HealthWeeklyStat>, val sleep: HealthWeeklyComparison?) {
    val recordCount get() = stats.sumOf { it.records }
    val stamp get() = HealthWeeklyStamp(scope, versions, calculatedAt)
    companion object { const val METHOD_VERSION = 1 }
}
internal data class HealthWeeklyStamp(val scope: HealthWeeklyScope, val versions: Map<HealthMetric, String>, val calculatedAt: Long) {
    init { require(versions.keys == scope.metrics && calculatedAt >= 0) }
}
internal data class HealthWeeklyRecord(val id: String, val revision: Int, val metric: HealthMetric, val time: Long,
    val values: Map<String, String>, val unit: String, val source: String) {
    companion object {
        fun from(record: HealthObservation) = with(record.draft) {
            HealthWeeklyRecord(record.id, record.revision, metric, measuredAt, values.toMap(), unit, record.source)
        }
    }
}
internal data class HealthWeeklyRecords(val records: List<HealthWeeklyRecord>, val next: HealthPageCursor?)

internal class HealthWeeklyAccumulator(private val metric: HealthMetric, private val first: LocalDate, private val days: Int, private val zone: ZoneId) {
    private class Day {
        var recorded = false
        var valid = false
        var count = 0L
        var sum = BigDecimal.ZERO
        var latestAt = Long.MIN_VALUE
        var latestId = ""
        var latestSteps = BigDecimal.ZERO
    }
    private val bins = Array(days) { Day() }
    private var records = 0L
    private var exactRecords = 0L

    fun add(record: HealthObservation) {
        check(record.profileId == "self" && record.draft.metric == metric)
        val draft = record.draft
        val date = Instant.ofEpochMilli(draft.measuredAt).atZone(zone).toLocalDate()
        val index = ChronoUnit.DAYS.between(first, date)
        check(index in 0 until days.toLong())
        val bin = bins[index.toInt()]
        records++; bin.recorded = true
        val values = metric.requiredFields.map { HealthResult.parse(draft.values[it].orEmpty(), metric.form)?.exactNumber ?: return }
        val value = values.first()
        val normalized = when (metric) {
            HealthMetric.SLEEP_DURATION -> when (draft.unit) { "h" -> value * BigDecimal(60); "min" -> value; else -> return }
            HealthMetric.TEMPERATURE -> when (draft.unit) {
                "\u00b0C" -> value
                "\u00b0F" -> ((value - BigDecimal(32)) * BigDecimal(5)).divide(BigDecimal(9), MathContext.DECIMAL64)
                else -> return
            }
            else -> if (draft.unit in metric.units) value else return
        }
        exactRecords++; bin.valid = true
        when (metric) {
            HealthMetric.BLOOD_PRESSURE -> Unit
            HealthMetric.STEPS -> {
                if (draft.measuredAt > bin.latestAt || draft.measuredAt == bin.latestAt && record.id > bin.latestId) {
                    bin.latestAt = draft.measuredAt; bin.latestId = record.id; bin.latestSteps = normalized
                }
            }
            else -> { bin.count++; bin.sum += normalized }
        }
    }

    fun finish(): HealthWeeklyStat {
        val valid = bins.filter { it.valid }
        val mean = if (metric == HealthMetric.BLOOD_PRESSURE || valid.isEmpty()) null else {
            val total = valid.fold(BigDecimal.ZERO) { sum, day ->
                sum + if (metric == HealthMetric.STEPS) day.latestSteps else day.sum.divide(BigDecimal.valueOf(day.count), MathContext.DECIMAL64)
            }
            total.divide(BigDecimal(valid.size), MathContext.DECIMAL64).stripTrailingZeros()
        }
        return HealthWeeklyStat(metric, records, exactRecords, bins.count { it.recorded }, valid.size, mean)
    }
}

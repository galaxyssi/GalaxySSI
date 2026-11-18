package com.galaxyssi.chat

import java.math.BigDecimal
import java.time.DayOfWeek
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.TemporalAdjusters

internal enum class HealthMeasurementPeriodKind { WEEK, MONTH }
internal data class HealthMeasurementPeriod(val kind: HealthMeasurementPeriodKind, val first: LocalDate) {
    init { require(first >= if (kind == HealthMeasurementPeriodKind.WEEK) LocalDate.of(1969, 12, 29) else LocalDate.of(1970, 1, 1)); require(first == start(kind, first)) }
    val end get() = if (kind == HealthMeasurementPeriodKind.WEEK) first.plusWeeks(1) else first.plusMonths(1)
    val key get() = "${kind.name}:$first"
    fun previous() = of(kind, first.minusDays(1))
    fun from(zone: ZoneId) = first.atStartOfDay(zone).toInstant().toEpochMilli().coerceAtLeast(0)
    fun until(zone: ZoneId) = end.atStartOfDay(zone).toInstant().toEpochMilli()
    companion object {
        private fun start(kind: HealthMeasurementPeriodKind, date: LocalDate) = if (kind == HealthMeasurementPeriodKind.WEEK)
            date.with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY)) else date.withDayOfMonth(1)
        fun of(kind: HealthMeasurementPeriodKind, date: LocalDate) = HealthMeasurementPeriod(kind, start(kind, date))
        fun parse(value: String?): HealthMeasurementPeriod? = runCatching {
            val parts = requireNotNull(value).split(':'); require(parts.size == 2)
            HealthMeasurementPeriod(HealthMeasurementPeriodKind.valueOf(parts[0]), LocalDate.parse(parts[1]))
        }.getOrNull()
    }
}
internal data class HealthMeasurementSeriesKey(val metric: HealthMetric, val unit: String, val condition: String, val side: String) {
    companion object { fun of(record: HealthObservation) = record.draft.let { HealthMeasurementSeriesKey(it.metric, it.unit, it.condition, it.side) } }
}
internal data class HealthMeasurementSeries(val key: HealthMeasurementSeriesKey, val latest: HealthObservation, val count: Long, val outsideCount: Long)
internal data class HealthMeasurementPeriodSummary(val period: HealthMeasurementPeriod?, val series: List<HealthMeasurementSeries>)
internal data class HealthMeasurementPeriodPage(val periods: List<HealthMeasurementPeriod>, val next: LocalDate?)

/** Sampling dates define calendar cohorts. Upload time, file count and import-job identity never participate. */
internal object HealthMeasurementPeriods {
    val metrics = HealthMetric.entries.toSet() - HealthMetric.STEPS
    class Builder(private val compareRanges: Boolean = true) {
        private val rows = linkedMapOf<HealthMeasurementSeriesKey, HealthMeasurementSeries>()
        fun add(record: HealthObservation) {
            if (record.profileId != "self" || record.draft.metric !in metrics) return
            val key = HealthMeasurementSeriesKey.of(record); val old = rows[key]
            val latest = if (old == null || compareValuesBy(record, old.latest, { it.draft.measuredAt }, { it.id }) > 0) record else old.latest
            rows[key] = HealthMeasurementSeries(key, latest, (old?.count ?: 0) + 1,
                (old?.outsideCount ?: 0) + if (compareRanges && HealthOverviewRangePolicy.report(record)?.outside == true) 1 else 0)
        }
        fun finish(period: HealthMeasurementPeriod?) = HealthMeasurementPeriodSummary(period, rows.values.toList())
    }
    fun load(records: HealthRecordStore, period: HealthMeasurementPeriod?, now: Long, zone: ZoneId,
        check: () -> Unit = {}): HealthMeasurementPeriodSummary {
        val versions = records.metricVersions(metrics)
        val builder = Builder()
        if (period == null) metrics.forEach { check(); records.overviewLatestSelf(it, now)?.let(builder::add) }
        else {
            var cursor: HealthPageCursor? = null
            do {
                check()
                val page = records.measurementPage(period.from(zone), minOf(now + 1, period.until(zone)), cursor, check = check)
                page.records.forEach(builder::add); cursor = page.next
            } while (cursor != null)
        }
        if (versions != records.metricVersions(metrics)) throw HealthWeeklyChanged()
        return builder.finish(period)
    }
    fun page(records: HealthRecordStore, kind: HealthMeasurementPeriodKind, now: Long, zone: ZoneId,
        before: LocalDate? = null, check: () -> Unit = {}): HealthMeasurementPeriodPage {
        var until = minOf(now + 1, before?.atStartOfDay(zone)?.toInstant()?.toEpochMilli() ?: Long.MAX_VALUE)
        val periods = arrayListOf<HealthMeasurementPeriod>()
        while (until > 0 && periods.size < 13) {
            check()
            val record = records.measurementPage(0, until, limit = 1, check = check).records.firstOrNull() ?: break
            val period = HealthMeasurementPeriod.of(kind, Instant.ofEpochMilli(record.draft.measuredAt).atZone(zone).toLocalDate())
            periods += period; until = period.from(zone)
        }
        val visible = periods.take(12)
        return HealthMeasurementPeriodPage(visible, if (periods.size > 12) visible.last().first else null)
    }
    fun delta(a: HealthObservation?, b: HealthObservation?, field: String): BigDecimal? {
        if (a == null || b == null || a.profileId != "self" || b.profileId != "self") return null
        val x = a.draft; val y = b.draft
        if (HealthMeasurementSeriesKey.of(a) != HealthMeasurementSeriesKey.of(b) || x.condition == "unspecified" || x.unit.isBlank() ||
            a.source != b.source || a.platformOrigin != b.platformOrigin || a.bluetoothGroup != b.bluetoothGroup ||
            x.evidence?.originalId != y.evidence?.originalId) return null
        val av = HealthResult.parse(x.values[field].orEmpty(), x.metric.form)?.exactNumber ?: return null
        val bv = HealthResult.parse(y.values[field].orEmpty(), y.metric.form)?.exactNumber ?: return null
        return bv - av
    }
}

package com.galaxyssi.chat

import java.math.BigDecimal
import java.math.MathContext
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.ChronoUnit
import java.util.BitSet

internal enum class HealthTrendAggregation { MEAN, MINIMUM, MAXIMUM }
internal const val HEALTH_CONNECT_AGGREGATE_ORIGIN = "health_connect.aggregate"
private val healthTrendPlatformOrigin = Regex("[a-zA-Z0-9_.]{1,255}")
internal fun validHealthTrendPlatformOrigin(origin: String) = healthTrendPlatformOrigin.matches(origin)

internal data class HealthTrendSource(val originalId: String = "", val manualOnly: Boolean = false,
    val bluetoothGroup: String = "", val platformOrigin: String = "") {
    init {
        require(originalId.isBlank() || java.util.UUID.fromString(originalId).toString() == originalId)
        require(bluetoothGroup.isEmpty() || isHealthBluetoothGroup(bluetoothGroup))
        require(platformOrigin.isEmpty() || validHealthTrendPlatformOrigin(platformOrigin))
        require(listOf(originalId.isNotBlank(), manualOnly, bluetoothGroup.isNotEmpty(), platformOrigin.isNotEmpty()).count { it } <= 1)
    }
    fun accepts(record: HealthObservation) = (!manualOnly || record.source == "manual") &&
        (originalId.isBlank() || record.draft.evidence?.originalId == originalId) &&
        (bluetoothGroup.isEmpty() || record.source == "bluetooth" && record.bluetoothGroup == bluetoothGroup) &&
        (platformOrigin.isEmpty() || record.source == "health_connect" && record.platformOrigin == platformOrigin)
}
internal data class HealthTrendSpec(val metric: HealthMetric, val first: LocalDate, val last: LocalDate,
    val zone: ZoneId, val unit: String, val aggregation: HealthTrendAggregation = HealthTrendAggregation.MEAN,
    val source: HealthTrendSource = HealthTrendSource()) {
    val days = ChronoUnit.DAYS.between(first, last) + 1
    val from = first.atStartOfDay(zone).toInstant().toEpochMilli()
    val until = last.plusDays(1).atStartOfDay(zone).toInstant().toEpochMilli()
    val bucketDays = ((days + MAX_POINTS - 1) / MAX_POINTS).toInt()
    init { require(!first.isBefore(LocalDate.of(1970, 1, 1)) && !last.isBefore(first)); require(days in 1..Int.MAX_VALUE.toLong()); require(unit in metric.selectableUnits) }
    fun matches(record: HealthObservation, numericOnly: Boolean = false): Boolean = record.profileId == "self" && record.draft.metric == metric && source.accepts(record) &&
        record.draft.measuredAt >= from && record.draft.measuredAt < until && (!numericOnly || record.draft.unit == unit && exact(record) != null)
    fun exact(record: HealthObservation): Map<String, BigDecimal>? {
        val values = metric.requiredFields.associateWith { field -> HealthResult.parse(record.draft.values[field].orEmpty(), metric.form)?.exactNumber }
        return if (values.values.any { it == null }) null else values.mapValues { requireNotNull(it.value) }
    }
    companion object { const val MAX_POINTS = 120 }
}
internal data class HealthTrendPoint(val bucket: Int, val field: String, val first: LocalDate, val last: LocalDate,
    val value: BigDecimal, val count: Long, val recordId: String, val gapBefore: Boolean, val recordRevision: Int = 0)
internal data class HealthTrendSummary(val spec: HealthTrendSpec, val total: Long, val eligible: Long, val nonNumeric: Long,
    val otherUnits: Long, val reportedDays: Int, val numericDays: Int, val points: List<HealthTrendPoint>, val latest: HealthObservation?,
    val version: String = "", val calculatedAt: Long = System.currentTimeMillis()) {
    val missingDays get() = spec.days - reportedDays
}

/** Bounded plot bins and calendar-day coverage; no raw history or fabricated zero observations are retained. */
internal class HealthTrendBuilder(private val spec: HealthTrendSpec, private val bucketDays: Int = spec.bucketDays) {
    init { require(bucketDays > 0 && bucketDays.toLong() <= spec.days) }
    private data class Ref(val id: String, val time: Long, val revision: Int)
    private class Cell {
        var count = 0L; var sum = BigDecimal.ZERO; var min: BigDecimal? = null; var max: BigDecimal? = null
        var minRef: Ref? = null; var maxRef: Ref? = null; var firstDay = Int.MAX_VALUE; var lastDay = -1
        fun add(value: BigDecimal, record: HealthObservation, day: Int) {
            val ref = Ref(record.id, record.draft.measuredAt, record.revision)
            fun newer(old: Ref?) = old == null || ref.time > old.time || ref.time == old.time && ref.id > old.id
            if (min == null || value < min || value.compareTo(min) == 0 && newer(minRef)) { min = value; minRef = ref }
            if (max == null || value > max || value.compareTo(max) == 0 && newer(maxRef)) { max = value; maxRef = ref }
            count++; sum += value; firstDay = minOf(firstDay, day); lastDay = maxOf(lastDay, day)
        }
    }
    private val bins = linkedMapOf<Pair<Int, String>, Cell>()
    private val recorded = BitSet(); private val numeric = BitSet()
    private var total = 0L; private var eligible = 0L; private var nonNumeric = 0L; private var otherUnits = 0L
    private var latest: HealthObservation? = null
    fun add(record: HealthObservation) {
        require(record.draft.metric == spec.metric) { "Trend metric mismatch" }
        if (!spec.matches(record)) return
        total++
        if (record.draft.unit != spec.unit) { otherUnits++; return }
        if (latest == null || record.draft.measuredAt > latest!!.draft.measuredAt || record.draft.measuredAt == latest!!.draft.measuredAt && record.id > latest!!.id) latest = record
        val day = ChronoUnit.DAYS.between(spec.first, Instant.ofEpochMilli(record.draft.measuredAt).atZone(spec.zone).toLocalDate()).toInt()
        recorded.set(day)
        val values = spec.exact(record) ?: run { nonNumeric++; return }
        eligible++; numeric.set(day)
        values.forEach { (field, value) -> bins.getOrPut(day / bucketDays to field) { Cell() }.add(value, record, day) }
    }
    fun finish(): HealthTrendSummary {
        val points = spec.metric.requiredFields.flatMap { field ->
            var previous: Pair<Int, Cell>? = null
            bins.filterKeys { it.second == field }.entries.sortedBy { it.key.first }.map { (key, cell) ->
                val index = key.first
                val gap = previous?.let { (previousIndex, previousCell) ->
                    index != previousIndex + 1 || numeric.nextClearBit(previousCell.lastDay) < cell.firstDay
                } ?: true
                previous = index to cell
                val start = spec.first.plusDays(index.toLong() * bucketDays)
                val end = minOf(spec.last, start.plusDays(bucketDays.toLong() - 1))
                val value = when (spec.aggregation) {
                    HealthTrendAggregation.MEAN -> cell.sum.divide(BigDecimal.valueOf(cell.count), MathContext.DECIMAL64)
                    HealthTrendAggregation.MINIMUM -> requireNotNull(cell.min)
                    HealthTrendAggregation.MAXIMUM -> requireNotNull(cell.max)
                }
                val ref = when (spec.aggregation) {
                    HealthTrendAggregation.MEAN -> if (cell.count == 1L) cell.minRef else null
                    HealthTrendAggregation.MINIMUM -> cell.minRef
                    HealthTrendAggregation.MAXIMUM -> cell.maxRef
                }
                HealthTrendPoint(index, field, start, end, value.stripTrailingZeros(), cell.count, ref?.id.orEmpty(), gap, ref?.revision ?: 0)
            }
        }
        return HealthTrendSummary(spec, total, eligible, nonNumeric, otherUnits, recorded.cardinality(), numeric.cardinality(), points, latest)
    }
}

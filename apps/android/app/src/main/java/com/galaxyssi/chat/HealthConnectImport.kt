package com.galaxyssi.chat

import android.content.Context
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.BloodPressureRecord
import androidx.health.connect.client.records.HeartRateRecord
import androidx.health.connect.client.records.Record
import androidx.health.connect.client.records.RestingHeartRateRecord
import androidx.health.connect.client.records.SleepSessionRecord
import androidx.health.connect.client.records.StepsRecord
import androidx.health.connect.client.records.WeightRecord
import androidx.health.connect.client.request.AggregateRequest
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.time.TimeRangeFilter
import java.time.Duration
import java.time.Instant
import java.time.ZoneId
import kotlin.reflect.KClass
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive

internal enum class HealthConnectScope(val metric: HealthMetric, type: KClass<out Record>) {
    SLEEP(HealthMetric.SLEEP_DURATION, SleepSessionRecord::class),
    STEPS(HealthMetric.STEPS, StepsRecord::class),
    HEART_RATE(HealthMetric.HEART_RATE, HeartRateRecord::class),
    RESTING_HEART_RATE(HealthMetric.RESTING_HEART_RATE, RestingHeartRateRecord::class),
    BLOOD_PRESSURE(HealthMetric.BLOOD_PRESSURE, BloodPressureRecord::class),
    WEIGHT(HealthMetric.WEIGHT, WeightRecord::class);

    val permission = HealthPermission.getReadPermission(type)
}

internal data class HealthConnectWindow(val hours: Int, val end: Instant, val zone: ZoneId) {
    init { require(hours in RANGES) }
    val start: Instant get() = end.minus(Duration.ofHours(hours.toLong()))
    companion object { val RANGES = listOf(1, 6, 24, 72, 168) }
}

internal data class HealthConnectMeasurement(val id: String, val origin: String, val draft: HealthDraft) {
    init {
        require(id.length in 1..512 && id.none(Char::isISOControl))
        require(origin.matches(Regex("[a-zA-Z0-9_.]{1,255}")))
        require(draft.recordId.isBlank() && draft.revision == 0 && draft.evidence == null)
        require(HealthConnectScope.entries.any { it.metric == draft.metric })
    }
}

internal class HealthConnectTooManyRecords : IllegalStateException()
internal class HealthConnectPermissionChanged : SecurityException()
internal interface HealthConnectReader {
    suspend fun granted(): Set<String>
    suspend fun read(scope: HealthConnectScope, window: HealthConnectWindow, emit: (HealthConnectMeasurement) -> Unit)
}

internal data class HealthConnectPreview(
    val selected: Set<HealthConnectScope>,
    val allowed: Set<HealthConnectScope>,
    val rows: List<HealthConnectMeasurement>,
    val window: HealthConnectWindow,
) {
    init {
        val metrics = allowed.mapTo(hashSetOf()) { it.metric }
        require(allowed.isNotEmpty() && selected.containsAll(allowed))
        require(rows.size <= HealthConnectImport.MAX_ROWS && rows.all { it.draft.metric in metrics })
    }
}

internal object HealthConnectImport {
    const val MAX_ROWS = 1500

    fun allowed(selected: Set<HealthConnectScope>, granted: Set<String>) = selected.filterTo(linkedSetOf()) { it.permission in granted }

    suspend fun preview(reader: HealthConnectReader, selected: Set<HealthConnectScope>, window: HealthConnectWindow): HealthConnectPreview {
        require(selected.isNotEmpty())
        require(HealthConnectScope.STEPS !in selected || window.hours >= 24)
        val job = currentCoroutineContext()
        val allowed = allowed(selected, reader.granted())
        if (allowed.isEmpty()) throw HealthConnectPermissionChanged()
        val rows = mutableListOf<HealthConnectMeasurement>()
        val seen = hashSetOf<Triple<HealthMetric, String, String>>()
        allowed.forEach { scope ->
            reader.read(scope, window) { row ->
                job.ensureActive()
                check(row.draft.metric == scope.metric)
                if (seen.add(Triple(scope.metric, row.origin, row.id))) {
                    if (rows.size >= MAX_ROWS) throw HealthConnectTooManyRecords()
                    check(HealthObservationPolicy.validate(row.draft, window.end.toEpochMilli()) == null)
                    rows.add(row)
                }
            }
        }
        verifyGrants(reader, allowed)
        return HealthConnectPreview(selected.toSet(), allowed, rows, window)
    }

    suspend fun save(reader: HealthConnectReader, store: HealthRecordStore, preview: HealthConnectPreview): Int {
        verifyGrants(reader, preview.allowed)
        val job = currentCoroutineContext()
        return store.importHealthConnect(preview.rows) { job.ensureActive() }
    }

    private suspend fun verifyGrants(reader: HealthConnectReader, expected: Set<HealthConnectScope>) {
        if (allowed(expected, reader.granted()) != expected) throw HealthConnectPermissionChanged()
    }
}

internal class AndroidHealthConnectReader(context: Context) : HealthConnectReader {
    private val client = HealthConnectClient.getOrCreate(context.applicationContext, HealthSourcesRepository.PROVIDER_PACKAGE)

    override suspend fun granted(): Set<String> = client.permissionController.getGrantedPermissions()
    suspend fun revoke() = client.permissionController.revokeAllPermissions()

    override suspend fun read(scope: HealthConnectScope, window: HealthConnectWindow, emit: (HealthConnectMeasurement) -> Unit) {
        fun one(id: String, origin: String, time: Instant, values: List<String>) {
            val draft = HealthDraft(scope.metric, scope.metric.fields.zip(values).toMap(), measuredAt = time.toEpochMilli())
            emit(HealthConnectMeasurement(id, origin, draft))
        }
        fun instantRecord(record: Record, time: Instant, vararg values: Number) =
            one(record.metadata.id, record.metadata.dataOrigin.packageName, time, values.map(::decimal))
        when (scope) {
            HealthConnectScope.SLEEP -> pages(SleepSessionRecord::class, window) { row ->
                if (row.endTime >= window.start && row.endTime <= window.end) {
                    val hours = java.math.BigDecimal.valueOf(Duration.between(row.startTime, row.endTime).toMillis())
                        .divide(java.math.BigDecimal.valueOf(3_600_000), 5, java.math.RoundingMode.HALF_UP).stripTrailingZeros()
                    instantRecord(row, row.endTime, hours)
                }
            }
            HealthConnectScope.STEPS -> {
                val endDate = window.end.atZone(window.zone).toLocalDate()
                repeat(window.hours / 24) { index ->
                    currentCoroutineContext().ensureActive()
                    val date = endDate.minusDays((index + 1).toLong())
                    val start = date.atStartOfDay(window.zone).toInstant()
                    val end = date.plusDays(1).atStartOfDay(window.zone).toInstant()
                    if (end > start) {
                        val result = client.aggregate(AggregateRequest(setOf(StepsRecord.COUNT_TOTAL), TimeRangeFilter.between(start, end)))
                        result[StepsRecord.COUNT_TOTAL]?.let { one(date.toString(), "health_connect.aggregate", end.minusMillis(1), listOf(it.toString())) }
                    }
                }
            }
            HealthConnectScope.HEART_RATE -> pages(HeartRateRecord::class, window) { row ->
                row.samples.forEach { sample ->
                    if (sample.time >= window.start && sample.time < window.end) {
                        one("${row.metadata.id}:${sample.time}", row.metadata.dataOrigin.packageName, sample.time, listOf(sample.beatsPerMinute.toString()))
                    }
                }
            }
            HealthConnectScope.RESTING_HEART_RATE -> pages(RestingHeartRateRecord::class, window) { row ->
                instantRecord(row, row.time, row.beatsPerMinute)
            }
            HealthConnectScope.BLOOD_PRESSURE -> pages(BloodPressureRecord::class, window) { row ->
                instantRecord(row, row.time, row.systolic.inMillimetersOfMercury, row.diastolic.inMillimetersOfMercury)
            }
            HealthConnectScope.WEIGHT -> pages(WeightRecord::class, window) { row ->
                instantRecord(row, row.time, row.weight.inKilograms)
            }
        }
    }

    private suspend fun <T : Record> pages(type: KClass<T>, window: HealthConnectWindow, emit: (T) -> Unit) {
        var token: String? = null
        val seen = hashSetOf<String>()
        repeat(100) {
            currentCoroutineContext().ensureActive()
            val page = client.readRecords(ReadRecordsRequest(type, TimeRangeFilter.between(window.start, window.end), pageSize = 100, pageToken = token))
            page.records.forEach(emit)
            token = page.pageToken?.takeIf(String::isNotBlank)
            if (token == null) return
            check(seen.add(requireNotNull(token))) { "Repeated Health Connect page" }
        }
        throw HealthConnectTooManyRecords()
    }

    private fun decimal(value: Number): String = value.toString().toBigDecimal().stripTrailingZeros().toPlainString()
}

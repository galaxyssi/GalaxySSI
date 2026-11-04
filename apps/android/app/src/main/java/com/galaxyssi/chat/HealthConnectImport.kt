package com.galaxyssi.chat

import android.content.Context
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.changes.DeletionChange
import androidx.health.connect.client.changes.UpsertionChange
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.BloodPressureRecord
import androidx.health.connect.client.records.HeartRateRecord
import androidx.health.connect.client.records.Record
import androidx.health.connect.client.records.RestingHeartRateRecord
import androidx.health.connect.client.records.SleepSessionRecord
import androidx.health.connect.client.records.StepsRecord
import androidx.health.connect.client.records.WeightRecord
import androidx.health.connect.client.request.AggregateRequest
import androidx.health.connect.client.request.ChangesTokenRequest
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.time.TimeRangeFilter
import java.time.Duration
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import kotlin.reflect.KClass
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive

internal enum class HealthConnectScope(val metric: HealthMetric, val type: KClass<out Record>) {
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

internal class AndroidHealthConnectReader(context: Context) : HealthConnectReader, HealthSyncGateway {
    private val client = HealthConnectClient.getOrCreate(context.applicationContext, HealthSourcesRepository.PROVIDER_PACKAGE)

    override suspend fun granted(): Set<String> = client.permissionController.getGrantedPermissions()
    suspend fun revoke() = client.permissionController.revokeAllPermissions()

    override suspend fun read(scope: HealthConnectScope, window: HealthConnectWindow, emit: (HealthConnectMeasurement) -> Unit) {
        if (scope == HealthConnectScope.STEPS) {
            val day = window.end.atZone(window.zone).toLocalDate()
            repeat(window.hours / 24) { index ->
                currentCoroutineContext().ensureActive()
                stepDay(day.minusDays((index + 1).toLong()), window.zone)?.let(emit)
            }
            return
        }
        var token = ""
        val seen = hashSetOf<String>()
        repeat(100) {
            currentCoroutineContext().ensureActive()
            val page = snapshot(scope, window.start, window.end, token)
            page.rows.forEach(emit)
            token = page.next
            if (token.isEmpty()) return
            check(seen.add(token)) { "Repeated Health Connect page" }
        }
        throw HealthConnectTooManyRecords()
    }

    override suspend fun token(scope: HealthConnectScope) = client.getChangesToken(ChangesTokenRequest(setOf(scope.type)))

    override suspend fun snapshot(scope: HealthConnectScope, from: Instant, until: Instant, cursor: String): HealthSyncSnapshotPage {
        require(scope != HealthConnectScope.STEPS)
        val page = client.readRecords(ReadRecordsRequest(scope.type, TimeRangeFilter.between(from, until),
            pageSize = 100, pageToken = cursor.takeIf(String::isNotEmpty)))
        return HealthSyncSnapshotPage(page.records.asSequence().flatMap { project(scope, it, from, until) }, page.pageToken.orEmpty())
    }

    override suspend fun changes(scope: HealthConnectScope, token: String, until: Instant): HealthSyncChangePage {
        require(scope != HealthConnectScope.STEPS)
        val page = client.getChanges(token)
        return HealthSyncChangePage(page.changes.asSequence().filterIsInstance<UpsertionChange>()
            .flatMap { project(scope, it.record, Instant.EPOCH, until) }, page.nextChangesToken, page.hasMore,
            page.changesTokenExpired, page.changes.count { it is DeletionChange })
    }

    override suspend fun stepDay(day: LocalDate, zone: ZoneId): HealthConnectMeasurement? {
        val start = day.atStartOfDay(zone).toInstant()
        val end = day.plusDays(1).atStartOfDay(zone).toInstant()
        if (end <= start) return null
        val result = client.aggregate(AggregateRequest(setOf(StepsRecord.COUNT_TOTAL), TimeRangeFilter.between(start, end)))
        return result[StepsRecord.COUNT_TOTAL]?.let { count ->
            measurement(HealthConnectScope.STEPS, day.toString(), "health_connect.aggregate", end.minusMillis(1), listOf(count.toString()))
        }
    }

    private fun project(scope: HealthConnectScope, record: Record, from: Instant, until: Instant): Sequence<HealthConnectMeasurement> = sequence {
        check(scope.type.isInstance(record))
        val id = record.metadata.id
        val origin = record.metadata.dataOrigin.packageName
        suspend fun SequenceScope<HealthConnectMeasurement>.one(time: Instant, vararg values: Number, key: String = id) {
            if (time >= from && time <= until) yield(measurement(scope, key, origin, time, values.map(::decimal)))
        }
        when (record) {
            is SleepSessionRecord -> {
                val hours = java.math.BigDecimal.valueOf(Duration.between(record.startTime, record.endTime).toMillis())
                    .divide(java.math.BigDecimal.valueOf(3_600_000), 5, java.math.RoundingMode.HALF_UP).stripTrailingZeros()
                one(record.endTime, hours)
            }
            is HeartRateRecord -> record.samples.forEach { one(it.time, it.beatsPerMinute, key = "$id:${it.time}") }
            is RestingHeartRateRecord -> one(record.time, record.beatsPerMinute)
            is BloodPressureRecord -> one(record.time, record.systolic.inMillimetersOfMercury, record.diastolic.inMillimetersOfMercury)
            is WeightRecord -> one(record.time, record.weight.inKilograms)
            else -> error("Unsupported Health Connect record type")
        }
    }

    private fun measurement(scope: HealthConnectScope, id: String, origin: String, time: Instant, values: List<String>) =
        HealthConnectMeasurement(id, origin, HealthDraft(scope.metric, scope.metric.fields.zip(values).toMap(), measuredAt = time.toEpochMilli()))

    private fun decimal(value: Number): String = value.toString().toBigDecimal().stripTrailingZeros().toPlainString()
}

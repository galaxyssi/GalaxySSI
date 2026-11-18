package com.galaxyssi.chat

import android.content.Intent
import android.content.Context
import java.time.LocalDate
import java.time.ZoneId
import java.util.Base64

private const val PLATFORM_SCOPE = "health_platform_scope"
private val platformScopeAad = "galaxyssi-health-trend-platform-scope-v1".toByteArray(Charsets.UTF_8)

private fun sealPlatformScope(origin: String): String {
    val plaintext = origin.toByteArray(Charsets.UTF_8)
    return try { Base64.getUrlEncoder().withoutPadding().encodeToString(AgentStorageCipher.encryptBinary(plaintext, platformScopeAad)) }
    finally { plaintext.fill(0) }
}

private fun Intent.platformScope(): String {
    val sealed = getStringExtra(PLATFORM_SCOPE) ?: return ""
    require(sealed.length in 1..1024)
    val plaintext = AgentStorageCipher.decryptBinary(Base64.getUrlDecoder().decode(sealed), platformScopeAad)
    return try { String(plaintext, Charsets.UTF_8).also { require(validHealthTrendPlatformOrigin(it)) } }
    finally { plaintext.fill(0) }
}

internal fun Intent.putHealthTrend(spec: HealthTrendSpec) = putExtra("health_metric", spec.metric.name)
    .putExtra("health_first", spec.first.toString()).putExtra("health_last", spec.last.toString()).putExtra("health_zone", spec.zone.id)
    .putExtra("health_unit", spec.unit).putExtra("health_aggregation", spec.aggregation.name)
    .putExtra("health_origin", spec.source.originalId).putExtra("health_manual_source", spec.source.manualOnly)
    .putExtra("health_bluetooth_group", spec.source.bluetoothGroup)
    .putExtra("health_trend_condition", spec.source.condition).putExtra("health_trend_side", spec.source.side)
    .putExtra("health_trend_record_source", spec.source.recordSource)
    .apply {
        if (spec.source.platformOrigin.isNotEmpty()) putExtra(PLATFORM_SCOPE, sealPlatformScope(spec.source.platformOrigin))
        else removeExtra(PLATFORM_SCOPE)
    }

internal fun Intent.healthTrendSpec(): HealthTrendSpec? = runCatching {
    val metric = HealthMetric.valueOf(requireNotNull(getStringExtra("health_metric")))
    HealthTrendSpec(metric, LocalDate.parse(requireNotNull(getStringExtra("health_first"))), LocalDate.parse(requireNotNull(getStringExtra("health_last"))),
        ZoneId.of(requireNotNull(getStringExtra("health_zone"))), requireNotNull(getStringExtra("health_unit")),
        HealthTrendAggregation.valueOf(requireNotNull(getStringExtra("health_aggregation"))),
        HealthTrendSource(getStringExtra("health_origin").orEmpty(), getBooleanExtra("health_manual_source", false),
            getStringExtra("health_bluetooth_group").orEmpty(), platformScope(), getStringExtra("health_trend_condition").orEmpty(),
            getStringExtra("health_trend_side").orEmpty(), getStringExtra("health_trend_record_source").orEmpty()))
}.getOrNull()

internal fun HealthTrendAggregation.titleResource() = when (this) {
    HealthTrendAggregation.MEAN -> R.string.health_trend_mean
    HealthTrendAggregation.MINIMUM -> R.string.health_trend_min
    HealthTrendAggregation.MAXIMUM -> R.string.health_trend_max
    HealthTrendAggregation.LATEST -> R.string.health_measurement_latest_point
}

internal fun Context.healthBluetoothTrendLabel(group: String, name: String): String {
    val label = name.ifBlank { getString(R.string.health_ble_title) }
    return if (group.isEmpty()) getString(R.string.health_trend_bluetooth_unidentified, label)
    else getString(R.string.health_trend_bluetooth_label, label, group.take(8))
}

internal fun Context.healthConnectTrendLabel(origin: String, metric: HealthMetric): String = when {
    metric == HealthMetric.STEPS && origin == HEALTH_CONNECT_AGGREGATE_ORIGIN -> getString(R.string.health_connect_platform_aggregate)
    origin.isEmpty() -> getString(R.string.health_sources_platform_name)
    else -> getString(R.string.health_connect_platform_origin, origin)
}

internal fun Context.healthTrendSourceLabel(spec: HealthTrendSpec, name: String = "") = with(spec.source) {
    when {
        manualOnly -> getString(R.string.health_source_manual)
        bluetoothGroup.isNotEmpty() -> healthBluetoothTrendLabel(bluetoothGroup, name)
        platformOrigin.isNotEmpty() -> healthConnectTrendLabel(platformOrigin, spec.metric)
        originalId.isNotEmpty() -> name.ifBlank { getString(R.string.health_trend_original_source, originalId.take(8)) }
        recordSource.isNotEmpty() -> getString(healthRecordSourceResource(recordSource))
        else -> getString(R.string.health_trend_all_sources)
    }
}

internal fun healthComparableTrendIntent(context: Context, names: HealthOverviewDatabases, record: HealthObservation): Intent {
    val zone = ZoneId.systemDefault()
    val last = java.time.Instant.ofEpochMilli(record.draft.measuredAt).atZone(zone).toLocalDate()
    val source = when {
        record.draft.evidence != null -> HealthTrendSource(recordSource = record.source)
        record.bluetoothGroup.isNotEmpty() -> HealthTrendSource(bluetoothGroup = record.bluetoothGroup)
        record.platformOrigin.isNotEmpty() -> HealthTrendSource(platformOrigin = record.platformOrigin)
        record.source == "manual" -> HealthTrendSource(manualOnly = true)
        else -> HealthTrendSource(recordSource = record.source)
    }.copy(condition = record.draft.condition, side = record.draft.side)
    return Intent(context, HealthTrendActivity::class.java).putHealthNavigationFixture(names)
        .putExtra("health_continuous", true)
        .putExtra("health_trend_anchor", last.toString())
        .putHealthTrend(HealthTrendSpec(record.draft.metric, last.minusMonths(6), last, zone, record.draft.unit,
            aggregation = if (record.draft.evidence != null) HealthTrendAggregation.LATEST else HealthTrendAggregation.MEAN, source = source))
}

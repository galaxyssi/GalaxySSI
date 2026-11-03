package com.galaxyssi.chat

import android.content.Intent
import java.time.LocalDate
import java.time.ZoneId

internal fun Intent.putHealthTrend(spec: HealthTrendSpec) = putExtra("health_metric", spec.metric.name)
    .putExtra("health_first", spec.first.toString()).putExtra("health_last", spec.last.toString()).putExtra("health_zone", spec.zone.id)
    .putExtra("health_unit", spec.unit).putExtra("health_aggregation", spec.aggregation.name)
    .putExtra("health_origin", spec.source.originalId).putExtra("health_manual_source", spec.source.manualOnly)

internal fun Intent.healthTrendSpec(): HealthTrendSpec? = runCatching {
    val metric = HealthMetric.valueOf(requireNotNull(getStringExtra("health_metric")))
    HealthTrendSpec(metric, LocalDate.parse(requireNotNull(getStringExtra("health_first"))), LocalDate.parse(requireNotNull(getStringExtra("health_last"))),
        ZoneId.of(requireNotNull(getStringExtra("health_zone"))), requireNotNull(getStringExtra("health_unit")),
        HealthTrendAggregation.valueOf(requireNotNull(getStringExtra("health_aggregation"))),
        HealthTrendSource(getStringExtra("health_origin").orEmpty(), getBooleanExtra("health_manual_source", false)))
}.getOrNull()

internal fun HealthTrendAggregation.titleResource() = when (this) {
    HealthTrendAggregation.MEAN -> R.string.health_trend_mean
    HealthTrendAggregation.MINIMUM -> R.string.health_trend_min
    HealthTrendAggregation.MAXIMUM -> R.string.health_trend_max
}

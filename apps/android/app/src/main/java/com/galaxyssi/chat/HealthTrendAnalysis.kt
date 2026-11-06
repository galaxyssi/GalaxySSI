package com.galaxyssi.chat

import android.content.Context
import android.content.Intent
import android.os.CancellationSignal
import org.json.JSONArray
import org.json.JSONObject

internal const val HEALTH_TREND_ANALYSIS_VERSION = "health_trend_analysis_version"

internal data class HealthTrendAnalysisHandoff(val spec: HealthTrendSpec, val version: String) {
    init { require(version.isEmpty() || HealthProfilePolicy.uuid(version)) }
}

internal fun Intent.putHealthTrendAnalysis(handoff: HealthTrendAnalysisHandoff) =
    putHealthTrend(handoff.spec).putExtra(HEALTH_TREND_ANALYSIS_VERSION, handoff.version)

internal fun Intent.healthTrendAnalysisHandoff(): HealthTrendAnalysisHandoff? = runCatching {
    HealthTrendAnalysisHandoff(requireNotNull(healthTrendSpec()), requireNotNull(getStringExtra(HEALTH_TREND_ANALYSIS_VERSION)))
}.getOrNull()

internal data class HealthTrendAnalysisFact(
    val key: String, val first: HealthTrendPoint, val last: HealthTrendPoint, val pointCount: Int,
) {
    val delta get() = if (pointCount > 1) (last.value - first.value).stripTrailingZeros() else null
}

internal data class HealthTrendAnalysisPreview(
    val handoff: HealthTrendAnalysisHandoff, override val policyVersion: String, val facts: List<HealthTrendAnalysisFact>,
    val numericRecords: Long, val numericDays: Int, val recordedDays: Int, val nonNumeric: Long, val otherUnits: Long,
) : HealthAnalysisInput {
    override val focus get() = HealthAnalysisFocus.CHANGES
    override val hasData get() = facts.isNotEmpty()
    override val factKeys get() = facts.map { it.key }
    override val allowedActions get() = listOf(HealthAnalysisAction.ADD_RECORD, HealthAnalysisAction.RECORD_REMINDER)

    fun payload(): JSONObject {
        val spec = handoff.spec
        fun bucket(point: HealthTrendPoint) = JSONObject().put("index", point.bucket + 1)
            .put("value", point.value.toPlainString()).put("record_count", point.count)
        return JSONObject().put("scope", "filtered_trend").put("focus", focus.name)
            .put("period_days", spec.days).put("bucket_days", spec.bucketDays)
            .put("aggregation", spec.aggregation.name).put("metric", spec.metric.name).put("unit", spec.unit)
            .put("numeric_records", numericRecords).put("numeric_days", numericDays).put("recorded_days", recordedDays)
            .put("missing_days", spec.days - recordedDays).put("excluded_non_numeric", nonNumeric).put("excluded_other_units", otherUnits)
            .put("facts", JSONArray(facts.map { fact ->
                JSONObject().put("id", fact.key).put("field", fact.first.field).put("point_count", fact.pointCount)
                    .put("first", bucket(fact.first)).apply {
                        fact.delta?.let { put("last", bucket(fact.last)).put("delta", it.toPlainString()) }
                    }
            })).put("allowed_actions", JSONArray(allowedActions.map { it.name }))
    }
}

internal object HealthTrendAnalysis {
    fun prepare(context: Context, names: HealthOverviewDatabases, handoff: HealthTrendAnalysisHandoff,
                signal: CancellationSignal? = null): HealthTrendAnalysisPreview =
        HealthPrivacyStore(context, names.privacy).use { privacy ->
            privacy.track(HealthAccessScope.trend(HealthAccessPurpose.HEALTH_ANALYSIS, handoff.spec)) {
                val policyVersion = privacy.policy().version
                HealthRecordStore(context, names.records).use { store ->
                    requireCurrent(store, handoff)
                    val trend = HealthTrendRepository.load(store, handoff.spec, { signal?.throwIfCanceled() }, signal = signal)
                    if (trend.version != handoff.version) throw HealthTrendChangedException()
                    project(trend, policyVersion)
                }
            }
        }

    fun requireCurrent(store: HealthRecordStore, handoff: HealthTrendAnalysisHandoff) {
        if (store.metricVersion(handoff.spec.metric) != handoff.version) throw HealthTrendChangedException()
    }

    fun project(trend: HealthTrendSummary, policyVersion: String): HealthTrendAnalysisPreview {
        val grouped = trend.points.groupBy { it.field }
        val facts = trend.spec.metric.requiredFields.mapIndexedNotNull { index, field ->
            val points = grouped[field] ?: return@mapIndexedNotNull null
            HealthTrendAnalysisFact("f${index + 1}", points.first(), points.last(), points.size)
        }
        return HealthTrendAnalysisPreview(HealthTrendAnalysisHandoff(trend.spec, trend.version), policyVersion,
            facts, trend.eligible, trend.numericDays, trend.reportedDays, trend.nonNumeric, trend.otherUnits)
    }
}

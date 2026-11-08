package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject

/** A contiguous recent page, not a clinical stability score or a filtered selection of normal results. */
internal data class HealthCareSeries(val samples: List<HealthCareSample>, val hasEarlier: Boolean) {
    init {
        require(samples.size in 1..30 && samples.map { it.record.id }.distinct().size == samples.size)
        require(samples.all { it.metric == samples.first().metric })
        require(samples == samples.sortedWith(compareByDescending<HealthCareSample> { it.measuredAt }.thenByDescending { it.record.id }))
    }
    fun json() = JSONObject().put("samples", JSONArray(samples.map { it.json() })).put("has_earlier", hasEarlier)
    fun modelJson(current: HealthCareSample, context: HealthCareContext?, previous: HealthCareComparison?): JSONObject =
        JSONObject().put("samples", JSONArray(samples.map { sample -> sample.modelJson().apply {
            val confirmed = context?.takeIf { it.record == sample.record }
                ?: previous?.previousContext?.takeIf { it.record == sample.record }
            put("confirmed_context", confirmed?.json() ?: JSONObject.NULL)
            put("gaps_against_current", JSONArray(if (sample.record == current.record) emptyList<String>() else
                HealthCareComparisonPolicy.gaps(sample, current, confirmed, context?.takeIf { it.record == current.record }).map { it.name }))
        } })).put("has_earlier", hasEarlier).put("stability_verified", false)
            .put("coverage", "One contiguous page of source revisions; no selection by result value. Missing context is unknown. Count and numeric agreement do not establish stability.")
    companion object {
        const val VERSION = "longitudinal-evidence-1"
        fun from(j: JSONObject) = HealthCareSeries(j.getJSONArray("samples").let { a ->
            (0 until a.length()).map { HealthCareSample.from(a.getJSONObject(it)) } }, j.getBoolean("has_earlier"))
        fun of(page: HealthRecordPage) = page.records.takeIf { it.isNotEmpty() }?.let {
            HealthCareSeries(it.map(HealthCareSample::of), page.next != null)
        }
    }
}

package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject

/** A bounded, source-revision-bound measurement snapshot, without notes or original attachments. */
internal data class HealthCareSample(val record: HealthCareRecordRef, val metric: HealthMetric, val measuredAt: Long,
    val values: Map<String, String>, val unit: String, val reference: String, val condition: String, val side: String,
    val source: String, val origin: String, val deviceGroup: String) {
    init {
        require(measuredAt > 0 && values.isNotEmpty() && values.keys.all { it in metric.fields })
        require(values.values.all { it.length <= HealthResult.MAX_LENGTH } && unit.length <= 32 && reference.length <= 200)
        require(condition.length <= 80 && side.length <= 80 && source.length <= 80 && origin.length <= 1000 && deviceGroup.length <= 64)
    }
    fun unitFor(field: String) = if (metric == HealthMetric.BLOOD_PRESSURE && field == "pulse") "bpm" else unit
    fun json() = JSONObject().put("record", record.json()).put("metric", metric.name).put("measured_at", measuredAt)
        .put("values", JSONObject(values)).put("unit", unit).put("reference", reference).put("condition", condition)
        .put("side", side).put("source", source).put("origin", origin).put("device_group", deviceGroup)
    fun modelJson() = json().apply { remove("origin"); remove("device_group") }
    companion object {
        fun of(value: HealthObservation) = with(value.draft) { HealthCareSample(HealthCareRecordRef(value.id, value.revision),
            metric, measuredAt, values, unit, reference, condition, side, value.source, value.platformOrigin, value.bluetoothGroup) }
        fun from(j: JSONObject) = HealthCareSample(HealthCareRecordRef.from(j.getJSONObject("record")),
            HealthMetric.valueOf(j.getString("metric")), j.getLong("measured_at"), j.getJSONObject("values").let { v ->
                v.keys().asSequence().associateWith(v::getString) }, j.getString("unit"), j.getString("reference"),
            j.getString("condition"), j.getString("side"), j.getString("source"), j.getString("origin"), j.getString("device_group"))
    }
}

internal enum class HealthCareComparisonKind { NEW_RESULT, RECORD_CORRECTION, HISTORY_CHANGED }
internal enum class HealthCareComparisonGap {
    UNITS_DIFFER, CONDITIONS_DIFFER, CONDITIONS_UNKNOWN, SOURCE_DIFFERS, REFERENCE_DIFFERS,
    NON_EXACT_RESULT, CONTEXT_UNCONFIRMED, CONTEXT_DIFFERS, METHOD_UNVERIFIED
}
internal data class HealthCareComparison(val before: HealthCareSample, val kind: HealthCareComparisonKind,
    val previousContext: HealthCareContext? = null) {
    init { require(previousContext == null || previousContext.record == before.record) }
    fun json() = JSONObject().put("before", before.json()).put("kind", kind.name)
        .put("previous_context", previousContext?.json() ?: JSONObject.NULL)
    companion object { fun from(j: JSONObject) = HealthCareComparison(HealthCareSample.from(j.getJSONObject("before")),
        HealthCareComparisonKind.valueOf(j.getString("kind")), j.optJSONObject("previous_context")?.let(HealthCareContext::from)) }
}

internal object HealthCareComparisonPolicy {
    fun build(current: HealthCareSample, eligible: List<HealthObservation>, previous: HealthCareAssessment?,
        context: HealthCareContext?): HealthCareComparison? {
        fun live(sample: HealthCareSample) = eligible.any { it.id == sample.record.id && it.revision == sample.record.revision }
        if (previous?.sample?.record == current.record) return previous.comparison?.takeIf {
            live(it.before) || it.kind == HealthCareComparisonKind.RECORD_CORRECTION && it.before.record.id == current.record.id
        }
        if (previous?.sample == null && previous?.record?.id == current.record.id && previous.record != current.record) return null
        val old = previous?.sample?.takeIf { live(it) || it.record.id == current.record.id }
            ?: eligible.firstOrNull { it.id != current.record.id && it.draft.measuredAt < current.measuredAt }?.let(HealthCareSample::of)
            ?: return null
        val kind = when {
            old.record.id == current.record.id -> HealthCareComparisonKind.RECORD_CORRECTION
            previous?.record == current.record || previous?.sample != null && !live(previous.sample) ||
                current.measuredAt <= old.measuredAt -> HealthCareComparisonKind.HISTORY_CHANGED
            else -> HealthCareComparisonKind.NEW_RESULT
        }
        val confirmed = context?.takeIf { it.record == old.record }
            ?: previous?.comparison?.previousContext?.takeIf { it.record == old.record }
        return HealthCareComparison(old, kind, confirmed)
    }

    fun gaps(value: HealthCareAssessment, context: HealthCareContext?): Set<HealthCareComparisonGap> {
        val previous = value.comparison ?: return emptySet()
        val before = previous.before
        val after = value.sample ?: return emptySet()
        return gaps(before, after, previous.previousContext, context?.takeIf { it.record == after.record })
    }

    fun gaps(before: HealthCareSample, after: HealthCareSample, old: HealthCareContext?, now: HealthCareContext?): Set<HealthCareComparisonGap> {
        require(before.metric == after.metric)
        require(old == null || old.record == before.record)
        require(now == null || now.record == after.record)
        val gaps = linkedSetOf(HealthCareComparisonGap.METHOD_UNVERIFIED)
        if (before.unit != after.unit) gaps += HealthCareComparisonGap.UNITS_DIFFER
        if (before.condition == "unspecified" || after.condition == "unspecified") gaps += HealthCareComparisonGap.CONDITIONS_UNKNOWN
        else if (before.condition != after.condition || before.side != after.side) gaps += HealthCareComparisonGap.CONDITIONS_DIFFER
        if (before.source != after.source || before.origin != after.origin || before.deviceGroup != after.deviceGroup) gaps += HealthCareComparisonGap.SOURCE_DIFFERS
        if (before.reference != after.reference) gaps += HealthCareComparisonGap.REFERENCE_DIFFERS
        if (after.metric.requiredFields.any { HealthResult.parse(before.values[it].orEmpty(), after.metric.form)?.exactNumber == null ||
                HealthResult.parse(after.values[it].orEmpty(), after.metric.form)?.exactNumber == null }) gaps += HealthCareComparisonGap.NON_EXACT_RESULT
        if (after.metric == HealthMetric.GLUCOSE) {
            fun incomplete(c: HealthCareContext?) = c == null || c.adult == HealthCareTruth.UNKNOWN ||
                c.pregnant == HealthCareTruth.UNKNOWN || c.diagnosedDiabetes == HealthCareTruth.UNKNOWN ||
                c.specimen == HealthCareSpecimen.UNKNOWN || c.fastingHours == null || c.illnessOrMedication == HealthCareTruth.UNKNOWN
            if (incomplete(old) || incomplete(now)) gaps += HealthCareComparisonGap.CONTEXT_UNCONFIRMED
            if (old != null && now != null && old.copy(record = now.record, confirmedAt = now.confirmedAt) != now)
                gaps += HealthCareComparisonGap.CONTEXT_DIFFERS
        }
        return gaps
    }

    fun handoff(value: HealthCareAssessment, context: HealthCareContext?): JSONObject? {
        val comparison = value.comparison ?: return null
        val after = value.sample ?: return null
        val before = comparison.before
        val changes = after.metric.fields.mapNotNull { field ->
            if (comparison.kind != HealthCareComparisonKind.NEW_RESULT || before.unitFor(field) != after.unitFor(field)) return@mapNotNull null
            val old = HealthResult.parse(before.values[field].orEmpty(), after.metric.form)?.exactNumber ?: return@mapNotNull null
            val now = HealthResult.parse(after.values[field].orEmpty(), after.metric.form)?.exactNumber ?: return@mapNotNull null
            JSONObject().put("field", field).put("unit", after.unitFor(field)).put("delta", now.subtract(old).toPlainString())
        }
        return JSONObject().put("kind", comparison.kind.name).put("before", before.modelJson()).put("after", after.modelJson())
            .put("previous_confirmed_context", comparison.previousContext?.json() ?: JSONObject.NULL)
            .put("current_confirmed_context", context?.takeIf { it.record == after.record }?.json() ?: JSONObject.NULL)
            .put("arithmetic_changes_only", JSONArray(changes)).put("comparison_gaps", JSONArray(gaps(value, context).map { it.name }))
            .put("clinical_direction_verified", false)
    }
}

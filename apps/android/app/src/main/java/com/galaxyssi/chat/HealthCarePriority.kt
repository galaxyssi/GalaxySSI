package com.galaxyssi.chat

import java.math.BigDecimal
import java.time.LocalDate
import java.time.ZoneOffset
import org.json.JSONObject

/** A recorded-value warning, not a diagnosis or a current-symptom triage service. */
internal object HealthCarePriority {
    const val BLOOD_PRESSURE_VERSION = "bp-record-warning-1"
    const val SOURCE = "https://www.heart.org/en/health-topics/high-blood-pressure/understanding-blood-pressure-readings/when-to-call-911-for-high-blood-pressure"
    private val checkedAt = LocalDate.of(2026, 11, 7).atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli()
    // NIST SP 811: conventional mmHg = 133.3224 Pa. Compare without intermediate rounding.
    private val kpaPerMmHg = BigDecimal("0.1333224")

    fun evaluationVersion(metric: HealthMetric) = if (metric == HealthMetric.BLOOD_PRESSURE) BLOOD_PRESSURE_VERSION else ""
    fun needsReview(draft: HealthDraft): Boolean {
        if (draft.metric != HealthMetric.BLOOD_PRESSURE || HealthObservationPolicy.validate(draft) != null) return false
        val scale = if (draft.unit == "kPa") kpaPerMmHg else BigDecimal.ONE
        return listOf("systolic" to "180", "diastolic" to "120").any { (field, threshold) ->
            HealthResult.parse(draft.values[field].orEmpty(), draft.metric.form)?.exactNumber?.let {
                it > BigDecimal(threshold) * scale
            } == true
        }
    }
    fun rank(assessment: HealthCareAssessment) = if (HealthCareSignal.BLOOD_PRESSURE_ALERT in assessment.signals) 1 else 0
    fun guideline() = HealthCareGuideline("aha-markedly-elevated-blood-pressure", "AHA: When to call for emergency help for high blood pressure",
        SOURCE, "Reviewed 2025-08-14", "Adult, nonpregnant guidance; age, pregnancy and current symptoms must not be assumed.",
        "A recorded systolic value above 180 or diastolic value above 120 mmHg requires prompt attention. " +
            "Historical readings alone do not establish a current emergency. See the source for symptom-dependent action; " +
            "this is not an individualized target or a medication instruction.", checkedAt)

    fun handoff(value: HealthCareConcern): JSONObject? = if (rank(value.assessment) == 0) null else JSONObject()
        .put("type", BLOOD_PRESSURE_VERSION).put("recorded_at", value.assessment.measuredAt)
        .put("current_symptoms", "unknown").put("current_emergency_established", false)
        .put("guidance_scope", "adult_nonpregnant_not_assumed")
        .put("source_url", SOURCE).put("source_checked_at", checkedAt)
        .put("rule", "systolic > 180 OR diastolic > 120 mmHg; recorded values, not live monitoring")
}

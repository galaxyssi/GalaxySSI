package com.galaxyssi.chat

import java.math.BigDecimal
import java.math.RoundingMode
import java.time.LocalDate
import java.time.ZoneOffset
import java.util.UUID

internal object HealthCarePolicy {
    const val VERSION = "health-care-assessment-1"
    private val guidelineChecked = LocalDate.of(2026, 11, 7).atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli()

    fun assess(metric: HealthMetric, records: List<HealthObservation>, context: HealthCareContext?, previous: HealthCareAssessment? = null): HealthCareAssessment? {
        val eligible = records.filter { it.profileId == "self" && it.draft.metric == metric &&
            HealthObservationPolicy.validate(it.draft) == null }.sortedWith(compareByDescending<HealthObservation> {
                it.draft.measuredAt }.thenByDescending { it.id })
        val latest = eligible.firstOrNull() ?: return null
        val ref = HealthCareRecordRef(latest.id, latest.revision)
        val draft = latest.draft
        val exact = metric.fields.associateWith { field -> HealthResult.parse(draft.values[field].orEmpty(), metric.form)?.exactNumber }
        val signals = linkedSetOf<HealthCareSignal>()
        val field = metric.fields.singleOrNull()
        val value = field?.let { exact[it] }
        val reference = HealthResult.parse(draft.reference, HealthResultForm.LABORATORY)
        if (field != null && draft.reference.isNotBlank()) {
            if (value == null) signals += HealthCareSignal.RESULT_NOT_EXACT
            else when (reference?.kind) {
                HealthResultKind.RANGE -> {
                    if (value < BigDecimal(reference.number)) signals += HealthCareSignal.REPORT_LOW
                    if (value > BigDecimal(reference.upper)) signals += HealthCareSignal.REPORT_HIGH
                }
                HealthResultKind.COMPARISON -> when (reference.operator) {
                    "<" -> if (value >= BigDecimal(reference.number)) signals += HealthCareSignal.REPORT_HIGH
                    "<=" -> if (value > BigDecimal(reference.number)) signals += HealthCareSignal.REPORT_HIGH
                    ">" -> if (value <= BigDecimal(reference.number)) signals += HealthCareSignal.REPORT_LOW
                    ">=" -> if (value < BigDecimal(reference.number)) signals += HealthCareSignal.REPORT_LOW
                }
                else -> Unit
            }
        }
        var guideline: HealthCareGuideline? = null
        if (HealthCarePriority.needsReview(draft)) {
            signals += HealthCareSignal.BLOOD_PRESSURE_ALERT
            guideline = HealthCarePriority.guideline()
        }
        if (metric == HealthMetric.GLUCOSE && value != null) {
            // Compare each supported unit to its published threshold; conversion rounding must not decide eligibility.
            val threshold = if (draft.unit == "mg/dL") BigDecimal("100") else BigDecimal("5.6")
            if (value >= threshold && (draft.condition != "after_meal" || context?.record == ref)) {
                if (context?.record == ref && context.excludesScreeningFpg) signals += HealthCareSignal.GUIDELINE_SCOPE
                else if (context?.record != ref || !context.screeningFpgApplicable) signals += HealthCareSignal.GLUCOSE_CONTEXT
                else {
                    signals += HealthCareSignal.GUIDELINE_REVIEW
                    guideline = HealthCareGuideline("ada-2026-fpg-screening", "ADA Standards of Care 2026: Diagnosis and Classification",
                        "https://diabetesjournals.org/care/article/49/Supplement_1/S27/163926", "2026",
                        "Nonpregnant adults without known diabetes; laboratory plasma glucose after at least eight hours without calories.",
                        "Fasting plasma glucose at or above 5.6 mmol/L (100 mg/dL) warrants risk assessment. " +
                            "A screening threshold is not a diagnosis, an individual treatment target, or an automatic retesting interval.", guidelineChecked)
                }
            }
        }
        val comparable = if (field == null || draft.condition == "unspecified") emptyList() else eligible.drop(1).filter {
            it.draft.unit == draft.unit && it.draft.condition == draft.condition && it.source == latest.source &&
                it.platformOrigin == latest.platformOrigin && it.bluetoothGroup == latest.bluetoothGroup &&
                it.draft.reference == draft.reference && it.draft.measuredAt <= draft.measuredAt - 86_400_000L &&
                HealthResult.parse(it.draft.values[field].orEmpty(), metric.form)?.exactNumber != null
        }.distinctBy { it.draft.measuredAt / 86_400_000L }.take(7)
        val baseline = if (comparable.size < 2 || field == null) null else {
            val values = comparable.map { HealthResult.parse(it.draft.values.getValue(field), metric.form)!!.exactNumber!! }
            HealthCareBaseline(comparable.map { HealthCareRecordRef(it.id, it.revision) }, draft.unit,
                values.minOrNull()!!.toPlainString(), values.maxOrNull()!!.toPlainString(),
                comparable.minOf { it.draft.measuredAt }, comparable.maxOf { it.draft.measuredAt })
        }
        // Describe a series, never infer a clinical risk cutoff or target from the person's historical range.
        if (baseline != null && value != null && comparable.size >= 2) {
            val points = listOf(value) + comparable.take(2).map { HealthResult.parse(it.draft.values.getValue(field!!), metric.form)!!.exactNumber!! }
            if (points.zipWithNext().all { (new, old) -> new > old }) signals += HealthCareSignal.RISING_SERIES
            if (points.zipWithNext().all { (new, old) -> new < old }) signals += HealthCareSignal.FALLING_SERIES
        }
        val sample = HealthCareSample.of(latest)
        return HealthCareAssessment(ref, draft.measuredAt, metric.requiredFields.joinToString(" / ") { draft.values[it].orEmpty() },
            draft.unit, draft.reference, signals, guideline, baseline, sample,
            HealthCareComparisonPolicy.build(sample, eligible, previous, context))
    }

    fun reconcile(prior: HealthCareConcern?, metric: HealthMetric, assessment: HealthCareAssessment?,
        inputVersion: String, now: Long): HealthCareConcern? {
        if (assessment == null && prior == null || assessment?.signals?.isEmpty() == true && prior == null) return null
        val next = assessment ?: HealthCareAssessment(null, 0, "", "", "", setOf(HealthCareSignal.SOURCE_REMOVED))
        if (prior == null) return HealthCareConcern(UUID.randomUUID().toString(), metric, 1, now, now, inputVersion, next,
            if (HealthCareSignal.GUIDELINE_REVIEW in next.signals) HealthCareStage.REVIEW_EVIDENCE else HealthCareStage.VERIFY_CONTEXT)
        require(prior.metric == metric)
        if (prior.inputVersion == inputVersion && prior.assessment == next) return prior
        val changed = prior.assessment != next
        val stage = when {
            prior.stage == HealthCareStage.PAUSED -> HealthCareStage.PAUSED
            !changed -> prior.stage
            prior.stage == HealthCareStage.CLOSED && next.signals.isEmpty() -> HealthCareStage.CLOSED
            next.record == null || HealthCareSignal.GLUCOSE_CONTEXT in next.signals || HealthCareSignal.RESULT_NOT_EXACT in next.signals -> HealthCareStage.VERIFY_CONTEXT
            else -> HealthCareStage.REASSESS
        }
        return prior.copy(revision = prior.revision + 1, updatedAt = maxOf(prior.updatedAt, now), inputVersion = inputVersion,
            assessment = next, stage = stage, context = prior.context?.takeIf { it.record == next.record })
    }

    fun review(value: HealthCareConcern, stage: HealthCareStage, reason: String, reviewer: String, now: Long): HealthCareConcern {
        require(stage in setOf(HealthCareStage.MAINTENANCE, HealthCareStage.CLOSED, HealthCareStage.PAUSED, HealthCareStage.REASSESS))
        require(reason.isNotBlank() && reviewer.isNotBlank())
        if (stage == HealthCareStage.MAINTENANCE) {
            require(value.assessment.record != null)
            require(value.actions.none { it.state == HealthCareActionState.PROPOSED })
        }
        return value.copy(stage = stage, reviewNote = reason, reviewedBy = reviewer, updatedAt = maxOf(value.updatedAt, now))
    }

    fun baselineText(value: HealthCareBaseline): String = "${BigDecimal(value.low).setScale(2, RoundingMode.HALF_UP).stripTrailingZeros().toPlainString()}" +
        " - ${BigDecimal(value.high).setScale(2, RoundingMode.HALF_UP).stripTrailingZeros().toPlainString()} ${value.unit}"
}

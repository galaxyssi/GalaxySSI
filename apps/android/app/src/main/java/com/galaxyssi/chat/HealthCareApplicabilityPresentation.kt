package com.galaxyssi.chat

import android.content.Context

internal object HealthCareApplicabilityPresentation {
    fun text(context: Context, plan: HealthCarePlan, issue: HealthCareConcern, action: HealthCareAction): String =
        text(context, plan.applicability[action.id], issue, HealthCareApplicabilityPolicy.canAccept(plan, issue, action))
    fun text(context: Context, review: HealthCareApplicability?, issue: HealthCareConcern, canAccept: Boolean): String {
        val status = HealthCareApplicabilityPolicy.status(review, issue)
        val lines = mutableListOf(context.getString(when (status) {
            HealthCareApplicabilityStatus.MISSING_REVIEW -> R.string.health_applicability_legacy
            HealthCareApplicabilityStatus.DISCUSSION_ONLY -> R.string.health_applicability_discussion
            HealthCareApplicabilityStatus.DECLARED_CHECKS_MATCH -> R.string.health_applicability_match
            HealthCareApplicabilityStatus.NEEDS_CONTEXT -> R.string.health_applicability_unknown
            HealthCareApplicabilityStatus.MISMATCH -> R.string.health_applicability_mismatch
            HealthCareApplicabilityStatus.CONFLICT -> R.string.health_applicability_conflict
        }))
        review?.checks?.forEach { check ->
            val actual = HealthCareApplicabilityPolicy.actual(check, issue)
            val expected = display(context, check.field, check.expected)
            val condition = context.getString(when (check.operator) {
                HealthCareApplicabilityOperator.EQUALS -> R.string.health_applicability_equals
                HealthCareApplicabilityOperator.AT_LEAST -> R.string.health_applicability_at_least
                HealthCareApplicabilityOperator.AT_MOST -> R.string.health_applicability_at_most
            }, expected)
            lines += context.getString(R.string.health_applicability_check, context.getString(field(check.field)),
                condition, display(context, check.field, actual), check.sourceIndex + 1)
        }
        review?.missingInformation?.takeIf { it.isNotEmpty() }?.let {
            lines += context.getString(R.string.health_applicability_missing, it.joinToString("\n"))
        }
        review?.conflicts?.forEach { conflict ->
            lines += context.getString(R.string.health_applicability_conflict_detail,
                conflict.sourceIndices.joinToString(", ") { (it + 1).toString() }, conflict.detail, conflict.nextStep)
        }
        if (!canAccept) lines += context.getString(R.string.health_applicability_blocked)
        return lines.joinToString("\n\n")
    }
    private fun field(value: HealthCareApplicabilityField) = when (value) {
        HealthCareApplicabilityField.metric -> R.string.health_applicability_metric
        HealthCareApplicabilityField.unit -> R.string.health_applicability_unit
        HealthCareApplicabilityField.collection_condition -> R.string.health_applicability_collection
        HealthCareApplicabilityField.adult -> R.string.health_care_adult
        HealthCareApplicabilityField.pregnant -> R.string.health_care_pregnant
        HealthCareApplicabilityField.diabetes -> R.string.health_care_diabetes
        HealthCareApplicabilityField.specimen -> R.string.health_care_sample
        HealthCareApplicabilityField.fasting -> R.string.health_care_fasting
        HealthCareApplicabilityField.illness_medication -> R.string.health_care_illness
    }
    private fun display(context: Context, field: HealthCareApplicabilityField, value: String?): String {
        if (value == null) return context.getString(R.string.health_care_unknown)
        if (field == HealthCareApplicabilityField.metric) return context.getString(HealthMetric.valueOf(value).titleResource())
        if (field == HealthCareApplicabilityField.collection_condition && value in setOf("resting", "after_exercise", "fasting", "after_meal", "other"))
            return context.getString(healthContextResource(value))
        val resource = when (value) {
            "YES" -> R.string.health_care_yes
            "NO" -> R.string.health_care_no
            "LAB_PLASMA" -> R.string.health_care_lab_plasma
            "HOME_CAPILLARY" -> R.string.health_care_capillary
            "INTERSTITIAL" -> R.string.health_care_interstitial
            else -> null
        }
        return resource?.let(context::getString) ?: value
    }
}

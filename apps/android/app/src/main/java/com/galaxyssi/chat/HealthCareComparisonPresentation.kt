package com.galaxyssi.chat

import android.content.Context
import java.text.DateFormat
import java.util.Date

internal object HealthCareComparisonPresentation {
    private fun sample(value: HealthCareSample) = value.metric.fields.filter { !value.values[it].isNullOrBlank() }
        .joinToString(" / ") { "${value.values[it]} ${value.unitFor(it)}".trim() }
    fun summary(context: Context, value: HealthCareAssessment): String? {
        val comparison = value.comparison ?: return null
        val after = value.sample ?: return null
        return context.getString(when (comparison.kind) {
            HealthCareComparisonKind.NEW_RESULT -> R.string.health_care_comparison_values
            HealthCareComparisonKind.RECORD_CORRECTION -> R.string.health_care_comparison_correction
            HealthCareComparisonKind.HISTORY_CHANGED -> R.string.health_care_comparison_history
        }, sample(comparison.before), sample(after))
    }
    fun details(context: Context, value: HealthCareConcern): String? {
        val comparison = value.assessment.comparison ?: return null
        val after = value.assessment.sample ?: return null
        val date = DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT)
        return listOfNotNull(summary(context, value.assessment),
            context.getString(R.string.health_care_comparison_times, date.format(Date(comparison.before.measuredAt)), date.format(Date(after.measuredAt))),
            HealthCareComparisonPolicy.gaps(value.assessment, value.context).joinToString("\n") {
                context.getString(gapResource(it))
            }, context.getString(R.string.health_care_comparison_not_clinical)).joinToString("\n\n")
    }
    fun gapResource(value: HealthCareComparisonGap): Int = when (value) {
        HealthCareComparisonGap.UNITS_DIFFER -> R.string.health_care_comparison_units
        HealthCareComparisonGap.CONDITIONS_DIFFER -> R.string.health_care_comparison_conditions
        HealthCareComparisonGap.CONDITIONS_UNKNOWN -> R.string.health_care_comparison_unknown
        HealthCareComparisonGap.SOURCE_DIFFERS -> R.string.health_care_comparison_source
        HealthCareComparisonGap.REFERENCE_DIFFERS -> R.string.health_care_comparison_reference
        HealthCareComparisonGap.NON_EXACT_RESULT -> R.string.health_care_comparison_not_exact
        HealthCareComparisonGap.CONTEXT_UNCONFIRMED -> R.string.health_care_comparison_context
        HealthCareComparisonGap.CONTEXT_DIFFERS -> R.string.health_care_comparison_context_changed
        HealthCareComparisonGap.METHOD_UNVERIFIED -> R.string.health_care_comparison_method
    }
}

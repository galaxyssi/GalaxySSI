package com.galaxyssi.chat

import android.content.Context
import java.text.DateFormat
import java.util.Date

internal object HealthCareTargetPresentation {
    fun range(context: Context, field: String, low: String?, high: String?, unit: String, lowInclusive: Boolean, highInclusive: Boolean): String {
        val bounds = listOfNotNull(low?.let { "${if (lowInclusive) ">=" else ">"} $it" },
            high?.let { "${if (highInclusive) "<=" else "<"} $it" }).joinToString("; ")
        return "${context.getString(healthFieldResource(field))}: $bounds $unit"
    }
    fun range(context: Context, value: HealthCareTarget) = range(context, value.field, value.low, value.high, value.unit, value.lowInclusive, value.highInclusive)
    fun range(context: Context, value: HealthCareTargetProposal) = range(context, value.field, value.low, value.high, value.unit, value.lowInclusive, value.highInclusive)
    fun status(context: Context, issue: HealthCareConcern) = context.getString(when (HealthCareTargetPolicy.comparison(issue)) {
        HealthCareTargetComparison.REVIEW_REQUIRED -> R.string.health_target_review_required
        HealthCareTargetComparison.NOT_COMPARABLE -> R.string.health_target_not_comparable
        HealthCareTargetComparison.BELOW -> R.string.health_target_below
        HealthCareTargetComparison.WITHIN -> R.string.health_target_within
        HealthCareTargetComparison.ABOVE -> R.string.health_target_above
    })
    fun details(context: Context, issue: HealthCareConcern): String {
        val target = issue.target ?: return context.getString(R.string.health_care_no_target)
        val date = DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT).format(Date(target.confirmedAt))
        return listOf(range(context, target), status(context, issue), target.rationale, target.source,
            context.getString(R.string.health_target_confirmed, date), context.getString(R.string.health_target_scope)).joinToString("\n\n")
    }
    fun planTitle(context: Context, plan: HealthCarePlan) = context.getString(
        if (plan.target == null) R.string.health_care_plan_pending else R.string.health_target_plan_pending, plan.actions.size)
}

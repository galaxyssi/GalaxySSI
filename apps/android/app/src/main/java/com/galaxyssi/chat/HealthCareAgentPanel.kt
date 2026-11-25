package com.galaxyssi.chat

import android.app.Activity
import android.graphics.Typeface
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.style.ForegroundColorSpan
import android.text.style.RelativeSizeSpan
import android.text.style.StyleSpan
import android.widget.LinearLayout

/** Read-only metric and report reference for the same observed record. */
internal class HealthCareAgentPanel(
    activity: Activity,
    metric: HealthMetric,
    assessment: HealthCareAssessment
) : LinearLayout(activity) {
    init {
        val ui = HealthCenterViews(activity)
        orientation = VERTICAL
        tag = "agent-health-care-panel"
        addView(ui.column().apply {
            tag = "agent-health-care-concern"
            setPadding(ui.dp(4), ui.dp(6), ui.dp(4), ui.dp(6))
            addView(ui.text(activity.getString(metric.titleResource()), 16f, bold = true).apply {
                tag = "agent-health-care-metric"
            })
            if (assessment.record != null && assessment.value.isNotBlank()) {
                val unit = assessment.unit.trim()
                val value = listOf(assessment.value.trim(), unit).filter(String::isNotEmpty).joinToString(" ")
                addView(ui.text("", 13f).apply {
                    tag = "agent-health-care-value"
                    text = SpannableStringBuilder(value).apply {
                        val flags = Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
                        setSpan(StyleSpan(Typeface.BOLD), 0, length, flags)
                        val reference = assessment.reportReference.trim()
                        if (reference.isNotEmpty()) {
                            val kind = HealthResult.parse(reference, HealthResultForm.LABORATORY)?.kind
                            val referenceWithUnit = if (unit.isNotEmpty() && kind != null && kind != HealthResultKind.QUALITATIVE)
                                "$reference $unit" else reference
                            val start = length
                            append(activity.getString(R.string.health_agent_report_reference, referenceWithUnit))
                            setSpan(ForegroundColorSpan(activity.getColor(R.color.text_secondary)), start, length, flags)
                            setSpan(RelativeSizeSpan(0.92f), start, length, flags)
                        }
                    }
                })
            }
        }, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT))
    }
}

package com.galaxyssi.chat

import android.app.Activity
import android.widget.LinearLayout

internal fun HealthCenterViews.sourceContext(activity: Activity, value: HealthOcrSourceContext) = column().apply {
    tag = "health-ocr-source-context"
    setPadding(dp(12), dp(10), dp(12), dp(10))
    background = this@sourceContext.background(stroke = activity.getColor(R.color.separator), radius = 8)
    addView(text(activity.getString(R.string.health_ocr_context_title), 15f, bold = true))
    fun lines(values: List<String>, label: Int, missing: Int, key: String) {
        add(this, text(if (values.isEmpty()) activity.getString(missing)
            else activity.getString(label, values.take(3).joinToString("\n")), 14f).apply {
            tag = key
            if (values.isNotEmpty()) setTextIsSelectable(true)
        }, 6)
        if (values.size > 3) add(this, text(activity.getString(R.string.health_ocr_context_more), 13f, muted = true), 4)
    }
    lines(value.owners, R.string.health_ocr_owner_detected, R.string.health_ocr_owner_unknown, "health-ocr-source-owner")
    lines(value.times, R.string.health_ocr_sample_detected, R.string.health_ocr_sample_unknown, "health-ocr-source-time")
}

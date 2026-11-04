package com.galaxyssi.chat

import android.app.Activity
import android.content.res.ColorStateList
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.ImageButton
import android.widget.LinearLayout
import android.widget.TextView

internal class HealthCenterViews(private val activity: Activity) {
    fun dp(value: Int) = (value * activity.resources.displayMetrics.density + .5f).toInt()
    fun column() = LinearLayout(activity).apply { orientation = LinearLayout.VERTICAL }
    fun line() = LinearLayout(activity).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL }
    fun text(value: String, size: Float = 16f, muted: Boolean = false, bold: Boolean = false) = TextView(activity).apply {
        text = value; textSize = size
        setTextColor(activity.getColor(if (muted) R.color.text_secondary else R.color.text_primary))
        if (bold) setTypeface(typeface, Typeface.BOLD)
        setLineSpacing(dp(3).toFloat(), 1f)
    }
    fun background(color: Int = activity.getColor(R.color.surface_bg), stroke: Int? = null, radius: Int = 14) = GradientDrawable().apply {
        setColor(color); cornerRadius = dp(radius).toFloat(); stroke?.let { setStroke(dp(1), it) }
    }
    fun card() = column().apply {
        setPadding(dp(18), dp(18), dp(18), dp(18))
        background = background(stroke = activity.getColor(R.color.separator))
    }
    fun icon(drawable: Int, description: Int, action: () -> Unit) = ImageButton(activity).apply {
        setImageResource(drawable); imageTintList = ColorStateList.valueOf(activity.getColor(R.color.text_primary))
        contentDescription = activity.getString(description); tooltipText = contentDescription
        setBackgroundColor(Color.TRANSPARENT); setPadding(dp(13), dp(13), dp(13), dp(13))
        layoutParams = LinearLayout.LayoutParams(dp(48), dp(48)); setOnClickListener { action() }
    }
    fun command(title: Int, action: () -> Unit) = text(activity.getString(title), 16f, bold = true).apply {
        gravity = Gravity.CENTER; minimumHeight = dp(48)
        background = background(Color.rgb(17, 195, 110), radius = 12)
        setTextColor(Color.rgb(8, 40, 29)); setOnClickListener { action() }
        isFocusable = true
    }
    fun row(title: String, subtitle: String = "", action: () -> Unit) = line().apply {
        minimumHeight = dp(72); setPadding(dp(4), dp(12), dp(4), dp(12))
        addView(column().apply {
            addView(text(title, bold = true))
            if (subtitle.isNotBlank()) addView(text(subtitle, 13f, muted = true))
        }, LinearLayout.LayoutParams(0, -2, 1f))
        addView(text("\u203a", 24f, muted = true))
        setOnClickListener { action() }; isFocusable = true
    }
    fun space(height: Int) = View(activity).apply { layoutParams = LinearLayout.LayoutParams(1, dp(height)) }
    fun add(parent: LinearLayout, view: View, top: Int = 0) {
        parent.addView(view, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, -2).apply { topMargin = dp(top) })
    }
}

internal fun HealthMetric.titleResource(): Int = when (this) {
    HealthMetric.BLOOD_PRESSURE -> R.string.health_blood_pressure
    HealthMetric.GLUCOSE -> R.string.health_glucose
    HealthMetric.WEIGHT -> R.string.health_weight
    HealthMetric.HEART_RATE -> R.string.health_heart_rate
}

internal fun healthFieldResource(field: String): Int = when (field) {
    "systolic" -> R.string.health_systolic
    "diastolic" -> R.string.health_diastolic
    "pulse" -> R.string.health_pulse
    "glucose" -> R.string.health_glucose
    else -> R.string.health_weight
}

internal fun healthContextResource(value: String): Int = when (value) {
    "resting" -> R.string.health_resting
    "after_exercise" -> R.string.health_after_exercise
    "fasting" -> R.string.health_fasting
    "after_meal" -> R.string.health_after_meal
    "other" -> R.string.health_other
    "left" -> R.string.health_left
    "right" -> R.string.health_right
    else -> R.string.health_unspecified
}

package com.galaxyssi.chat

import android.content.res.ColorStateList
import android.text.Spannable
import android.text.SpannableStringBuilder
import android.text.style.ForegroundColorSpan
import android.text.style.RelativeSizeSpan
import android.view.Gravity
import android.view.View
import android.widget.ImageView
import android.widget.LinearLayout
import java.text.NumberFormat

internal class HealthOverviewMetricView(private val activity: HealthCenterActivity) {
    private val ui get() = activity.ui
    private fun label(id: Int, vararg args: Any) = activity.getString(id, *args)
    private fun color(id: Int) = activity.getColor(id)

    fun row(item: HealthOverviewMetric, openRecord: (HealthObservation) -> Unit): LinearLayout {
        val record = item.record
        val draft = record?.draft
        val metric = item.metric
        val status = item.ranges.firstOrNull { it.outside }
            ?: item.ranges.firstOrNull { it.position == HealthOverviewRangePosition.NOT_COMPARABLE }
            ?: item.ranges.firstOrNull()
        val title = label(if (metric == HealthMetric.GLUCOSE && draft?.condition == "fasting")
            R.string.health_overview_fasting_glucose else metric.titleResource())
        val spacious = activity.resources.configuration.fontScale >= 1.25f
        val icon = when (metric) {
            HealthMetric.BLOOD_PRESSURE, HealthMetric.HEART_RATE, HealthMetric.RESTING_HEART_RATE -> R.drawable.ic_health_heart
            HealthMetric.SLEEP_DURATION -> R.drawable.ic_conversation_paused
            HealthMetric.STEPS -> R.drawable.ic_health_data_chart
            else -> R.drawable.ic_avatar_lab
        }
        val details = ui.column().apply {
            tag = "health-overview-detail-${metric.name}"
            visibility = View.GONE
            setPadding(0, ui.dp(4), 0, ui.dp(7))
            if (record != null) {
                addView(ui.row(label(R.string.health_overview_record_detail)) { openRecord(record) }.apply { minimumHeight = ui.dp(48) })
                addView(ui.row(label(R.string.health_overview_metric_history)) { activity.open("metric_records", metric) }.apply { minimumHeight = ui.dp(48) })
            }
        }
        val arrow = ImageView(activity).apply {
            setImageResource(if (record == null) R.drawable.ic_arrow_right else R.drawable.ic_chevron_down)
            imageTintList = ColorStateList.valueOf(color(R.color.text_secondary))
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
        }
        val header = ui.column().apply {
            tag = "health-overview-${metric.name}-${item.freshness.name}"
            setPadding(0, ui.dp(10), 0, ui.dp(10))
            minimumHeight = ui.dp(50)
            isFocusable = true
            setOnClickListener {
                if (record == null) activity.open("manual", metric) else {
                    val expanded = details.visibility != View.VISIBLE
                    details.visibility = if (expanded) View.VISIBLE else View.GONE
                    arrow.rotation = if (expanded) 180f else 0f
                }
            }
            val name = ui.line().apply {
                addView(ImageView(activity).apply {
                    setImageResource(icon)
                    imageTintList = ColorStateList.valueOf(color(R.color.health_overview_green))
                    importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
                }, LinearLayout.LayoutParams(ui.dp(18), ui.dp(18)).apply { marginEnd = ui.dp(7) })
                addView(ui.text(title, 15f, bold = true), LinearLayout.LayoutParams(0, -2, 1f))
            }
            val value = ui.text("", 22f, bold = true).apply {
                text = draft?.let { reading(it, item.ranges) } ?: label(R.string.health_overview_no_value)
                tag = "health-overview-value-${metric.name}"
                gravity = Gravity.END
                setPadding(ui.dp(4), 0, ui.dp(5), 0)
            }
            addView(ui.line().apply {
                addView(name, LinearLayout.LayoutParams(0, -2, 1f))
                if (!spacious) addView(value, LinearLayout.LayoutParams(0, -2, 1f))
                addView(arrow, LinearLayout.LayoutParams(ui.dp(14), ui.dp(14)))
            })
            if (spacious) addView(value, LinearLayout.LayoutParams(-1, -2))
            if (record != null) {
                val timing = label(R.string.health_overview_source, activity.date(record.draft.measuredAt),
                    label(healthRecordSourceResource(record.source)))
                val source = ui.text(timing, 12f).apply { setTextColor(color(R.color.health_overview_muted)) }
                val state = ui.text(status?.let { statusText(it, metric) } ?: label(R.string.health_overview_no_range), 12f, bold = true).apply {
                    tag = "health-overview-status-${metric.name}"
                    setTextColor(color(ink(status?.position, muted = true)))
                    gravity = Gravity.END
                }
                ui.add(this, if (spacious) ui.column().apply { addView(source); addView(state, LinearLayout.LayoutParams(-1, -2)) }
                else ui.line().apply {
                    addView(source, LinearLayout.LayoutParams(0, -2, 1f).apply { marginEnd = ui.dp(6) })
                    addView(state, LinearLayout.LayoutParams(0, -2, 1f))
                }, 4)
                item.ranges.forEach { bound ->
                    val field = if (metric.requiredFields.size > 1) "${label(healthFieldResource(bound.field))} " else ""
                    ui.add(this, ui.text(label(R.string.health_overview_range_line, label(bound.source.title()),
                        "$field${bound.bounds} ${bound.unit}"), 13f).apply { tag = "health-overview-range-${metric.name}" }, 6)
                }
            } else ui.add(this, ui.text(label(R.string.health_overview_unrecorded), 12f, muted = true), 4)
        }
        return ui.column().apply {
            addView(header)
            addView(details)
            addView(View(activity).apply { setBackgroundColor(color(R.color.separator)) }, LinearLayout.LayoutParams(-1, ui.dp(1)))
        }
    }

    private fun reading(draft: HealthDraft, ranges: List<HealthOverviewRange>) = SpannableStringBuilder().apply {
        draft.metric.requiredFields.forEachIndexed { index, field ->
            if (index != 0) append("/")
            val raw = draft.reportedValues[field] ?: draft.values[field].orEmpty()
            val position = ranges.firstOrNull { it.field == field && it.outside }?.position
                ?: ranges.firstOrNull { it.field == field }?.position
            val from = length
            append(if (draft.metric == HealthMetric.STEPS) raw.toLongOrNull()?.let { NumberFormat.getIntegerInstance().format(it) } ?: raw
                else raw)
            if (length > from) setSpan(ForegroundColorSpan(color(ink(position))), from, length, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE)
        }
        if (draft.unit.isNotBlank()) {
            val from = length
            append(" ").append(if (draft.metric == HealthMetric.STEPS) label(R.string.health_overview_steps_unit) else draft.unit)
            setSpan(RelativeSizeSpan(0.58f), from, length, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE)
            setSpan(ForegroundColorSpan(color(R.color.health_overview_muted)), from, length, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE)
        }
    }

    private fun ink(position: HealthOverviewRangePosition?, muted: Boolean = false) = when (position) {
        HealthOverviewRangePosition.WITHIN -> R.color.health_overview_green
        HealthOverviewRangePosition.ABOVE, HealthOverviewRangePosition.BELOW -> R.color.health_overview_orange
        else -> if (muted) R.color.health_overview_muted else R.color.text_primary
    }

    private fun statusText(range: HealthOverviewRange, metric: HealthMetric): String {
        val comparison = label(when (range.position) {
            HealthOverviewRangePosition.BELOW -> R.string.health_overview_range_below
            HealthOverviewRangePosition.WITHIN -> R.string.health_overview_range_within
            HealthOverviewRangePosition.ABOVE -> R.string.health_overview_range_above
            HealthOverviewRangePosition.NOT_COMPARABLE -> return label(R.string.health_overview_range_not_comparable)
        }, label(range.source.title()))
        return if (metric.requiredFields.size > 1) "${label(healthFieldResource(range.field))} $comparison" else comparison
    }

    private fun HealthOverviewRangeSource.title() = when (this) {
        HealthOverviewRangeSource.REPORT -> R.string.health_overview_report_range
        HealthOverviewRangeSource.RECORD -> R.string.health_overview_record_range
        HealthOverviewRangeSource.CONFIRMED_TARGET -> R.string.health_overview_confirmed_target
    }
}

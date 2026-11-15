package com.galaxyssi.chat

import android.content.Intent
import android.content.res.ColorStateList
import android.net.Uri
import android.text.Spannable
import android.text.SpannableStringBuilder
import android.text.style.ForegroundColorSpan
import android.text.style.RelativeSizeSpan
import android.view.Gravity
import android.view.View
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import java.text.NumberFormat
import java.time.LocalDate

internal class HealthOverviewMetricView(private val activity: HealthCenterActivity) {
    private val ui get() = activity.ui
    private fun label(id: Int, vararg args: Any) = activity.getString(id, *args)
    private fun color(id: Int) = activity.getColor(id)
    private data class Reference(val lines: List<Int>, val detail: Int, val source: Int, val url: String)

    fun row(item: HealthOverviewMetric, openRecord: (HealthObservation) -> Unit,
        bindSteps: (((HealthPhoneStepReading?, Boolean) -> Unit) -> Unit) = {}): LinearLayout {
        val record = item.record
        val draft = record?.draft
        val metric = item.metric
        val reference = reference(item)
        val canExpand = record != null || reference != null
        val status = item.ranges.firstOrNull { it.outside }
            ?: item.ranges.firstOrNull { it.position == HealthOverviewRangePosition.NOT_COMPARABLE }
            ?: item.ranges.firstOrNull()
        val title = label(when {
            metric == HealthMetric.STEPS -> R.string.health_overview_today_steps
            metric == HealthMetric.GLUCOSE && draft?.condition == "fasting" -> R.string.health_overview_fasting_glucose
            else -> metric.titleResource()
        })
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
            } else if (reference != null) {
                addView(ui.row(label(R.string.health_manual)) { activity.open("manual", metric) }.apply { minimumHeight = ui.dp(48) })
            }
            if (reference != null) {
                ui.add(this, ui.text(label(reference.detail), 12f, muted = true), 4)
                addView(ui.row(label(reference.source)) {
                    runCatching { activity.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(reference.url))) }
                        .onFailure { Toast.makeText(activity, R.string.health_overview_reference_no_browser, Toast.LENGTH_SHORT).show() }
                }.apply { minimumHeight = ui.dp(48) })
            }
        }
        val arrow = ImageView(activity).apply {
            setImageResource(if (canExpand) R.drawable.ic_chevron_down else R.drawable.ic_arrow_right)
            imageTintList = ColorStateList.valueOf(color(R.color.text_secondary))
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
        }
        val staleSteps = metric == HealthMetric.STEPS && item.freshness != HealthOverviewFreshness.RECENT
        val storedValue = draft?.takeUnless { staleSteps }?.let { reading(it, item.ranges) } ?: label(R.string.health_overview_no_value)
        val value = ui.text("", 22f, bold = true).apply {
            text = storedValue
            tag = "health-overview-value-${metric.name}"
            gravity = Gravity.END
            setPadding(ui.dp(4), 0, ui.dp(5), 0)
        }
        val recordMetadata = ui.column()
        val header = ui.column().apply {
            tag = "health-overview-${metric.name}-${item.freshness.name}"
            setPadding(0, ui.dp(10), 0, ui.dp(10))
            minimumHeight = ui.dp(50)
            isFocusable = true
            setOnClickListener {
                if (!canExpand) activity.open("manual", metric) else {
                    val expanded = details.visibility != View.VISIBLE
                    details.visibility = if (expanded) View.VISIBLE else View.GONE
                    arrow.rotation = if (expanded) 180f else 0f
                }
            }
            addHealthOverviewHeadline(activity, title, icon, value, arrow)
            if (record != null && !staleSteps) {
                val timing = label(R.string.health_overview_source, activity.date(record.draft.measuredAt),
                    label(healthRecordSourceResource(record.source)))
                val source = ui.text(timing, 12f).apply { setTextColor(color(R.color.health_overview_muted)) }
                val statusLabel = status?.let { statusText(it, metric) }
                    ?: label(R.string.health_overview_no_range).takeIf { reference == null && metric != HealthMetric.STEPS }
                val state = statusLabel?.let { ui.text(it, 12f, bold = true).apply {
                    tag = "health-overview-status-${metric.name}"
                    setTextColor(color(ink(status?.position, muted = true)))
                    gravity = Gravity.END
                } }
                ui.add(recordMetadata, if (state == null) source
                else if (spacious) ui.column().apply { addView(source); addView(state, LinearLayout.LayoutParams(-1, -2)) }
                else ui.line().apply {
                    addView(source, LinearLayout.LayoutParams(0, -2, 1f).apply { marginEnd = ui.dp(6) })
                    addView(state, LinearLayout.LayoutParams(0, -2, 1f))
                }, 4)
                item.ranges.forEach { bound ->
                    val field = if (metric.requiredFields.size > 1) "${label(healthFieldResource(bound.field))} " else ""
                    ui.add(recordMetadata, ui.text(label(R.string.health_overview_range_line, label(bound.source.title()),
                        "$field${bound.bounds} ${bound.unit}"), 13f).apply { tag = "health-overview-range-${metric.name}" }, 6)
                }
            } else ui.add(recordMetadata, ui.text(label(if (staleSteps) R.string.health_overview_no_today_steps
                else R.string.health_overview_unrecorded), 12f, muted = true), 4)
            addView(recordMetadata)
            if (reference != null) ui.add(this, ui.text(reference.lines.joinToString("\n") { label(it) }, 13f, muted = true)
                .apply { tag = "health-overview-reference-${metric.name}" }, 6)
        }
        return ui.column().apply {
            addView(header)
            if (metric == HealthMetric.STEPS) {
                val button = ui.text("", 13f, bold = true).apply {
                    gravity = Gravity.CENTER_VERTICAL
                    minimumHeight = ui.dp(48)
                    tag = "health-overview-phone-steps"
                    visibility = View.GONE
                }
                addView(button)
                val progress = ui.text("", 12f, muted = true)
                addView(stepGoal(item, progress))
                bindSteps { phone, supported ->
                    val day = LocalDate.now()
                    val ledger = phone?.ledger
                    val steps = ledger?.takeIf { it.day == day || phone?.active == true }?.today(day)?.total
                    value.text = steps?.let {
                        SpannableStringBuilder(NumberFormat.getIntegerInstance().format(it)).apply {
                            appendReadingUnit(label(R.string.health_overview_steps_unit))
                        }
                    } ?: storedValue
                    recordMetadata.visibility = if (steps == null) View.VISIBLE else View.GONE
                    button.visibility = View.VISIBLE
                    button.setText(when {
                        !supported -> R.string.health_phone_steps_unsupported
                        phone?.failed == true -> R.string.health_phone_steps_retry
                        phone?.active == true -> R.string.health_phone_steps_counting
                        steps != null -> R.string.health_phone_steps_paused
                        else -> R.string.health_phone_steps_enable
                    })
                    button.setTextColor(color(if (supported) R.color.health_overview_green else R.color.health_overview_muted))
                    button.setOnClickListener(if (supported) View.OnClickListener { activity.editPhoneSteps() } else null)
                    button.isClickable = supported
                    button.isFocusable = supported
                    val ratio = if (steps == null) item.stepProgress else HealthOverviewGuidance.stepProgress(item.stepGoal,
                        steps, HealthOverviewFreshness.RECENT, item.stepProgressPermitted)
                    updateStepProgress(progress, ratio)
                }
            }
            addView(details)
            addView(View(activity).apply { setBackgroundColor(color(R.color.separator)) }, LinearLayout.LayoutParams(-1, ui.dp(1)))
        }
    }

    private fun stepGoal(item: HealthOverviewMetric, progress: android.widget.TextView): View {
        val goal = item.stepGoal
        val target = goal?.let { label(R.string.health_overview_step_goal_value, NumberFormat.getIntegerInstance().format(it)) }
            ?: label(R.string.health_overview_step_goal_set)
        updateStepProgress(progress, item.stepProgress)
        return ui.line().apply {
            tag = "health-overview-step-goal"
            minimumHeight = ui.dp(48)
            setPadding(0, 0, 0, ui.dp(6))
            isFocusable = true
            setOnClickListener { activity.editOverviewStepGoal(goal) }
            addView(ui.column().apply {
                addView(ui.text(target, 13f, bold = true).apply { setTextColor(color(R.color.health_overview_green)) })
                addView(progress)
            }, LinearLayout.LayoutParams(0, -2, 1f))
            addView(ImageView(activity).apply {
                setImageResource(R.drawable.ic_arrow_right)
                imageTintList = ColorStateList.valueOf(color(R.color.text_secondary))
                importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
            }, LinearLayout.LayoutParams(ui.dp(14), ui.dp(14)))
        }
    }

    private fun updateStepProgress(view: android.widget.TextView, ratio: Double?) {
        view.visibility = if (ratio == null) View.GONE else View.VISIBLE
        view.tag = if (ratio == null) null else "health-overview-step-progress"
        view.text = ratio?.let { label(R.string.health_overview_step_goal_progress, NumberFormat.getPercentInstance().format(it)) }.orEmpty()
    }

    private fun reference(item: HealthOverviewMetric) = when (item.metric) {
        HealthMetric.BLOOD_PRESSURE -> if (item.showAdultReference) Reference(
            listOf(R.string.health_overview_bp_home, R.string.health_overview_bp_office),
            R.string.health_overview_bp_detail, R.string.health_overview_bp_source,
            "https://cs.medjournals.cn/article/doi/full/10.3760/cma.j.cn112148-20250401-00234") else null
        HealthMetric.RESTING_HEART_RATE -> if (item.showAdultReference) Reference(
            listOf(R.string.health_overview_resting_reference), R.string.health_overview_resting_detail, R.string.health_overview_resting_source,
            "https://www.heart.org/en/health-topics/high-blood-pressure/the-facts-about-high-blood-pressure/all-about-heart-rate-pulse") else null
        HealthMetric.SLEEP_DURATION -> Reference(listOf(when (item.sleepBand) {
            HealthOverviewGuidance.SleepBand.ADULT_UNSPECIFIED -> R.string.health_overview_sleep_adult
            HealthOverviewGuidance.SleepBand.MONTHS_0_3 -> R.string.health_overview_sleep_0_3m
            HealthOverviewGuidance.SleepBand.MONTHS_4_12 -> R.string.health_overview_sleep_4_12m
            HealthOverviewGuidance.SleepBand.YEARS_1_2 -> R.string.health_overview_sleep_1_2
            HealthOverviewGuidance.SleepBand.YEARS_3_5 -> R.string.health_overview_sleep_3_5
            HealthOverviewGuidance.SleepBand.YEARS_6_12 -> R.string.health_overview_sleep_6_12
            HealthOverviewGuidance.SleepBand.YEARS_13_17 -> R.string.health_overview_sleep_13_17
            HealthOverviewGuidance.SleepBand.YEARS_18_60 -> R.string.health_overview_sleep_18_60
            HealthOverviewGuidance.SleepBand.YEARS_61_64 -> R.string.health_overview_sleep_61_64
            HealthOverviewGuidance.SleepBand.YEARS_65_PLUS -> R.string.health_overview_sleep_65_plus
        }), R.string.health_overview_sleep_detail, R.string.health_overview_sleep_source, "https://www.cdc.gov/sleep/about/")
        else -> null
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
            appendReadingUnit(if (draft.metric == HealthMetric.STEPS) label(R.string.health_overview_steps_unit) else draft.unit)
        }
    }

    private fun SpannableStringBuilder.appendReadingUnit(unit: String) {
        val from = length
        append(" ").append(unit)
        setSpan(RelativeSizeSpan(0.58f), from, length, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE)
        setSpan(ForegroundColorSpan(color(R.color.health_overview_muted)), from, length, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE)
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

internal fun LinearLayout.addHealthOverviewHeadline(activity: HealthCenterActivity, title: String, icon: Int,
    amount: TextView, arrow: ImageView) {
    val ui = activity.ui
    val spacious = activity.resources.configuration.fontScale >= 1.25f
    addView(ui.line().apply {
        addView(ui.line().apply {
            addView(ImageView(activity).apply {
                setImageResource(icon)
                imageTintList = ColorStateList.valueOf(activity.getColor(R.color.health_overview_green))
                importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
            }, LinearLayout.LayoutParams(ui.dp(18), ui.dp(18)).apply { marginEnd = ui.dp(7) })
            addView(ui.text(title, 15f, bold = true), LinearLayout.LayoutParams(0, -2, 1f))
        }, LinearLayout.LayoutParams(0, -2, 1f))
        if (!spacious) addView(amount, LinearLayout.LayoutParams(0, -2, 1f))
        addView(arrow, LinearLayout.LayoutParams(ui.dp(14), ui.dp(14)))
    })
    if (spacious) addView(amount, LinearLayout.LayoutParams(-1, -2))
}

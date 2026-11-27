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

    fun row(item: HealthOverviewMetric, caption: String? = null, open: () -> Unit): LinearLayout {
        val metric = item.metric
        val record = item.record
        val reference = reference(item)
        val status = item.ranges.firstOrNull { it.outside }
            ?: item.ranges.firstOrNull { it.position == HealthOverviewRangePosition.NOT_COMPARABLE }
            ?: item.ranges.firstOrNull()
        return ui.column().apply {
            tag = "health-overview-${metric.name}-${item.freshness.name}"
            setTag(R.id.healthReadingKey, record?.id ?: metric.name)
            setPadding(ui.dp(12), ui.dp(8), ui.dp(10), ui.dp(8))
            minimumHeight = ui.dp(52)
            isFocusable = true
            setOnClickListener { open() }
            addHealthOverviewHeadline(activity, title(item), glyph(metric), ui.text("", 18f, bold = true).apply {
                text = record?.let { reading(it.draft, item.ranges) } ?: label(R.string.health_overview_no_value)
                tag = "health-overview-value-${metric.name}"
                gravity = Gravity.END
                setPadding(ui.dp(4), 0, ui.dp(4), 0)
            }, arrow())
            val range = item.ranges.firstOrNull { it.source == status?.source }
            val references = if (range == null) reference?.lines?.joinToString("\n") { label(it) } else null
            val basis = when {
                range != null -> rangeText(item.ranges.filter { it.source == range.source }, metric)
                references != null -> references
                record == null -> label(R.string.health_overview_unrecorded)
                else -> label(R.string.health_overview_no_range)
            }
            val basisLabel = ui.text(basis, 12f, muted = true).apply {
                if (range != null) tag = "health-overview-range-${metric.name}"
                else if (references != null) tag = "health-overview-reference-${metric.name}"
            }
            val state = status?.let { bound ->
                ui.text(statusText(bound, metric), 12f, bold = bound.outside).apply {
                    tag = "health-overview-status-${metric.name}"
                    setTextColor(color(ink(bound.position, muted = true)))
                    gravity = Gravity.END
                }
            }
            val config = activity.resources.configuration
            if (state == null) ui.add(this, basisLabel, 3)
            else if (config.fontScale >= 1.25f || config.screenWidthDp < 345) {
                ui.add(this, basisLabel, 3)
                addView(state, LinearLayout.LayoutParams(-1, -2))
            } else ui.add(this, ui.line().apply {
                gravity = Gravity.TOP
                addView(basisLabel, LinearLayout.LayoutParams(0, -2, 1.25f).apply { marginEnd = ui.dp(5) })
                addView(state, LinearLayout.LayoutParams(0, -2, 1f))
            }, 3)
            if (!caption.isNullOrBlank()) ui.add(this, ui.text(caption, 11f, muted = true), 3)
        }
    }

    fun showDetail(content: LinearLayout, detail: HealthOverviewMetricDetail) {
        val item = detail.metric
        val record = item.record
        val ref = reference(item)
        content.addView(ui.column().apply {
            tag = "health-overview-detail-${item.metric.name}"
            if (record == null) {
                addView(ui.text(label(R.string.health_overview_unrecorded), 14f, muted = true))
            } else {
                addView(ui.text("", 30f, bold = true).apply { text = reading(record.draft, item.ranges) })
                ui.add(this, ui.text(label(R.string.health_overview_source, activity.date(record.draft.measuredAt),
                    label(healthRecordSourceResource(record.source))), 13f, muted = true), 3)
                val condition = record.draft.condition
                if (item.metric == HealthMetric.GLUCOSE && condition.isNotBlank()) {
                    ui.add(this, ui.text(label(healthContextResource(condition)), 13f, muted = true), 2)
                }
            }
            item.ranges.groupBy { it.source }.values.forEach { bounds ->
                ui.add(this, ui.text(rangeText(bounds, item.metric), 14f), 8)
                bounds.forEach { bound ->
                    ui.add(this, ui.text(statusText(bound, item.metric), 13f).apply {
                        setTextColor(color(ink(bound.position, muted = true)))
                    }, 3)
                }
            }
            if (ref != null) {
                ui.add(this, ui.text(ref.lines.joinToString("\n") { label(it) }, 13f, muted = true), 10)
                ui.add(this, ui.text(label(ref.detail), 12f, muted = true), 4)
                addView(detailLink(ref.source) {
                    runCatching { activity.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(ref.url))) }
                        .onFailure { Toast.makeText(activity, R.string.health_overview_reference_no_browser, Toast.LENGTH_SHORT).show() }
                })
            }
        })
        if (detail.recent.isNotEmpty()) {
            record?.let { observed -> content.addView(detailLink(R.string.health_measurement_continuous) { activity.metricTrend(observed) }) }
            ui.add(content, ui.text(label(R.string.health_overview_recent_records), 15f, bold = true), 14)
            detail.recent.forEach { previous ->
                content.addView(ui.line().apply {
                    minimumHeight = ui.dp(48)
                    setOnClickListener { activity.open("detail", previous.draft.metric, previous.id) }
                    isFocusable = true
                    addView(ui.text(activity.date(previous.draft.measuredAt), 12f, muted = true),
                        LinearLayout.LayoutParams(0, -2, 1f))
                    addView(ui.text(healthDisplayValue(previous.draft), 14f, bold = true).apply { gravity = Gravity.END },
                        LinearLayout.LayoutParams(0, -2, 1f))
                    addView(arrow(), LinearLayout.LayoutParams(ui.dp(15), ui.dp(15)))
                })
                content.addView(healthOverviewDivider(activity))
            }
            content.addView(detailLink(R.string.health_overview_metric_history) { activity.open("overview_history", item.metric) })
        }
        if (item.outsideRange) {
            ui.add(content, ui.text(label(R.string.health_overview_compare_note), 13f, muted = true).apply {
                tag = "health-overview-compare-note"
            }, 10)
        }
        detail.concernId?.let { id ->
            content.addView(detailLink(R.string.health_overview_discuss_metric) { activity.openOverviewDiscussion(item.metric, id) })
        }
        if (record == null) ui.add(content, ui.command(R.string.health_manual) { activity.open("manual", item.metric) }, 12)
    }

    fun stepTile(item: HealthOverviewMetric, bind: (((HealthPhoneStepReading?, Boolean) -> Unit) -> Unit)): View {
        val staleSteps = item.freshness != HealthOverviewFreshness.RECENT
        val storedValue = item.record?.draft?.takeUnless { staleSteps }?.let { reading(it, item.ranges) }
            ?: label(R.string.health_overview_no_value)
        val value = ui.text("", 18f, bold = true).apply {
            text = storedValue
            tag = "health-overview-value-STEPS"
        }
        val goal = item.stepGoal
        val goalLink = ui.text(goal?.let { label(R.string.health_overview_step_goal_value, NumberFormat.getIntegerInstance().format(it)) }
            ?: label(R.string.health_overview_step_goal_set), 12f, muted = true).apply {
            tag = "health-overview-step-goal"
            minimumHeight = ui.dp(44)
            gravity = Gravity.CENTER_VERTICAL
            isFocusable = true
            setOnClickListener { activity.editOverviewStepGoal(goal) }
        }
        val progress = ui.text("", 12f, muted = true)
        val tile = healthOverviewActivityTile(activity, R.string.health_overview_today_steps, R.drawable.ic_health_data_chart,
            value, goalLink).apply {
            tag = "health-overview-STEPS-${item.freshness.name}"
            addView(progress)
        }
        updateStepProgress(progress, item.stepProgress)
        bind { phone, supported ->
            val day = LocalDate.now()
            val steps = phone?.ledger?.takeIf { it.day == day || phone?.active == true }?.today(day)?.total
            value.text = steps?.let {
                SpannableStringBuilder(NumberFormat.getIntegerInstance().format(it)).apply {
                    appendReadingUnit(label(R.string.health_overview_steps_unit))
                }
            } ?: storedValue
            tile.setOnClickListener(if (supported) View.OnClickListener { activity.editPhoneSteps() } else null)
            tile.isClickable = supported
            tile.isFocusable = supported
            val state = label(when {
                !supported -> R.string.health_phone_steps_unsupported
                phone?.failed == true -> R.string.health_phone_steps_retry
                phone?.active == true -> R.string.health_phone_steps_counting
                steps != null -> R.string.health_phone_steps_paused
                else -> R.string.health_phone_steps_enable
            })
            tile.contentDescription = label(R.string.health_overview_source, value.text, state)
            updateStepProgress(progress, if (steps == null) item.stepProgress
                else HealthOverviewGuidance.stepProgress(item.stepGoal, steps, HealthOverviewFreshness.RECENT, item.stepProgressPermitted))
        }
        return tile
    }

    private fun detailLink(resource: Int, action: () -> Unit) = ui.text(label(resource), 14f).apply {
        setTextColor(color(R.color.health_overview_green))
        minimumHeight = ui.dp(48)
        gravity = Gravity.CENTER_VERTICAL
        isFocusable = true
        setOnClickListener { action() }
    }

    private fun arrow() = ImageView(activity).apply {
        setImageResource(R.drawable.ic_arrow_right)
        imageTintList = ColorStateList.valueOf(color(R.color.text_secondary))
        importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
    }

    private fun title(item: HealthOverviewMetric) =
        label(if (item.metric == HealthMetric.GLUCOSE && item.record?.draft?.condition == "fasting")
            R.string.health_overview_fasting_glucose else item.metric.titleResource())

    private fun glyph(metric: HealthMetric) = when (metric) {
        HealthMetric.BLOOD_PRESSURE, HealthMetric.HEART_RATE, HealthMetric.RESTING_HEART_RATE -> R.drawable.ic_health_heart
        HealthMetric.SLEEP_DURATION -> R.drawable.ic_conversation_paused
        else -> R.drawable.ic_avatar_lab
    }

    private fun rangeText(ranges: List<HealthOverviewRange>, metric: HealthMetric) =
        label(R.string.health_overview_range_line, label(ranges.first().source.title()), ranges.joinToString(" / ") { bound ->
            val field = if (metric.requiredFields.size > 1) "${label(healthFieldResource(bound.field))} " else ""
            "$field${bound.bounds} ${bound.unit}"
        })

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
    val spacious = activity.resources.configuration.let { it.fontScale >= 1.25f || it.screenWidthDp < 344 }
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

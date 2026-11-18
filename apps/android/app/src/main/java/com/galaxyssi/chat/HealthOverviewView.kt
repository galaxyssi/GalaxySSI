package com.galaxyssi.chat

import android.content.Intent
import android.content.res.ColorStateList
import android.view.Gravity
import android.view.View
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.CheckBox
import java.text.DateFormat
import java.util.Date

internal class HealthOverviewView(private val activity: HealthCenterActivity, private val names: HealthOverviewDatabases) {
    private val ui get() = activity.ui
    private val metricView = HealthOverviewMetricView(activity)
    private var stepBinding: ((HealthPhoneStepReading?, Boolean) -> Unit)? = null
    private var recordList: HealthOverviewRecordsView? = null
    private var recordFilter = ""
    private var recordAfter: HealthPageCursor? = null
    private var recordHistory = emptyList<HealthPageCursor?>()

    fun clearTodaySteps() {
        stepBinding = null
        recordList?.let { recordAfter = it.cursor; recordHistory = it.history; it.clear() }
        recordList = null
    }
    fun updatePhoneSteps(reading: HealthPhoneStepReading?, supported: Boolean) { stepBinding?.invoke(reading, supported) }
    private fun label(id: Int, vararg args: Any) = activity.getString(id, *args)
    private fun color(id: Int) = activity.getColor(id)
    private fun start(type: Class<*>, extras: Intent.() -> Unit = {}) {
        if (names.fixture == null) activity.startActivity(Intent(activity, type).apply(extras))
    }
    fun show(content: LinearLayout, snapshot: HealthOverviewSnapshot) {
        content.removeAllViews()
        val today = DateFormat.getDateInstance(DateFormat.MEDIUM).format(Date(snapshot.time))
        content.addView(ui.line().apply {
            tag = "health-overview-date-actions"
            addView(ui.text(today, 12f, muted = true), LinearLayout.LayoutParams(0, -2, 1f))
            addView(ui.text(label(R.string.health_activity_comparison) + " \u203a", 13f).apply {
                tag = "health-activity-comparison"; minimumHeight = ui.dp(48)
                gravity = Gravity.CENTER_VERTICAL or Gravity.END; isFocusable = true
                setTextColor(color(R.color.health_overview_green)); setPadding(ui.dp(8), 0, 0, 0)
                setOnClickListener { activity.startActivity(Intent(activity, HealthActivityComparisonActivity::class.java).putHealthNavigationFixture(names)) }
            })
        })
        val steps = snapshot.metrics.single { it.metric == HealthMetric.STEPS }
        val stepTile = metricView.stepTile(steps) { stepBinding = it }
        val cyclingTile = activity.cyclingTile()
        val config = activity.resources.configuration
        val stackActivity = config.fontScale >= 1.3f || config.screenWidthDp < 344
        ui.add(content, (if (stackActivity) ui.column() else ui.line()).apply {
            tag = "health-overview-activity"
            if (stackActivity) {
                addView(stepTile)
                ui.add(this, cyclingTile, 8)
            } else {
                gravity = Gravity.TOP
                addView(stepTile, LinearLayout.LayoutParams(0, -1, 1f).apply { marginEnd = ui.dp(8) })
                addView(cyclingTile, LinearLayout.LayoutParams(0, -1, 1f))
            }
        }, 12)
        if (!snapshot.hasRecords) {
            ui.add(content, ui.text(label(R.string.health_no_records), 12f, muted = true).apply {
                tag = "health-overview-empty"
            }, 12)
        }
        ui.add(content, ui.line().apply {
            addView(ui.text(label(R.string.health_overview_metrics_heading), 16f, bold = true),
                LinearLayout.LayoutParams(0, -2, 1f))
            addView(ui.text(activity.measurementPeriod?.label(activity) ?: label(R.string.health_measurement_latest), 13f).apply {
                minimumHeight = ui.dp(48); gravity = Gravity.CENTER_VERTICAL or Gravity.END; isFocusable = true
                setPadding(ui.dp(8), ui.dp(4), ui.dp(8), ui.dp(4))
                background = ui.background(color(R.color.button_soft), stroke = color(R.color.separator), radius = 8)
                tag = "health-measurement-period-filter"; setOnClickListener { activity.chooseMeasurementPeriod() }
            }, LinearLayout.LayoutParams(0, -2, 1.2f))
        }, 12)
        ui.add(content, ui.line().apply {
            addView(CheckBox(activity).apply {
                tag = "health-measurement-abnormal-filter"; text = label(R.string.health_period_abnormal); textSize = 13f
                setTextColor(color(R.color.text_primary)); isChecked = activity.measurementAbnormal; isEnabled = snapshot.measurementComparisonAllowed
                setOnCheckedChangeListener { _, checked -> activity.filterMeasurementAbnormal(checked) }
            }, LinearLayout.LayoutParams(0, -2, 1f))
            addView(ui.text(label(R.string.health_period_comparison), 13f).apply {
                minimumHeight = ui.dp(48); gravity = Gravity.CENTER_VERTICAL or Gravity.END; isFocusable = true
                isEnabled = snapshot.measurementComparisonAllowed; alpha = if (isEnabled) 1f else .45f
                setTextColor(color(R.color.health_overview_green)); tag = "health-measurement-compare"
                setOnClickListener { activity.compareMeasurements() }
            })
        }, 4)
        val summaries = snapshot.measurementSeries.associateBy { it.latest.id }
        val measurements = snapshot.metrics.filterNot { it.metric == HealthMetric.STEPS }
        val filtered = measurements.filter { !activity.measurementAbnormal || it.outsideRange || (summaries[it.record?.id]?.outsideCount ?: 0) > 0 }
        val highlighted = filtered.filter { it.outsideRange || (summaries[it.record?.id]?.outsideCount ?: 0) > 0 }
        val preview = highlighted + filtered.filterNot { it in highlighted }.sortedByDescending { it.record != null }
            .take((5 - highlighted.size).coerceAtLeast(0))
        content.addView(ui.column().apply {
            tag = "health-overview-metrics"
            background = ui.background(stroke = color(R.color.separator), radius = 8)
            preview.forEachIndexed { index, item ->
                if (index > 0) addView(healthOverviewDivider(activity))
                val record = item.record; val summary = summaries[record?.id]
                val caption = record?.let {
                    val date = DateFormat.getDateInstance(DateFormat.SHORT).format(Date(it.draft.measuredAt))
                    val qualifier = if (it.draft.condition == "unspecified" || item.metric == HealthMetric.GLUCOSE && it.draft.condition == "fasting") ""
                        else " \u00b7 ${label(healthContextResource(it.draft.condition))}"
                    "$date$qualifier" + if (activity.measurementPeriod != null && summary != null) " \u00b7 ${label(R.string.health_period_record_count, summary.count)}" else ""
                }
                addView(metricView.row(item, caption) {
                    if (activity.measurementPeriod != null && record != null) activity.metricTrend(record)
                    else activity.open("overview_metric", item.metric)
                })
                if (summary != null && activity.measurementPeriod != null && summary.outsideCount > 0 && !item.outsideRange)
                    ui.add(this, ui.text(label(R.string.health_period_prior_outside, summary.outsideCount), 12f).apply {
                        setTextColor(color(R.color.health_overview_orange)); setPadding(ui.dp(12), 0, ui.dp(12), ui.dp(8))
                    })
            }
            if (preview.isEmpty()) addView(ui.text(label(R.string.health_period_no_matching), 13f, muted = true).apply { setPadding(ui.dp(12), ui.dp(12), ui.dp(12), ui.dp(12)) })
        })
        val outsideIds = measurements.filter { it.outsideRange }.mapNotNull { it.record?.id }.toSet()
        recordList?.clear()
        val filter = "${activity.measurementPeriod?.key.orEmpty()}|${activity.measurementAbnormal}"
        if (filter != recordFilter) { recordAfter = null; recordHistory = emptyList(); recordFilter = filter }
        recordList = HealthOverviewRecordsView(activity, names, activity.measurementPeriod, activity.measurementAbnormal, outsideIds, recordAfter, recordHistory).also {
            ui.add(content, it.root, 12); it.show()
        }
    }

    fun showMetric(content: LinearLayout, detail: HealthOverviewMetricDetail) = metricView.showDetail(content, detail)

    private data class Shortcut(val icon: Int, val title: Int, val tag: String, val action: () -> Unit)

    fun quicks() = ui.column().apply {
        tag = "health-overview-bottom-actions"
        setBackgroundColor(color(R.color.surface_bg))
        addView(View(activity).apply { setBackgroundColor(color(R.color.separator)) }, LinearLayout.LayoutParams(-1, ui.dp(1)))
        val entries = listOf(
            Shortcut(R.drawable.ic_agent_camera, R.string.health_overview_photo, "health-overview-photo") {
                if (names.fixture == null) activity.startActivity(healthCaptureIntent(activity, names, HealthCaptureEntry.CAMERA))
            },
            Shortcut(R.drawable.ic_hub_compose, R.string.health_manual, "health-overview-manual") { activity.open("manual") },
            Shortcut(R.drawable.ic_settings_upload, R.string.health_overview_import, "health-overview-import", activity::pickHealthFile),
            Shortcut(R.drawable.ic_settings_devices, R.string.health_sources_quick, "health-overview-sources") { start(HealthSourcesActivity::class.java) },
        )
        val configuration = activity.resources.configuration
        val columns = if (configuration.fontScale >= 1.5f || configuration.screenWidthDp < 310) 2 else 4
        entries.chunked(columns).forEach { row ->
            addView(ui.line().apply {
                row.forEach { entry ->
                    addView(ui.column().apply {
                        tag = entry.tag
                        gravity = Gravity.CENTER
                        minimumHeight = ui.dp(54)
                        isFocusable = true
                        setPadding(ui.dp(2), ui.dp(6), ui.dp(2), ui.dp(6))
                        setOnClickListener { entry.action() }
                        addView(ImageView(activity).apply {
                            setImageResource(entry.icon)
                            imageTintList = ColorStateList.valueOf(color(R.color.health_overview_green))
                            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
                        }, LinearLayout.LayoutParams(ui.dp(18), ui.dp(18)))
                        ui.add(this, ui.text(label(entry.title), 12f, bold = true).apply { gravity = Gravity.CENTER }, 4)
                    }, LinearLayout.LayoutParams(0, -1, 1f))
                }
            })
        }
    }
}

internal fun healthOverviewDivider(activity: HealthCenterActivity) = View(activity).apply {
    setBackgroundColor(activity.getColor(R.color.separator))
    layoutParams = LinearLayout.LayoutParams(-1, activity.ui.dp(1))
    importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
}

internal fun healthOverviewActivityTile(activity: HealthCenterActivity, title: Int, icon: Int,
    amount: android.widget.TextView, caption: android.widget.TextView) = activity.ui.run {
    column().apply {
        minimumHeight = dp(102)
        background = background(stroke = activity.getColor(R.color.separator), radius = 8)
        setPadding(dp(11), dp(8), dp(11), dp(6))
        addView(line().apply {
            addView(ImageView(activity).apply {
                setImageResource(icon)
                imageTintList = ColorStateList.valueOf(activity.getColor(R.color.health_overview_green))
                importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
            }, LinearLayout.LayoutParams(dp(16), dp(16)).apply { marginEnd = dp(6) })
            addView(text(activity.getString(title), 14f, bold = true), LinearLayout.LayoutParams(0, -2, 1f))
        })
        add(this, amount, 4)
        add(this, caption, 2)
    }
}

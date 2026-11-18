package com.galaxyssi.chat

import android.content.Intent
import android.os.Bundle
import android.view.Gravity
import android.widget.CheckBox
import android.widget.LinearLayout
import android.widget.RadioButton
import android.widget.RadioGroup
import java.text.DateFormat
import java.time.ZoneId
import java.util.Date

internal class HealthMeasurementPeriodsActivity : HealthHistoryPage() {
    override val heading = R.string.health_period_comparison
    private var kind = HealthMeasurementPeriodKind.WEEK
    private var a: HealthMeasurementPeriod? = null
    private var b: HealthMeasurementPeriod? = null
    private var abnormal = false
    override fun onCreate(savedInstanceState: Bundle?) {
        a = HealthMeasurementPeriod.parse(savedInstanceState?.getString("a") ?: intent.getStringExtra("health_period"))
        b = HealthMeasurementPeriod.parse(savedInstanceState?.getString("b"))
        kind = savedInstanceState?.getInt("kind")?.let { HealthMeasurementPeriodKind.entries.getOrNull(it) } ?: a?.kind ?: HealthMeasurementPeriodKind.WEEK
        abnormal = savedInstanceState?.getBoolean("abnormal") ?: false
        super.onCreate(savedInstanceState)
    }
    override fun onSaveInstanceState(outState: Bundle) {
        outState.putString("a", a?.key); outState.putString("b", b?.key); outState.putBoolean("abnormal", abnormal)
        outState.putInt("kind", kind.ordinal)
        super.onSaveInstanceState(outState)
    }
    override fun refresh() {
        content.removeAllViews(); content.addView(ui.text(getString(R.string.health_loading)))
        val selectedKind = kind; val first = a; val second = b
        query({ check -> HealthPrivacyStore.track(applicationContext,
            HealthAccessScope(HealthAccessPurpose.OVERVIEW, HealthMeasurementPeriods.metrics), names.privacy) {
            HealthRecordStore(applicationContext, names.records).use { store ->
                val versions = store.metricVersions(HealthMeasurementPeriods.metrics)
                val now = System.currentTimeMillis(); val zone = ZoneId.systemDefault()
                val period = first ?: HealthMeasurementPeriods.page(store, selectedKind, now, zone, check = check).periods.firstOrNull()
                val previous = second ?: runCatching { period?.previous() }.getOrNull()
                val result = period?.let { HealthMeasurementPeriods.load(store, it, now, zone, check) } to
                    previous?.let { HealthMeasurementPeriods.load(store, it, now, zone, check) }
                if (versions != store.metricVersions(HealthMeasurementPeriods.metrics)) throw HealthWeeklyChanged()
                result
            }
        } }) { (firstSummary, secondSummary) ->
            a = firstSummary?.period; b = secondSummary?.period; render(firstSummary, secondSummary)
        }
    }
    private fun render(first: HealthMeasurementPeriodSummary?, second: HealthMeasurementPeriodSummary?) {
        content.removeAllViews()
        content.addView(RadioGroup(this).apply {
            orientation = RadioGroup.HORIZONTAL
            HealthMeasurementPeriodKind.entries.forEach { option ->
                addView(RadioButton(this@HealthMeasurementPeriodsActivity).apply {
                    id = android.view.View.generateViewId(); text = getString(if (option == HealthMeasurementPeriodKind.WEEK) R.string.health_period_weeks else R.string.health_period_months)
                    isChecked = kind == option; minimumHeight = ui.dp(48)
                    setOnClickListener { if (kind != option) { kind = option; a = a?.let { HealthMeasurementPeriod.of(kind, it.first) }; b = null; refresh() } }
                }, RadioGroup.LayoutParams(0, -2, 1f))
            }
        })
        content.addView(ui.row(getString(R.string.health_period_a), a?.label(this).orEmpty()) { choose(true) }.apply { tag = "health-period-a" })
        content.addView(ui.row(getString(R.string.health_period_b), b?.label(this).orEmpty()) { choose(false) }.apply { tag = "health-period-b" })
        content.addView(CheckBox(this).apply {
            text = getString(R.string.health_period_abnormal); isChecked = abnormal
            setOnCheckedChangeListener { _, value -> abnormal = value; render(first, second) }
        })
        ui.add(content, ui.text(getString(R.string.health_period_basis), 12f, muted = true), 8)
        if (first == null) { ui.add(content, ui.text(getString(R.string.health_no_records)), 16); return }
        val left = first.series.associateBy { it.key }; val right = second?.series.orEmpty().associateBy { it.key }
        val keys = (left.keys + right.keys).sortedWith(compareBy({ it.metric.ordinal }, { it.condition }, { it.unit }, { it.side }))
        keys.forEach { key ->
            val x = left[key]; val y = right[key]
            if (abnormal && listOfNotNull(x, y).none { it.outsideCount > 0 }) return@forEach
            val record = (y ?: x)?.latest ?: return@forEach
            ui.add(content, ui.row(getString(key.metric.titleResource()), getString(healthContextResource(key.condition))) {
                startActivity(healthComparableTrendIntent(this, names, record))
            }, 12)
            val stack = resources.configuration.fontScale >= 1.3f || resources.configuration.screenWidthDp < 344
            val values = (if (stack) ui.column() else ui.line()).apply { gravity = Gravity.TOP }
            fun cell(series: HealthMeasurementSeries?, label: String) = ui.column().apply {
                addView(ui.text(label, 12f, muted = true))
                addView(ui.text(series?.latest?.let { healthDisplayValue(it.draft) } ?: getString(R.string.health_period_no_records), 19f, bold = true).apply {
                    if (series?.latest?.let { HealthOverviewRangePolicy.report(it)?.outside } == true) setTextColor(getColor(R.color.health_overview_orange))
                })
                series?.let { value ->
                    addView(ui.text(DateFormat.getDateTimeInstance(DateFormat.SHORT, DateFormat.SHORT).format(Date(value.latest.draft.measuredAt)), 12f, muted = true))
                    addView(ui.text(getString(R.string.health_period_record_count, value.count), 12f, muted = true))
                    if (value.outsideCount > 0 && HealthOverviewRangePolicy.report(value.latest)?.outside != true)
                        addView(ui.text(getString(R.string.health_period_prior_outside, value.outsideCount), 12f).apply { setTextColor(getColor(R.color.health_overview_orange)) })
                    if (value.latest.draft.reference.isNotBlank()) addView(ui.text(getString(R.string.health_measurement_report_range, value.latest.draft.reference), 12f, muted = true))
                    isFocusable = true
                    setOnClickListener { startActivity(Intent(this@HealthMeasurementPeriodsActivity, HealthCenterActivity::class.java)
                        .putHealthNavigationFixture(names).putExtra("health_record", value.latest.id)) }
                }
            }
            if (stack) { values.addView(cell(x, "A")); ui.add(values, cell(y, "B"), 8) }
            else { values.addView(cell(x, "A"), LinearLayout.LayoutParams(0, -2, 1f)); values.addView(cell(y, "B"), LinearLayout.LayoutParams(0, -2, 1f)) }
            content.addView(values)
            val differences = key.metric.requiredFields.mapNotNull { field -> HealthMeasurementPeriods.delta(y?.latest, x?.latest, field)?.let {
                "${getString(healthFieldResource(field))}: ${if (it.signum() > 0) "+" else ""}${it.stripTrailingZeros().toPlainString()} ${key.unit}"
            } }
            ui.add(content, ui.text(if (differences.size == key.metric.requiredFields.size) "A \u2212 B\n" + differences.joinToString("\n")
                else getString(R.string.health_measurement_not_comparable), 12f, muted = true), 4)
        }
        if (keys.isEmpty()) ui.add(content, ui.text(getString(R.string.health_no_records)), 16)
    }
    private fun choose(first: Boolean) = showHealthPeriodPicker(this, if (first) R.string.health_period_a else R.string.health_period_b,
        ::show, { before, done ->
            query({ check -> HealthPrivacyStore.track(applicationContext,
                HealthAccessScope(HealthAccessPurpose.OVERVIEW, HealthMeasurementPeriods.metrics), names.privacy) {
                HealthRecordStore(applicationContext, names.records).use { HealthMeasurementPeriods.page(it, kind, System.currentTimeMillis(), ZoneId.systemDefault(), before, check) }
            } }, done)
        }, { period -> if (first) a = period else b = period; refresh() })
}

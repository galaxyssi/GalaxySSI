package com.galaxyssi.chat

import android.app.AlertDialog
import android.app.DatePickerDialog
import android.os.Bundle
import android.widget.LinearLayout
import android.widget.RadioButton
import android.widget.RadioGroup
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.ChronoUnit
import java.text.NumberFormat

internal class HealthActivityComparisonActivity : HealthHistoryPage() {
    override val heading = R.string.health_activity_comparison
    private var kind = HealthActivityKind.STEPS
    private var days = 7
    private var first = LocalDate.now().minusDays(7)
    private var last = LocalDate.now().minusDays(1)
    override fun onCreate(savedInstanceState: Bundle?) {
        savedInstanceState?.let {
            kind = HealthActivityKind.entries.getOrElse(it.getInt("kind")) { HealthActivityKind.STEPS }
            days = it.getInt("days", 7)
            runCatching { first = LocalDate.parse(it.getString("first")); last = LocalDate.parse(it.getString("last")) }
        }
        super.onCreate(savedInstanceState)
    }
    override fun onSaveInstanceState(outState: Bundle) {
        outState.putInt("kind", kind.ordinal); outState.putInt("days", days)
        outState.putString("first", first.toString()); outState.putString("last", last.toString())
        super.onSaveInstanceState(outState)
    }
    override fun refresh() {
        if (days > 0) { last = LocalDate.now().minusDays(1); first = last.minusDays(days.toLong() - 1) }
        val from = first; val until = last; val selected = kind
        render(null)
        query({ check ->
            val zone = ZoneId.systemDefault()
            val size = ChronoUnit.DAYS.between(from, until) + 1
            HealthPrivacyStore.track(applicationContext, HealthAccessScope(HealthAccessPurpose.OVERVIEW, setOf(HealthMetric.STEPS),
                from.minusDays(size).atStartOfDay(zone).toInstant().toEpochMilli(), until.plusDays(1).atStartOfDay(zone).toInstant().toEpochMilli(), zone.id), names.privacy) {
                check()
                if (names.fixture == null) {
                    // Only surviving checkpoints can be migrated; missing older days remain unknown.
                    HealthPhoneStepStore(applicationContext).load()?.let { HealthPhoneStepStore(applicationContext).archive(it) }
                    HealthCyclingStore(applicationContext).let { it.archive(it.load()) }
                }
                HealthActivityHistoryStore(applicationContext, names.activity).use {
                    HealthActivityComparison.build(from, until, it.read(selected, from.minusDays(size), until), selected)
                }
            }
        }) { render(it) }
    }
    private fun render(result: HealthActivityComparison?) {
        content.removeAllViews()
        segment(listOf(R.string.health_overview_today_steps, R.string.health_cycling_today), kind.ordinal) {
            kind = HealthActivityKind.entries[it]; refresh()
        }
        val periods = listOf(7, 30, 90, 0)
        segment(listOf(R.string.health_trend_7, R.string.health_trend_30, R.string.health_trend_90, R.string.health_trend_custom), periods.indexOf(days)) {
            if (it == 3) custom() else { days = periods[it]; refresh() }
        }
        ui.add(content, ui.text("$first \u2014 $last", 13f, muted = true), 12)
        val count = ChronoUnit.DAYS.between(first, last) + 1
        ui.add(content, ui.text(getString(R.string.health_activity_previous_dates, first.minusDays(count).toString(), first.minusDays(1).toString()), 12f, muted = true), 4)
        if (result == null) { ui.add(content, ui.text(getString(R.string.health_loading)), 24); return }
        ui.add(content, ui.text(getString(R.string.health_activity_total), 13f, muted = true), 20)
        ui.add(content, ui.text(amount(result.current.filterNotNull().sum()), 30f, bold = true), 4)
        ui.add(content, ui.text(getString(R.string.health_activity_coverage, result.current.count { it != null }, count.toInt()), 12f, muted = true), 4)
        result.current.filterNotNull().takeIf { it.isNotEmpty() }?.let { totals ->
            ui.add(content, ui.text(getString(R.string.health_activity_average, amount(totals.sum() / totals.size)), 13f, muted = true), 4)
        }
        val paired = result.paired.size
        val change = result.changePercent?.let { String.format(java.util.Locale.getDefault(), "%+.1f%%", it) }
        ui.add(content, ui.text(if (paired == 0) getString(R.string.health_activity_no_pairs) else
            getString(R.string.health_activity_paired, paired, amount(result.currentPaired), amount(result.previousPaired), change ?: "\u2014"), 14f), 16)
        ui.add(content, HealthActivityComparisonChart(this, result, kind).apply { tag = "health-activity-chart" }, 16)
        ui.add(content, ui.line().apply {
            addView(ui.text(getString(R.string.health_activity_current), 13f).apply { setTextColor(getColor(R.color.health_overview_green)) }, LinearLayout.LayoutParams(0, -2, 1f))
            addView(ui.text(getString(R.string.health_activity_previous), 13f).apply { setTextColor(HealthTrendChart.BLUE) }, LinearLayout.LayoutParams(0, -2, 1f))
        }, 8)
        ui.add(content, ui.text(getString(R.string.health_activity_missing), 12f, muted = true), 16)
        ui.add(content, ui.row(getString(R.string.health_trend_chart_data)) {
            show(AlertDialog.Builder(this).setTitle(heading).setItems(result.current.indices.map { index ->
                "${first.plusDays(index.toLong())}: ${result.current[index]?.let(::amount) ?: "\u2014"} / ${result.previous[index]?.let(::amount) ?: "\u2014"}"
            }.toTypedArray(), null).setNegativeButton(android.R.string.cancel, null).create())
        })
    }
    private fun amount(value: Long) = if (kind == HealthActivityKind.STEPS) NumberFormat.getIntegerInstance().format(value) + " " + getString(R.string.health_activity_steps_unit)
        else NumberFormat.getNumberInstance().apply { maximumFractionDigits = 1 }.format(value / 60_000.0) + " " + getString(R.string.health_activity_minutes)
    private fun segment(labels: List<Int>, selected: Int, choose: (Int) -> Unit) {
        ui.add(content, RadioGroup(this).apply {
            orientation = RadioGroup.HORIZONTAL
            labels.forEachIndexed { index, label -> addView(RadioButton(this@HealthActivityComparisonActivity).apply {
                id = android.view.View.generateViewId(); text = getString(label); textSize = 13f; minimumHeight = ui.dp(48)
                buttonDrawable = null; gravity = android.view.Gravity.CENTER
                setTextColor(getColor(if (selected == index) R.color.health_overview_green else R.color.text_primary))
                background = ui.background(getColor(if (selected == index) R.color.button_soft else R.color.page_bg), radius = 6)
                setPadding(ui.dp(2), ui.dp(4), ui.dp(2), ui.dp(4))
                isChecked = selected == index; setOnClickListener { choose(index) }
            }, RadioGroup.LayoutParams(0, -2, 1f)) }
        }, 4)
    }
    private fun custom() {
        show(DatePickerDialog(this, { _, y, m, d ->
            val start = LocalDate.of(y, m + 1, d)
            show(DatePickerDialog(this, { _, ey, em, ed ->
                val end = LocalDate.of(ey, em + 1, ed)
                if (ChronoUnit.DAYS.between(start, end) in 0..365 && end.isBefore(LocalDate.now())) {
                    first = start; last = end; days = 0; refresh()
                } else android.widget.Toast.makeText(this, R.string.health_activity_dates_invalid, android.widget.Toast.LENGTH_LONG).show()
            }, last.year, last.monthValue - 1, last.dayOfMonth))
        }, first.year, first.monthValue - 1, first.dayOfMonth))
    }
}

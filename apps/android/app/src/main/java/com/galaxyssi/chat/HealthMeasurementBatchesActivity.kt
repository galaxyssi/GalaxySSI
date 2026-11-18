package com.galaxyssi.chat

import android.app.AlertDialog
import android.content.Intent
import android.os.Bundle
import android.widget.CheckBox
import java.text.DateFormat
import java.util.Date

internal class HealthMeasurementBatchesActivity : HealthHistoryPage() {
    override val heading = R.string.health_measurement_batches
    private var a = ""; private var b = ""; private var report = ""; private var abnormal = false
    private var choosing = "a"
    private var cursor: Pair<Long, String>? = null
    private var labelA = ""; private var labelB = ""
    override fun onCreate(savedInstanceState: Bundle?) {
        val state = savedInstanceState
        a = state?.getString("a") ?: intent.getStringExtra("health_batch").orEmpty()
        b = state?.getString("b").orEmpty(); report = state?.getString("report").orEmpty(); abnormal = state?.getBoolean("abnormal") ?: false
        choosing = state?.getString("choosing") ?: if (a.isBlank()) "a" else ""
        super.onCreate(state)
    }
    override fun onSaveInstanceState(outState: Bundle) {
        outState.putString("a", a); outState.putString("b", b); outState.putString("report", report)
        outState.putBoolean("abnormal", abnormal); outState.putString("choosing", choosing)
        super.onSaveInstanceState(outState)
    }
    private fun date(time: Long) = DateFormat.getDateTimeInstance(DateFormat.SHORT, DateFormat.SHORT).format(Date(time))
    override fun refresh() {
        content.removeAllViews(); content.addView(ui.text(getString(R.string.health_loading)))
        val target = choosing; val selectedA = a; val selectedB = b; val selectedReport = report; val after = cursor
        query({ check -> HealthPrivacyStore.track(applicationContext,
            HealthAccessScope(HealthAccessPurpose.OVERVIEW, HealthMetric.entries.toSet()), names.privacy) {
            HealthOriginalStore(applicationContext, names.originals, names.originalRoot(applicationContext)).use { originals ->
                val batches = HealthMeasurementBatches(originals)
                if (target.isNotBlank()) Triple(batches.page(after), null, null)
                else HealthRecordStore(applicationContext, names.records).use { records ->
                    labelA = batches.label(selectedA).let { date(it.first) + if (it.second.isBlank()) "" else " \u00b7 ${it.second}" }
                    labelB = selectedB.takeIf(String::isNotEmpty)?.let { batches.label(it) }?.let { date(it.first) }.orEmpty()
                    Triple(null, batches.load(records, selectedA, selectedReport, check),
                        selectedB.takeIf(String::isNotEmpty)?.let { batches.load(records, it, check = check) })
                }
            }
        } }) { (page, first, second) ->
            content.removeAllViews()
            if (page != null) renderPicker(page, target) else renderResults(requireNotNull(first), second)
        }
    }
    private fun renderPicker(page: HealthMeasurementBatchPage, target: String) {
        if (intent.getBooleanExtra("health_select_batch", false)) content.addView(ui.row(getString(R.string.health_measurement_latest)) {
            setResult(RESULT_OK, Intent().putExtra("health_batch", "")); finish()
        })
        if (page.items.isEmpty()) content.addView(ui.text(getString(R.string.health_no_records)))
        page.items.forEach { batch ->
            ui.add(content, ui.row(getString(R.string.health_measurement_imported, date(batch.importedAt)),
                getString(R.string.health_measurement_reports, batch.reports) + batch.name.takeIf(String::isNotBlank)?.let { " \u00b7 $it" }.orEmpty()) {
                if (intent.getBooleanExtra("health_select_batch", false)) {
                    setResult(RESULT_OK, Intent().putExtra("health_batch", batch.key)); finish()
                } else { if (target == "b") b = batch.key else { a = batch.key; report = "" }; choosing = ""; cursor = null; refresh() }
            }, 4)
        }
        page.next?.let { next -> content.addView(ui.row(getString(R.string.health_next_page)) { cursor = next; refresh() }) }
        if (cursor != null) content.addView(ui.row(getString(R.string.health_measurement_first_page)) { cursor = null; refresh() })
    }
    private fun renderResults(first: HealthMeasurementBatchSnapshot, second: HealthMeasurementBatchSnapshot?) {
        content.addView(ui.row(getString(R.string.health_measurement_batch_a), labelA) { choose("a") })
        content.addView(ui.row(getString(R.string.health_measurement_batch_b), labelB) { choose("b") })
        if (b.isNotEmpty()) content.addView(ui.row(getString(R.string.health_measurement_clear_comparison)) { b = ""; refresh() })
        if (b.isEmpty()) content.addView(ui.row(getString(R.string.health_measurement_choose_report),
            report.takeIf(String::isNotEmpty)?.take(8) ?: getString(R.string.health_measurement_all_reports)) { chooseReport() })
        content.addView(CheckBox(this).apply {
            text = getString(R.string.health_measurement_abnormal); isChecked = abnormal
            setOnCheckedChangeListener { _, value -> abnormal = value; renderResultsAgain(first, second) }
        })
        ui.add(content, ui.text(getString(R.string.health_measurement_scope_note), 12f, muted = true), 8)
        val metrics = (first.latest.keys + second?.latest.orEmpty().keys).sortedBy { it.ordinal }
        metrics.forEach { metric ->
            val x = first.latest[metric]; val y = second?.latest?.get(metric)
            if (abnormal && listOfNotNull(x, y).none { HealthOverviewRangePolicy.report(it)?.outside == true }) return@forEach
            ui.add(content, ui.row(getString(metric.titleResource()), getString(R.string.health_measurement_continuous)) {
                (y ?: x)?.let(::openTrend)
            }, 12)
            val stack = resources.configuration.fontScale >= 1.3f || resources.configuration.screenWidthDp < 344
            val values = (if (stack) ui.column() else ui.line()).apply { gravity = android.view.Gravity.TOP }
            fun reading(record: HealthObservation?, prefix: String) = ui.column().apply {
                if (second != null) addView(ui.text(prefix, 12f, muted = true))
                addView(ui.text(record?.let { healthDisplayValue(it.draft) } ?: "\u2014", 19f, bold = true).apply {
                    if (record?.let { HealthOverviewRangePolicy.report(it)?.outside } == true) setTextColor(getColor(R.color.health_overview_orange))
                })
                record?.let {
                    addView(ui.text(date(it.draft.measuredAt), 12f, muted = true))
                    addView(ui.text(getString(healthContextResource(it.draft.condition)), 12f, muted = true))
                    if (it.draft.reference.isNotBlank()) addView(ui.text(getString(R.string.health_measurement_report_range, it.draft.reference), 12f, muted = true))
                    isFocusable = true
                    setOnClickListener { startActivity(Intent(this@HealthMeasurementBatchesActivity, HealthCenterActivity::class.java)
                        .putHealthNavigationFixture(names).putExtra("health_record", it.id)) }
                }
            }
            if (stack) { values.addView(reading(x, "A")); if (second != null) ui.add(values, reading(y, "B"), 8) }
            else { values.addView(reading(x, "A"), android.widget.LinearLayout.LayoutParams(0, -2, 1f))
                if (second != null) values.addView(reading(y, "B"), android.widget.LinearLayout.LayoutParams(0, -2, 1f)) }
            content.addView(values)
            if (second != null) {
                val deltas = metric.requiredFields.mapNotNull { field -> HealthMeasurementBatches.delta(x, y, field)?.let {
                    "${getString(healthFieldResource(field))}: ${if (it.signum() > 0) "+" else ""}${it.stripTrailingZeros().toPlainString()} ${x?.draft?.unit.orEmpty()}"
                } }
                content.addView(ui.text(if (deltas.size == metric.requiredFields.size) deltas.joinToString("\n") else getString(R.string.health_measurement_not_comparable), 12f, muted = true))
            }
        }
        if (metrics.isEmpty()) ui.add(content, ui.text(getString(R.string.health_no_records)), 16)
    }
    private fun renderResultsAgain(a: HealthMeasurementBatchSnapshot, b: HealthMeasurementBatchSnapshot?) {
        content.removeAllViews(); renderResults(a, b)
    }
    private fun choose(target: String) { choosing = target; cursor = null; refresh() }
    private fun chooseReport(after: String = "") {
        query({ check -> HealthPrivacyStore.track(applicationContext,
            HealthAccessScope(HealthAccessPurpose.OVERVIEW, HealthMetric.entries.toSet()), names.privacy) {
            HealthOriginalStore(applicationContext, names.originals, names.originalRoot(applicationContext)).use { originals ->
                check(); HealthMeasurementBatches(originals).reports(a, after).map { it to originals.original(it)?.name.orEmpty() }
            }
        } }) { rows ->
            val labels = listOf(getString(R.string.health_measurement_all_reports)) + rows.map { it.second.ifBlank { it.first.take(8) } } +
                if (rows.size == 30) listOf(getString(R.string.health_next_page)) else emptyList()
            show(AlertDialog.Builder(this).setTitle(R.string.health_measurement_choose_report).setItems(labels.toTypedArray()) { _, index ->
                when { index == 0 -> { report = ""; refresh() }; index <= rows.size -> { report = rows[index - 1].first; refresh() }
                    else -> chooseReport(rows.last().first) }
            }.setNegativeButton(android.R.string.cancel, null).create())
        }
    }
    private fun openTrend(record: HealthObservation) = startActivity(healthComparableTrendIntent(this, names, record))
}

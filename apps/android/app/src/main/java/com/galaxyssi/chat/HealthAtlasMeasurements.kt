package com.galaxyssi.chat

import android.app.Activity
import android.content.Intent
import android.database.ContentObserver
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper
import android.widget.LinearLayout
import java.time.LocalDate
import java.time.ZoneId
import java.time.Instant
import java.time.format.DateTimeFormatter
import java.util.concurrent.Executors

internal data class HealthAtlasMeasurementSelection(val metric: HealthMetric?, val period: Int = 1)

/** Cancels indexed reads and drops decrypted view state whenever this surface leaves the foreground. */
internal class HealthAtlasMeasurements(private val activity: Activity, private val parent: LinearLayout,
    private val item: HealthAtlasItem, initial: HealthAtlasMeasurementSelection?,
    private val onAnalysisReady: (Boolean) -> Unit = {}) : AutoCloseable {
    private val ui = HealthCenterViews(activity)
    private val names = activity.intent.healthNavigationDatabases()
    private val metrics = HealthAtlasMetrics.forItem(item)
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var metric = initial?.metric?.takeIf { it in metrics } ?: metrics.firstOrNull()
    private var period = initial?.period?.coerceIn(0, 2) ?: 1
    val selection get() = HealthAtlasMeasurementSelection(metric, period)
    private var signal: CancellationSignal? = null
    private var generation = 0
    private var closed = false
    private var analysis: HealthTrendAnalysisHandoff? = null
    val canAnalyze get() = !closed && analysis != null
    private var picker: android.app.AlertDialog? = null
    private val panel = ui.column().apply { isSaveEnabled = false }
    private var chart: HealthTrendChart? = null
    private val observer = object : ContentObserver(main) { override fun onChange(selfChange: Boolean) { if (!closed) load() } }
    init {
        parent.addView(panel)
        if (metrics.isEmpty()) ui.add(panel, ui.text(activity.getString(R.string.health_atlas_no_metrics), 16f))
        else {
            activity.contentResolver.registerContentObserver(HealthRecordStore.changes(activity, names.records), false, observer)
            activity.contentResolver.registerContentObserver(HealthPrivacyStore.changes(activity, names.privacy), false, observer)
            load()
        }
    }
    private fun load() {
        if (closed) return
        analysis = null; onAnalysisReady(false)
        val selected = metric ?: return
        signal?.cancel(); val cancellation = CancellationSignal(); signal = cancellation; val token = ++generation
        chart?.clear(); chart = null; panel.removeAllViews()
        val metricSelector = ui.row(activity.getString(selected.titleResource())) {
            picker = android.app.AlertDialog.Builder(activity).setTitle(R.string.health_atlas_measurements)
                .setItems(metrics.map { activity.getString(it.titleResource()) }.toTypedArray()) { _, index -> metric = metrics[index]; load() }
                .setNegativeButton(android.R.string.cancel, null).show()
        }.apply { tag = "atlas-metric-selector" }
        panel.addView(metricSelector)
        panel.addView(HealthAtlasUi.tabs(activity, listOf(R.string.health_atlas_week, R.string.health_atlas_month, R.string.health_atlas_year), period, "atlas-period") { period = it; load() })
        val resultPanel = ui.column(); panel.addView(resultPanel)
        resultPanel.addView(ui.text(activity.getString(R.string.health_loading)))
        val zone = ZoneId.systemDefault(); val last = LocalDate.now(zone)
        val first = when (period) { 0 -> last.minusDays(6); 1 -> last.minusMonths(1).plusDays(1); else -> last.minusYears(1).plusDays(1) }
        val requested = HealthTrendSpec(selected, first, last, zone, selected.units.first(), HealthTrendAggregation.LATEST)
        worker.execute {
            val result = runCatching {
                HealthPrivacyStore.track(activity.applicationContext, HealthAccessScope.trend(HealthAccessPurpose.TREND, requested), names.privacy) {
                    HealthRecordStore(activity.applicationContext, names.records).use { store ->
                        cancellation.throwIfCanceled()
                        val unit = store.trendRecords(requested, signal = cancellation).records.firstOrNull()?.draft?.unit
                            ?.takeIf { it in selected.selectableUnits } ?: requested.unit
                        HealthTrendRepository.load(store, requested.copy(unit = unit), { cancellation.throwIfCanceled() }, signal = cancellation)
                    }
                }
            }
            main.post { if (!closed && generation == token && !cancellation.isCanceled) {
                resultPanel.removeAllViews()
                result.fold({ summary -> show(resultPanel, summary) }, { error ->
                    resultPanel.addView(ui.text(activity.getString(if (error is HealthAccessBlocked) R.string.health_privacy_trend_blocked else R.string.health_storage_error)))
                    ui.add(resultPanel, ui.command(if (error is HealthAccessBlocked) R.string.health_privacy_title else R.string.health_atlas_reset) {
                        if (error is HealthAccessBlocked) activity.startActivity(Intent(activity, HealthPrivacyActivity::class.java)
                            .putExtra("health_privacy_test_db", names.privacy).putHealthNavigationFixture(names)) else load()
                    }, 12)
                })
            } }
        }
    }
    private fun show(container: LinearLayout, summary: HealthTrendSummary) {
        val record = summary.latest
        ui.add(container, ui.text(record?.let { healthDisplayValue(it.draft) } ?: activity.getString(R.string.health_no_measurement), 26f, bold = true), 18)
        if (record != null) {
            val whenMeasured = Instant.ofEpochMilli(record.draft.measuredAt).atZone(summary.spec.zone).format(DateTimeFormatter.ofPattern("uuuu-MM-dd HH:mm"))
            ui.add(container, ui.text(whenMeasured + " · " + activity.getString(healthRecordSourceResource(record.source)), 12f, muted = true), 4)
            record.draft.condition.takeIf(String::isNotBlank)?.let { ui.add(container, ui.text(activity.getString(healthContextResource(it)), 12f, muted = true), 4) }
        }
        val plot = HealthTrendChart(activity, selected = { point ->
            if (point.recordId.isNotBlank()) activity.startActivity(Intent(activity, HealthRecordRevisionActivity::class.java)
                .putExtra("health_record", point.recordId).putExtra("health_revision", point.recordRevision).putHealthNavigationFixture(names))
        }).apply { tag = "atlas-personal-chart"; bind(summary) }
        chart = plot; container.addView(plot, LinearLayout.LayoutParams(-1, ui.dp(230)))
        ui.add(container, ui.text(activity.getString(R.string.health_atlas_records_note), 12f, muted = true), 12)
        ui.add(container, ui.row(activity.getString(R.string.health_atlas_source)) {
            activity.startActivity(Intent(activity, HealthTrendRecordsActivity::class.java).putHealthTrend(summary.spec).putHealthNavigationFixture(names))
        }, 12)
        ui.add(container, ui.row(activity.getString(R.string.health_atlas_trend_details)) {
            activity.startActivity(Intent(activity, HealthTrendActivity::class.java).putHealthTrend(summary.spec).putHealthNavigationFixture(names))
        })
        analysis = if (summary.points.isNotEmpty()) HealthTrendAnalysisHandoff(summary.spec, summary.version) else null
        onAnalysisReady(canAnalyze)
    }
    fun analyze() {
        if (closed) return
        val selected = analysis ?: return
        activity.startActivity(Intent(activity, HealthAssistantActivity::class.java)
            .putHealthTrendAnalysis(selected).putHealthNavigationFixture(names))
    }
    override fun close() {
        if (closed) return
        closed = true; generation++; signal?.cancel(); signal = null; picker?.dismiss(); picker = null
        analysis = null; onAnalysisReady(false)
        activity.contentResolver.unregisterContentObserver(observer)
        chart?.clear(); chart = null; panel.removeAllViews(); worker.shutdown()
    }
}

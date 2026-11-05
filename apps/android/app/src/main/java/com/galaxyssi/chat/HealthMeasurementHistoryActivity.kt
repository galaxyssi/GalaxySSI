package com.galaxyssi.chat

import android.app.Activity
import android.app.AlertDialog
import android.os.Bundle
import android.os.CancellationSignal
import android.widget.LinearLayout
import java.time.Instant
import java.time.ZoneId
import java.util.concurrent.Executors

internal data class HealthMeasurementHistoryScope(val metric: HealthMetric, val healthConnectOnly: Boolean) {
    init { require(!healthConnectOnly || HealthConnectScope.entries.any { it.metric == metric }) }
}

internal enum class HealthMeasurementSource(val code: String) {
    MANUAL("manual"), OCR("ocr"), TABLE("table"), BLUETOOTH("bluetooth"), CONNECT("health_connect"), OTHER("");

    companion object {
        fun from(code: String) = entries.firstOrNull { it.code == code } ?: OTHER
    }
}

internal data class HealthMeasurementHistoryPreview(
    val scope: HealthMeasurementHistoryScope,
    val version: String,
    val sources: Map<HealthMeasurementSource, Long>,
    val first: Long,
    val last: Long,
) {
    val count: Long get() = sources.values.sum()
}

internal class HealthMeasurementHistoryChanged : IllegalStateException("Health measurement history changed after preview")

/** Reviews app-owned records without accessing external sources. */
class HealthMeasurementHistoryActivity : Activity() {
    private val ui by lazy { HealthCenterViews(this) }
    private val names by lazy { intent.healthNavigationDatabases() }
    private val healthConnectOnly by lazy { !intent.getBooleanExtra("health_erase_measurements", false) }
    private val prefix get() = if (healthConnectOnly) "health-connect-history" else "health-measurement-history"
    private val heading get() = if (healthConnectOnly) R.string.health_connect_history_title else R.string.health_measurement_history_delete
    private val worker = Executors.newSingleThreadExecutor()
    private lateinit var body: LinearLayout
    private var active = false
    private var deleting = false
    private var dialog: AlertDialog? = null
    private var signal: CancellationSignal? = null
    private var notice: Int? = null

    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        body = healthProfileBody(heading) { finish() }
    }
    override fun onResume() { super.onResume(); active = true; show() }
    override fun onPause() {
        active = false
        dialog?.dismiss(); dialog = null
        signal?.cancel(); signal = null
        body.removeAllViews()
        super.onPause()
    }
    override fun onDestroy() { worker.shutdown(); super.onDestroy() }

    private fun show() {
        val content = healthProfileContent(body)
        if (deleting || signal != null) {
            content.addView(ui.text(getString(R.string.health_loading), 14f, muted = true))
            return
        }
        notice?.let { ui.add(content, ui.text(getString(it), 14f).apply { tag = "$prefix-notice" }, 4) }
        if (healthConnectOnly) {
            for (scope in HealthConnectScope.entries) addMetric(content, scope.metric, scope.name)
        } else {
            for (metric in HealthMetric.entries) addMetric(content, metric, metric.name)
        }
    }

    private fun addMetric(content: LinearLayout, metric: HealthMetric, key: String) {
        ui.add(content, ui.profileRow(getString(metric.titleResource())) { preview(HealthMeasurementHistoryScope(metric, healthConnectOnly)) }
            .apply { tag = "$prefix-$key" }, 6)
    }

    private fun preview(scope: HealthMeasurementHistoryScope) {
        if (!active || deleting || signal != null || dialog?.isShowing == true) return
        val request = CancellationSignal().also { signal = it }
        notice = null; show()
        worker.execute {
            val app = applicationContext
            val result = runCatching {
                if (!app.getDatabasePath(names.records).isFile) null
                else HealthRecordStore(app, names.records).use { it.measurementHistoryPreview(scope, request::throwIfCanceled) }
            }
            runOnUiThread {
                if (!active || signal !== request) return@runOnUiThread
                signal = null
                result.fold({ current ->
                    if (current == null || current.count == 0L)
                        notice = if (healthConnectOnly) R.string.health_connect_history_empty else R.string.health_measurement_history_empty
                    else if (hasWindowFocus()) confirm(current)
                }, { notice = failureResource(it) })
                show()
            }
        }
    }

    private fun confirm(preview: HealthMeasurementHistoryPreview) {
        val zone = ZoneId.systemDefault()
        fun date(time: Long) = Instant.ofEpochMilli(time).atZone(zone).toLocalDate()
        val metric = getString(preview.scope.metric.titleResource())
        val first = date(preview.first)
        val last = date(preview.last)
        val message = if (healthConnectOnly) getString(R.string.health_connect_history_preview, metric, preview.count, first, last)
        else {
            val sources = HealthMeasurementSource.entries.mapNotNull { source ->
                preview.sources[source]?.let {
                    getString(R.string.health_measurement_history_source, getString(healthRecordSourceResource(source.code)), it)
                }
            }.joinToString("\n")
            getString(R.string.health_measurement_history_preview, metric, preview.count, first, last, sources)
        }
        dialog = AlertDialog.Builder(this)
            .setTitle(if (healthConnectOnly) R.string.health_connect_history_delete else heading)
            .setMessage(message)
            .setNegativeButton(R.string.common_cancel, null)
            .setPositiveButton(R.string.common_delete) { _, _ -> erase(preview, zone) }
            .show()
    }

    private fun erase(preview: HealthMeasurementHistoryPreview, zone: ZoneId) {
        if (!active || deleting) return
        deleting = true; notice = null; show()
        val purpose = if (healthConnectOnly) HealthAccessPurpose.DELETE_HEALTH_CONNECT_HISTORY else HealthAccessPurpose.DELETE_MEASUREMENT_HISTORY
        val source = if (healthConnectOnly) HealthAccessSource.HEALTH_CONNECT else HealthAccessSource.ALL
        val access = HealthAccessScope(purpose, setOf(preview.scope.metric), preview.first, preview.last + 1, zone.id,
            count = preview.count, source = source)
        worker.execute {
            val app = applicationContext
            val result = runCatching {
                HealthPrivacyStore.track(app, access, if (names.fixture == null) healthPrivacyDatabaseName() else names.privacy) {
                    HealthRecordStore(app, names.records).use { it.eraseMeasurementHistory(preview) }
                }
            }
            runOnUiThread {
                deleting = false
                notice = result.fold({
                    if (healthConnectOnly) R.string.health_connect_history_deleted else R.string.health_measurement_history_deleted
                }, ::failureResource)
                if (active) show()
            }
        }
    }

    private fun failureResource(failure: Throwable) =
        if (failure is HealthMeasurementHistoryChanged) R.string.health_connect_history_changed else R.string.health_storage_error
}

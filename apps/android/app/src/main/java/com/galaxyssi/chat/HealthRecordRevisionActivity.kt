package com.galaxyssi.chat

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.widget.LinearLayout
import android.widget.ScrollView
import java.text.DateFormat
import java.util.Date
import java.util.concurrent.Executors

/** Read-only audit view: a plotted historical point must not silently open a later edited value. */
class HealthRecordRevisionActivity : Activity() {
    private val names by lazy { intent.healthNavigationDatabases() }
    private val ui by lazy { HealthCenterViews(this) }; private val worker = Executors.newSingleThreadExecutor(); private val main = Handler(Looper.getMainLooper())
    private lateinit var body: LinearLayout; private var active = false; private var generation = 0
    private var id = ""; private var revision = 0
    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        id = intent.getStringExtra("health_record").orEmpty(); revision = intent.getIntExtra("health_revision", 0)
        if (runCatching { java.util.UUID.fromString(id).toString() == id }.getOrDefault(false).not() || revision <= 0) { finish(); return }
        window.statusBarColor = getColor(R.color.page_bg); window.navigationBarColor = getColor(R.color.page_bg)
        if (android.os.Build.VERSION.SDK_INT >= 33) setRecentsScreenshotEnabled(false)
        val root = ui.column().apply { setBackgroundColor(getColor(R.color.page_bg)) }
        root.addView(ui.line().apply {
            addView(ui.icon(R.drawable.ic_navigation_back, R.string.health_back) { finish() })
            addView(ui.text(getString(R.string.health_trend_snapshot_record), 19f, bold = true).apply { gravity = Gravity.CENTER }, LinearLayout.LayoutParams(0, -2, 1f))
            addView(ui.icon(R.drawable.ic_health_grid, R.string.health_functions) { startActivity(Intent(this@HealthRecordRevisionActivity, HealthCenterActivity::class.java).putExtra("health_functions", true)) })
        }, LinearLayout.LayoutParams(-1, ui.dp(56)))
        body = ui.column(); root.addView(body, LinearLayout.LayoutParams(-1, 0, 1f)); setContentView(root)
    }
    override fun onStart() { super.onStart(); if (::body.isInitialized) { active = true; load() } }
    override fun onStop() { active = false; generation++; if (::body.isInitialized) body.removeAllViews(); super.onStop() }
    override fun onDestroy() { worker.shutdown(); super.onDestroy() }
    private fun load() {
        val token = ++generation; body.removeAllViews(); body.addView(ui.text(getString(R.string.health_loading)))
        worker.execute {
            val result = runCatching { HealthRecordStore(applicationContext, names.records).use { it.revision(id, revision) } }
            main.post { if (!active || token != generation) return@post
                body.removeAllViews()
                result.fold({ record ->
                    if (record == null) { body.addView(ui.text(getString(R.string.health_record_missing))); return@fold }
                    val draft = record.draft
                    val content = ui.column().apply { setPadding(ui.dp(16), ui.dp(16), ui.dp(16), ui.dp(24)) }
                    content.addView(ui.text(getString(draft.metric.titleResource()), 18f, bold = true))
                    ui.add(content, ui.text(healthDisplayValue(draft), 23f, bold = true).apply { tag = "health-revision-value" }, 8)
                    ui.add(content, ui.text(DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT).format(Date(draft.measuredAt)), 14f, muted = true), 12)
                    ui.add(content, ui.text(getString(R.string.health_revision, record.revision), 13f, muted = true), 6)
                    ui.add(content, ui.text(getString(healthRecordSourceResource(record.source))), 12)
                    if (record.source == "bluetooth") ui.add(content,
                        ui.text(healthBluetoothTrendLabel(record.bluetoothGroup, record.platformOrigin), 13f, muted = true)
                            .apply { tag = "health-revision-device" }, 4)
                    if (record.source == "health_connect" && record.platformOrigin.isNotEmpty()) ui.add(content,
                        ui.text(healthConnectTrendLabel(record.platformOrigin, record.draft.metric), 13f, muted = true)
                            .apply { tag = "health-revision-platform" }, 4)
                    ui.add(content, ui.text(getString(healthContextResource(draft.condition))), 8)
                    if (draft.metric == HealthMetric.BLOOD_PRESSURE) {
                        ui.add(content, ui.text(getString(healthContextResource(draft.side))), 8)
                        draft.values["pulse"]?.let { ui.add(content, ui.text("${getString(R.string.health_pulse)}: $it bpm"), 8) }
                    }
                    if (draft.reference.isNotBlank()) { ui.add(content, ui.text(getString(R.string.health_report_reference), 13f, muted = true), 12); content.addView(ui.text(draft.reference)) }
                    if (draft.note.isNotBlank()) ui.add(content, ui.text(draft.note), 12)
                    draft.evidence?.let { evidence ->
                        ui.add(content, ui.row(getString(R.string.health_view_original)) { startActivity(Intent(this, HealthCaptureActivity::class.java).putExtra("original", evidence.originalId).putHealthNavigationFixture(names)) }, 12)
                        ui.add(content, ui.text(evidence.rawText, 13f, muted = true).apply { setTextIsSelectable(true) }, 8)
                    }
                    ui.add(content, ui.row(getString(R.string.health_trend_current_record)) { startActivity(Intent(this, HealthCenterActivity::class.java).putExtra("health_record", id).putHealthNavigationFixture(names)) }, 16)
                    ui.add(content, ui.row(getString(R.string.health_revision_history)) { startActivity(Intent(this, HealthCenterActivity::class.java).putExtra("health_record", id).putExtra("health_metric", draft.metric.name).putExtra("health_history", true).putHealthNavigationFixture(names)) })
                    body.addView(ScrollView(this).apply { addView(content) }, LinearLayout.LayoutParams(-1, 0, 1f))
                }, { body.addView(ui.text(getString(R.string.health_storage_error))); body.addView(ui.command(R.string.common_retry) { load() }) })
            }
        }
    }
}

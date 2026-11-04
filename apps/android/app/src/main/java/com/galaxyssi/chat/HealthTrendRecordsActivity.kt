package com.galaxyssi.chat

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.Toast
import java.time.Instant
import java.time.format.DateTimeFormatter
import java.util.concurrent.CancellationException
import java.util.concurrent.Executors

/** An aggregate point opens its own date/unit/source cohort, never a full unfiltered history. */
class HealthTrendRecordsActivity : Activity() {
    private val names by lazy { intent.healthNavigationDatabases() }
    private val ui by lazy { HealthCenterViews(this) }
    private val worker = Executors.newSingleThreadExecutor(); private val main = Handler(Looper.getMainLooper())
    private lateinit var body: LinearLayout; private lateinit var spec: HealthTrendSpec
    private var numeric = false; private var active = false; @Volatile private var generation = 0
    private var fixedVersion = false
    private var signal: CancellationSignal? = null; private var cursor: HealthPageCursor? = null
    private var version: String? = null
    private val previous = arrayListOf<HealthPageCursor?>()
    private val privacyDatabase by lazy { if (names.fixture == null) healthPrivacyDatabaseName() else names.privacy }
    private val privacyObserver = object : android.database.ContentObserver(main) {
        override fun onChange(selfChange: Boolean) { if (active) load() }
    }
    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        spec = intent.healthTrendSpec() ?: run { finish(); return }; numeric = intent.getBooleanExtra("health_numeric", false)
        fixedVersion = intent.getBooleanExtra("health_fixed_version", false)
        version = state?.getString("version") ?: intent.getStringExtra("health_version")
        if ((numeric || fixedVersion) && version == null) { finish(); return }
        state?.getString("cursor_id")?.let { cursor = HealthPageCursor(state.getLong("cursor_time"), it) }
        state?.getStringArrayList("previous")?.forEach { value ->
            previous += if (value.isEmpty()) null else value.split('|').let { HealthPageCursor(it[0].toLong(), it[1]) }
        }
        window.statusBarColor = getColor(R.color.page_bg); window.navigationBarColor = getColor(R.color.page_bg)
        if (android.os.Build.VERSION.SDK_INT >= 33) setRecentsScreenshotEnabled(false)
        val root = ui.column().apply { setBackgroundColor(getColor(R.color.page_bg)) }
        root.addView(ui.line().apply {
            addView(ui.icon(R.drawable.ic_navigation_back, R.string.health_back) { finish() })
            addView(ui.text(getString(spec.metric.titleResource()), 19f, bold = true).apply { gravity = Gravity.CENTER }, LinearLayout.LayoutParams(0, -2, 1f))
            addView(ui.icon(R.drawable.ic_health_grid, R.string.health_functions) { startActivity(Intent(this@HealthTrendRecordsActivity, HealthCenterActivity::class.java).putExtra("health_functions", true)) })
        }, LinearLayout.LayoutParams(-1, ui.dp(56)))
        body = ui.column(); root.addView(body, LinearLayout.LayoutParams(-1, 0, 1f)); setContentView(root)
    }
    override fun onStart() { super.onStart(); if (::spec.isInitialized) {
        active = true; contentResolver.registerContentObserver(HealthPrivacyStore.changes(this, privacyDatabase), false, privacyObserver); load()
    } }
    override fun onStop() {
        if (active) contentResolver.unregisterContentObserver(privacyObserver)
        active = false; generation++; signal?.cancel(); signal = null; if (::body.isInitialized) body.removeAllViews(); super.onStop()
    }
    override fun onDestroy() { worker.shutdown(); super.onDestroy() }
    override fun onSaveInstanceState(state: Bundle) {
        cursor?.let { state.putLong("cursor_time", it.measuredAt); state.putString("cursor_id", it.id) }
        state.putStringArrayList("previous", ArrayList(previous.map { if (it == null) "" else "${it.measuredAt}|${it.id}" }))
        version?.let { state.putString("version", it) }
        super.onSaveInstanceState(state)
    }
    private fun load() {
        val token = ++generation; signal?.cancel(); val cancellation = CancellationSignal(); signal = cancellation; val after = cursor
        body.removeAllViews(); body.addView(ui.text(getString(R.string.health_loading), 14f, muted = true))
        worker.execute {
            val result = runCatching { HealthPrivacyStore.track(applicationContext, HealthAccessScope.trend(HealthAccessPurpose.TREND_RECORDS, spec), privacyDatabase) { HealthRecordStore(applicationContext, names.records).use { store ->
                val before = store.metricVersion(spec.metric)
                if (version != null && version != before) throw HealthTrendChangedException()
                val page = store.trendRecords(spec, after, numeric, {
                    if (token != generation || cancellation.isCanceled) throw CancellationException()
                }, cancellation)
                if (store.metricVersion(spec.metric) != before) throw HealthTrendChangedException()
                page to before
            } } }
            main.post { if (active && token == generation) result.fold({ (page, snapshot) -> version = snapshot; render(page) }, {
                body.removeAllViews()
                body.addView(ui.text(getString(when (it) { is HealthTrendChangedException -> R.string.health_trend_changed; is HealthAccessBlocked -> R.string.health_privacy_trend_blocked; else -> R.string.health_storage_error }), 14f, muted = true))
                if (it is HealthAccessBlocked) body.addView(ui.command(R.string.health_privacy_title) { startActivity(healthPrivacyIntent()) }.apply { tag = "health-privacy-blocked" })
                body.addView(ui.command(if (numeric || fixedVersion) R.string.health_trend_return else R.string.health_trend_refresh) {
                    if (numeric || fixedVersion) finish() else { version = null; cursor = null; previous.clear(); load() }
                })
            }) }
        }
    }
    private fun render(page: HealthRecordPage) {
        body.removeAllViews()
        val content = ui.column().apply { setPadding(ui.dp(16), ui.dp(16), ui.dp(16), ui.dp(24)) }
        content.addView(ui.text("${spec.first} \u2014 ${spec.last} \u00b7 ${spec.zone.id}", 13f, muted = true))
        if (numeric) ui.add(content, ui.text(getString(R.string.health_trend_numeric_records, spec.unit), 13f, muted = true), 8)
        if (page.records.isEmpty()) ui.add(content, ui.text(getString(R.string.health_no_records)), 20)
        page.records.forEach { record ->
            val time = Instant.ofEpochMilli(record.draft.measuredAt).atZone(spec.zone).format(DateTimeFormatter.ofPattern("uuuu-MM-dd HH:mm"))
            ui.add(content, ui.row(healthDisplayValue(record.draft), "$time \u00b7 ${getString(healthRecordSourceResource(record.source))}") {
                if (numeric || fixedVersion) startActivity(Intent(this, HealthRecordRevisionActivity::class.java).putExtra("health_record", record.id).putExtra("health_revision", record.revision).putHealthNavigationFixture(names))
                else startActivity(Intent(this, HealthCenterActivity::class.java).putExtra("health_record", record.id).putHealthNavigationFixture(names))
            }.apply { tag = "health-trend-record-${record.id}" }, 8)
        }
        body.addView(ScrollView(this).apply { addView(content) }, LinearLayout.LayoutParams(-1, 0, 1f))
        val footer = ui.line().apply { setPadding(ui.dp(16), ui.dp(8), ui.dp(16), ui.dp(12)) }
        if (previous.isNotEmpty()) footer.addView(ui.command(R.string.health_previous_page) { cursor = previous.removeAt(previous.lastIndex); load() }, LinearLayout.LayoutParams(0, -2, 1f))
        page.next?.let { next -> footer.addView(ui.command(R.string.health_next_page) { previous += cursor; cursor = next; load() }, LinearLayout.LayoutParams(0, -2, 1f)) }
        if (footer.childCount > 0) body.addView(footer, LinearLayout.LayoutParams(-1, -2))
    }
}

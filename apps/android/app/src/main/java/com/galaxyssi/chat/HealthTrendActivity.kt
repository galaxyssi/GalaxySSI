package com.galaxyssi.chat

import android.app.Activity
import android.app.AlertDialog
import android.app.DatePickerDialog
import android.content.Intent
import android.os.Bundle
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.View
import android.widget.LinearLayout
import android.widget.RadioButton
import android.widget.RadioGroup
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import androidx.core.view.OneShotPreDrawListener
import java.time.LocalDate
import java.time.ZoneId
import java.util.concurrent.CancellationException
import java.util.concurrent.Executors

class HealthTrendActivity : Activity() {
    private data class PointSelection(val spec: HealthTrendSpec, val version: String, val bucket: Int, val field: String)
    private val names by lazy { intent.healthNavigationDatabases() }
    private val ui by lazy { HealthCenterViews(this) }
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private lateinit var body: LinearLayout
    private lateinit var metric: HealthMetric
    private var first = LocalDate.now().minusDays(6); private var last = LocalDate.now(); private var zone = ZoneId.systemDefault()
    private var unit = ""; private var explicitUnit = false; private var preset = 0
    private var aggregation = HealthTrendAggregation.MEAN; private var source = HealthTrendSource(); private var sourceName = ""
    private var active = false; @Volatile private var generation = 0
    private var signal: CancellationSignal? = null; private var dialog: AlertDialog? = null
    private var chart: HealthTrendChart? = null; private var progress: TextView? = null; private var scroll: ScrollView? = null; private var scrollY = 0
    private var notice: TextView? = null; private var retry: TextView? = null; private var version: String? = null
    private var pointSelection: PointSelection? = null
    private var observing = false; private var probing = false; private var probeAgain = false; private var probeSerial = 0
    private val observer = object : android.database.ContentObserver(main) { override fun onChange(selfChange: Boolean) = probeVersion() }
    private val privacyDatabase by lazy { if (names.fixture == null) healthPrivacyDatabaseName() else names.privacy }
    private val privacyObserver = object : android.database.ContentObserver(main) {
        override fun onChange(selfChange: Boolean) {
            val open = dialog; dialog = null; open?.dismiss(); sourceName = ""; load()
        }
    }
    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        val restored = state?.let { Intent().apply { it.keySet().forEach { key -> when (val value = it.get(key)) {
            is String -> putExtra(key, value); is Boolean -> putExtra(key, value)
        } } }.healthTrendSpec() }
        metric = restored?.metric ?: HealthMetric.entries.firstOrNull { it.name == intent.getStringExtra("health_metric") } ?: run { finish(); return }
        unit = restored?.unit ?: metric.units.first(); aggregation = restored?.aggregation ?: aggregation; source = restored?.source ?: source
        restored?.let { first = it.first; last = it.last }; explicitUnit = state?.getBoolean("explicit_unit") ?: false
        preset = state?.getInt("preset")?.coerceIn(0, 3) ?: 0; scrollY = state?.getInt("scroll") ?: 0
        window.statusBarColor = getColor(R.color.page_bg); window.navigationBarColor = getColor(R.color.page_bg)
        if (android.os.Build.VERSION.SDK_INT >= 33) setRecentsScreenshotEnabled(false)
        val root = ui.column().apply { setBackgroundColor(getColor(R.color.page_bg)) }
        root.addView(ui.line().apply {
            addView(ui.icon(R.drawable.ic_navigation_back, R.string.health_back) { finish() })
            addView(ui.text(getString(metric.titleResource()), 19f, bold = true).apply { gravity = Gravity.CENTER }, LinearLayout.LayoutParams(0, -2, 1f))
            addView(ui.icon(R.drawable.ic_health_grid, R.string.health_functions) { startActivity(Intent(this@HealthTrendActivity, HealthCenterActivity::class.java).putExtra("health_functions", true)) })
        }, LinearLayout.LayoutParams(-1, ui.dp(56)))
        body = ui.column(); root.addView(body, LinearLayout.LayoutParams(-1, 0, 1f)); setContentView(root)
    }
    override fun onStart() {
        super.onStart(); if (!::metric.isInitialized) return
        active = true; zone = ZoneId.systemDefault()
        contentResolver.registerContentObserver(HealthRecordStore.changes(this, names.records), false, observer); observing = true
        contentResolver.registerContentObserver(HealthPrivacyStore.changes(this, privacyDatabase), false, privacyObserver)
        if (preset < 3) { last = LocalDate.now(zone); first = last.minusDays(listOf(7L, 30L, 90L)[preset] - 1) }
        load()
    }
    override fun onStop() {
        active = false; scrollY = scroll?.scrollY ?: scrollY; generation++; signal?.cancel(); signal = null
        if (observing) { contentResolver.unregisterContentObserver(observer); contentResolver.unregisterContentObserver(privacyObserver); observing = false }
        probeSerial++; probing = false; probeAgain = false; version = null; notice?.text = ""; notice = null; retry = null
        dialog?.dismiss(); dialog = null; chart?.clear(); chart = null; progress?.text = ""; progress = null
        sourceName = ""; scroll = null; if (::body.isInitialized) body.removeAllViews()
        super.onStop()
    }
    override fun onDestroy() { worker.shutdown(); super.onDestroy() }
    override fun onSaveInstanceState(out: Bundle) {
        if (::metric.isInitialized) {
            val extras = Intent().putHealthTrend(spec()).extras!!; out.putAll(extras)
            out.putBoolean("explicit_unit", explicitUnit); out.putInt("preset", preset); out.putInt("scroll", scroll?.scrollY ?: scrollY)
        }
        super.onSaveInstanceState(out)
    }
    private fun spec() = HealthTrendSpec(metric, first, last, zone, unit, aggregation, source)
    private fun begin(): Pair<Int, CancellationSignal> {
        generation++; signal?.cancel(); probeSerial++; probing = false; probeAgain = false
        val next = CancellationSignal(); signal = next; return generation to next
    }
    private fun load() {
        if (!active) return
        val (token, cancellation) = begin(); val requested = spec(); val autoUnit = !explicitUnit
        version = null; render(null)
        worker.execute {
            fun cancelled() { if (token != generation || cancellation.isCanceled) throw CancellationException() }
            val result = runCatching { HealthPrivacyStore.track(applicationContext, HealthAccessScope.trend(HealthAccessPurpose.TREND, requested), privacyDatabase) { HealthRecordStore(applicationContext, names.records).use { store ->
                cancelled()
                val effective = if (!autoUnit) requested else requested.copy(unit = store.trendRecords(requested, cancelled = ::cancelled, signal = cancellation)
                    .records.firstOrNull()?.draft?.unit?.takeIf { it in metric.selectableUnits } ?: requested.unit)
                val summary = HealthTrendRepository.load(store, effective, ::cancelled, { count -> main.post {
                    if (active && token == generation) progress?.text = getString(R.string.health_trend_progress, count)
                } }, cancellation)
                val name = if (effective.source.originalId.isBlank()) "" else
                    HealthOriginalStore(applicationContext, names.originals, names.originalRoot(applicationContext))
                        .use { it.original(effective.source.originalId)?.name.orEmpty() }
                summary to name
            } } }
            main.post { if (active && token == generation) result.fold({ (summary, name) -> unit = summary.spec.unit; sourceName = name; render(summary) }, {
                val message = getString(when (it) { is HealthTrendChangedException -> R.string.health_trend_changed; is HealthAccessBlocked -> R.string.health_privacy_trend_blocked; else -> R.string.health_storage_error })
                chart?.unavailable(message); progress?.text = ""; notice?.text = message; notice?.visibility = View.VISIBLE; retry?.visibility = View.VISIBLE
                if (it is HealthAccessBlocked) body.addView(ui.command(R.string.health_privacy_title) { startActivity(healthPrivacyIntent()) }.apply { tag = "health-privacy-blocked" })
            }) }
        }
    }
    private fun render(summary: HealthTrendSummary?) {
        version = summary?.version
        chart?.clear(); chart = null; body.removeAllViews()
        val content = ui.column().apply { setPadding(ui.dp(16), ui.dp(16), ui.dp(16), ui.dp(24)) }
        val currentScroll = ScrollView(this).apply { addView(content); tag = "health-trend-scroll" }
        scroll = currentScroll.also { body.addView(it, LinearLayout.LayoutParams(-1, 0, 1f)) }
        ui.add(content, ui.card().apply {
            addView(ui.text(getString(R.string.health_trend_latest), 13f, muted = true))
            val record = summary?.latest
            ui.add(this, ui.text(if (summary == null) getString(R.string.health_loading) else record?.let { healthDisplayValue(it.draft) } ?: getString(R.string.health_no_measurement), 23f, bold = true), 8)
            record?.let { observed ->
                tag = "health-trend-latest-record"
                val time = java.time.Instant.ofEpochMilli(observed.draft.measuredAt).atZone(zone).format(java.time.format.DateTimeFormatter.ofPattern("uuuu-MM-dd HH:mm"))
                addView(ui.text("$time \u00b7 ${getString(healthRecordSourceResource(observed.source))}", 12f, muted = true))
                setOnClickListener { openRecord(observed.id, observed.revision) }; isFocusable = true
            }
        })
        ui.add(content, RadioGroup(this).apply {
            orientation = RadioGroup.HORIZONTAL; background = ui.background(getColor(R.color.button_soft), radius = 8); setPadding(ui.dp(3), ui.dp(3), ui.dp(3), ui.dp(3))
            listOf(R.string.health_trend_7, R.string.health_trend_30, R.string.health_trend_90, R.string.health_trend_custom).forEachIndexed { index, title ->
                addView(RadioButton(this@HealthTrendActivity).apply {
                    id = View.generateViewId(); tag = "health-trend-period-$index"; text = getString(title); textSize = 13f; gravity = Gravity.CENTER; buttonDrawable = null; backgroundTintList = null
                    minimumHeight = ui.dp(48); setTextColor(getColor(R.color.text_primary)); setPadding(ui.dp(2), ui.dp(6), ui.dp(2), ui.dp(6))
                    background = android.graphics.drawable.StateListDrawable().apply {
                        addState(intArrayOf(android.R.attr.state_checked), ui.background(getColor(R.color.surface_bg), radius = 6))
                        addState(intArrayOf(), ui.background(android.graphics.Color.TRANSPARENT, radius = 6))
                    }; isChecked = preset == index
                    setOnClickListener { if (index == 3) { (parent as RadioGroup).let { it.check(it.getChildAt(preset).id) }; customDates() } else {
                        preset = index; last = LocalDate.now(zone); first = last.minusDays(listOf(7L, 30L, 90L)[index] - 1); scrollY = 0; load()
                    } }
                }, RadioGroup.LayoutParams(0, -2, 1f))
            }
        }, 16)
        ui.add(content, ui.text("$first \u2014 $last \u00b7 ${zone.id}", 12f, muted = true), 8)
        ui.add(content, ui.row(getString(R.string.health_trend_source), when {
            source.manualOnly -> getString(R.string.health_source_manual)
            source.originalId.isBlank() -> getString(R.string.health_trend_all_sources)
            else -> sourceName.ifBlank { getString(R.string.health_trend_original_source, source.originalId.take(8)) }
        }) { chooseSources() }.apply { tag = "health-trend-source" }, 8)
        ui.add(content, ui.row(getString(R.string.health_unit), unit.ifBlank { getString(R.string.health_unit_not_applicable) }) {
            choose(R.string.health_unit, metric.selectableUnits.map { it.ifBlank { getString(R.string.health_unit_not_applicable) } }) { index -> unit = metric.selectableUnits[index]; explicitUnit = true; load() }
        })
        ui.add(content, ui.row(getString(R.string.health_trend_aggregation), getString(aggregation.titleResource())) {
            choose(R.string.health_trend_aggregation, HealthTrendAggregation.entries.map { getString(it.titleResource()) }) { aggregation = HealthTrendAggregation.entries[it]; load() }
        }.apply { tag = "health-trend-aggregation" })
        val focused = if (summary == null) null else pointSelection?.let { selection ->
            if (selection.spec == summary.spec && selection.version == summary.version)
                summary.points.singleOrNull { it.bucket == selection.bucket && it.field == selection.field }
            else null
        }
        if (summary != null && focused == null) pointSelection = null
        chart = HealthTrendChart(this, ::openPoint).apply { tag = "health-trend-chart"; bind(summary, focused) }
        ui.add(content, requireNotNull(chart), 12); chart!!.layoutParams.height = ui.dp(240)
        val legend = ui.line()
        metric.requiredFields.forEachIndexed { index, field -> legend.addView(ui.text(getString(healthFieldResource(field)), 12f).apply {
            setTextColor(if (index == 0) HealthTrendChart.GREEN else HealthTrendChart.BLUE)
        }, LinearLayout.LayoutParams(0, -2, 1f)) }
        content.addView(legend)
        progress = ui.text(if (summary == null) getString(R.string.health_loading) else getString(R.string.health_trend_counts, summary.eligible, summary.numericDays, summary.reportedDays, summary.missingDays), 14f, muted = true)
            .apply { tag = "health-trend-counts"; minimumHeight = ui.dp(48) }.also { ui.add(content, it, 12) }
        summary?.let {
            val time = java.time.Instant.ofEpochMilli(it.calculatedAt).atZone(zone).format(java.time.format.DateTimeFormatter.ofPattern("HH:mm:ss"))
            ui.add(content, ui.text(getString(R.string.health_trend_calculated, time), 12f, muted = true), 6)
            ui.add(content, ui.text(getString(R.string.health_trend_excluded, it.nonNumeric, it.otherUnits), 12f, muted = true), 6)
            ui.add(content, ui.text(getString(R.string.health_trend_bucket, it.spec.bucketDays), 12f, muted = true), 6)
            ui.add(content, ui.row(getString(R.string.health_all_records), getString(R.string.health_record_count, it.total)) { openRecords(it.spec) }, 16)
        }
        notice = ui.text("", 13f, muted = true).apply { visibility = View.GONE }.also { ui.add(content, it, 8) }
        retry = ui.command(R.string.health_trend_refresh) { load() }.apply { visibility = View.GONE }.also { ui.add(content, it, 8) }
        ui.add(content, ui.text(getString(R.string.health_not_diagnosis), 12f, muted = true), 12)
        body.addView(ui.column().apply { setPadding(ui.dp(16), ui.dp(8), ui.dp(16), ui.dp(12)); addView(ui.command(R.string.health_add_measurement) {
            startActivity(Intent(this@HealthTrendActivity, HealthCenterActivity::class.java).putExtra("health_manual", true)
                .putExtra("health_metric", metric.name).putHealthNavigationFixture(names))
        }) }, LinearLayout.LayoutParams(-1, -2))
        OneShotPreDrawListener.add(currentScroll) { if (active && scroll === currentScroll) currentScroll.scrollTo(0, scrollY) }
        if (summary != null) probeVersion()
    }
    private fun probeVersion() {
        val displayed = version ?: return
        if (!active) return
        if (probing) { probeAgain = true; return }
        probing = true; val ticket = ++probeSerial; val token = generation
        worker.execute {
            val result = runCatching { HealthRecordStore(applicationContext, names.records).use { it.metricVersion(metric) } }
            main.post {
                if (ticket != probeSerial) return@post
                probing = false
                if (active && token == generation && version == displayed) result.fold({ current ->
                    if (current != displayed) { notice?.text = getString(R.string.health_trend_stale); notice?.visibility = View.VISIBLE; retry?.visibility = View.VISIBLE }
                }, { notice?.text = getString(R.string.health_storage_error); notice?.visibility = View.VISIBLE; retry?.visibility = View.VISIBLE })
                if (active && probeAgain) { probeAgain = false; probeVersion() }
            }
        }
    }
    private fun openRecord(id: String, revision: Int) {
        startActivity(Intent(this, HealthRecordRevisionActivity::class.java).putExtra("health_record", id)
            .putExtra("health_revision", revision).putHealthNavigationFixture(names))
    }
    private fun openPoint(point: HealthTrendPoint) {
        val snapshot = version ?: return
        val selected = spec()
        pointSelection = PointSelection(selected, snapshot, point.bucket, point.field)
        if (point.count == 1L && point.recordId.isNotBlank()) openRecord(point.recordId, point.recordRevision)
        else openRecords(selected.copy(first = point.first, last = point.last), point.field)
    }
    private fun openRecords(spec: HealthTrendSpec, field: String? = null) { startActivity(Intent(this, HealthTrendRecordsActivity::class.java).putHealthTrend(spec).putExtra("health_privacy_test_db", privacyDatabase).apply {
        putHealthNavigationFixture(names)
        if (field != null) {
            putExtra("health_numeric", true)
            putExtra("health_point_field", field)
            putExtra("health_version", version)
        }
    }) }
    private fun choose(title: Int, values: List<String>, selected: (Int) -> Unit) {
        dialog?.dismiss(); dialog = AlertDialog.Builder(this).setTitle(title).setItems(values.toTypedArray()) { _, index -> selected(index) }
            .setNegativeButton(R.string.common_cancel, null).show()
    }
    private fun chooseSources() { choose(R.string.health_trend_source, listOf(getString(R.string.health_trend_all_sources), getString(R.string.health_source_manual), getString(R.string.health_trend_choose_original))) { index ->
        when (index) { 0 -> { source = HealthTrendSource(); sourceName = ""; load() }; 1 -> { source = HealthTrendSource(manualOnly = true); sourceName = ""; load() }; else -> sourcePicker() }
    } }
    private fun sourcePicker(after: String = "", history: List<String> = emptyList()) {
        val (token, cancellation) = begin(); dialog?.dismiss()
        val wait = AlertDialog.Builder(this).setTitle(R.string.health_trend_source).setMessage(R.string.health_loading).setNegativeButton(R.string.common_cancel, null).create()
        dialog = wait; wait.setOnDismissListener { if (dialog === wait) { dialog = null; if (active) load() } }; wait.show()
        val requested = spec()
        worker.execute {
            val result = runCatching { HealthPrivacyStore.track(applicationContext, HealthAccessScope.trend(HealthAccessPurpose.TREND_SOURCES, requested), privacyDatabase) { HealthRecordStore(applicationContext, names.records).use { store ->
                val ids = store.trendSourceIds(requested, after, cancellation)
                HealthOriginalStore(applicationContext, names.originals, names.originalRoot(applicationContext)).use { originals -> ids to ids.take(30).map { id ->
                    (originals.original(id)?.name ?: getString(R.string.health_original_missing)) + " \u00b7 " + id.take(8)
                } }
            } } }
            main.post { if (!active || token != generation || dialog !== wait) return@post
                result.fold({ (ids, labels) ->
                    wait.setOnDismissListener(null); wait.dismiss()
                    val builder = AlertDialog.Builder(this).setTitle(R.string.health_trend_source).setNegativeButton(R.string.common_close, null)
                    if (labels.isEmpty()) builder.setMessage(R.string.health_trend_no_sources) else builder.setItems(labels.toTypedArray()) { _, index -> source = HealthTrendSource(originalId = ids[index]); sourceName = "" }
                    if (ids.size > 30) builder.setPositiveButton(R.string.health_next_page, null)
                    if (history.isNotEmpty()) builder.setNeutralButton(R.string.health_previous_page, null)
                    val choice = builder.create(); dialog = choice
                    choice.setOnDismissListener { if (dialog === choice) { dialog = null; if (active) load() } }
                    choice.setOnShowListener {
                        fun page(next: String, previous: List<String>) { choice.setOnDismissListener(null); choice.dismiss(); dialog = null; sourcePicker(next, previous) }
                        if (ids.size > 30) choice.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener { page(ids[29], history + after) }
                        if (history.isNotEmpty()) choice.getButton(AlertDialog.BUTTON_NEUTRAL).setOnClickListener { page(history.last(), history.dropLast(1)) }
                    }; choice.show()
                }, { wait.setMessage(getString(if (it is HealthAccessBlocked) R.string.health_privacy_trend_blocked else R.string.health_storage_error)) })
            }
        }
    }
    private fun customDates() {
        fun picker(initial: LocalDate, title: Int, done: (LocalDate) -> Unit) {
            dialog?.dismiss(); dialog = DatePickerDialog(this, { _, year, month, day -> done(LocalDate.of(year, month + 1, day)) }, initial.year, initial.monthValue - 1, initial.dayOfMonth)
                .apply { setTitle(title); datePicker.minDate = 0; datePicker.maxDate = System.currentTimeMillis(); show() }
        }
        picker(first, R.string.health_trend_from) { start -> picker(last.coerceAtLeast(start), R.string.health_trend_until) { end ->
            if (end < start) Toast.makeText(this, R.string.health_trend_invalid_dates, Toast.LENGTH_LONG).show()
            else { first = start; last = end; preset = 3; scrollY = 0; load() }
        } }
    }
}

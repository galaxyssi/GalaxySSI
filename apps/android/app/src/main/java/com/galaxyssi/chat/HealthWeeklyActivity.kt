package com.galaxyssi.chat

import android.app.Activity
import android.content.Intent
import android.database.ContentObserver
import android.net.Uri
import android.os.Bundle
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper
import android.widget.CheckBox
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import java.time.LocalDate
import java.time.ZoneId
import java.util.concurrent.Executors

class HealthWeeklyActivity : Activity() {
    private enum class Screen { SUMMARY, OPTIONS, REVIEW }
    private val ui by lazy { HealthCenterViews(this) }
    private val text by lazy { HealthWeeklyText(this) }
    private val main = Handler(Looper.getMainLooper())
    private val io = Executors.newSingleThreadExecutor()
    private val names by lazy { intent.healthNavigationDatabases() }
    private val database by lazy {
        val name = intent.getStringExtra("health_weekly_test_db").orEmpty()
        if (BuildConfig.DEBUG && name.startsWith("health-weekly-test-") && name.endsWith(".db") &&
            HealthProfilePolicy.uuid(name.removePrefix("health-weekly-test-").removeSuffix(".db"))) name else names.records
    }
    private val privacy by lazy { if (names.fixture == null) healthPrivacyDatabaseName() else names.privacy }
    private lateinit var body: LinearLayout
    private lateinit var title: TextView
    private lateinit var zone: ZoneId
    private lateinit var end: LocalDate
    private var screen = Screen.SUMMARY
    private var metrics = healthWeeklyMetrics.toSet()
    private var summaryMetrics = healthWeeklyMetrics.toSet()
    private var summaryComparison = true
    private var linked: HealthWeeklyStamp? = null
    private val fromSleepReminder by lazy { intent.getBooleanExtra("health_weekly_from_sleep_reminder", false) }
    private var includeRecords = false
    private var comparison = true
    private var active = false
    private var request = 0
    private var signal: CancellationSignal? = null
    private var stamp: HealthWeeklyStamp? = null
    private var pendingSave: HealthWeeklyStamp? = null
    private var writing = false
    private var saveError: Throwable? = null
    private var saved = false
    private var cursor: HealthPageCursor? = null
    private val history = arrayListOf<HealthPageCursor?>()
    private val observer = object : ContentObserver(main) {
        override fun onChange(selfChange: Boolean) {
            if (!active || writing) return
            if (screen != Screen.OPTIONS) load()
        }
    }

    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        linked = if (state != null) state.getBundle("linked")?.weeklyStamp()
            else intent.getBundleExtra(HEALTH_WEEKLY_HANDOFF)?.weeklyStamp()?.takeUnless { it.scope.records }
        if (state == null && intent.hasExtra(HEALTH_WEEKLY_HANDOFF) && linked == null) {
            Toast.makeText(this, R.string.health_storage_error, Toast.LENGTH_LONG).show()
            finish()
            return
        }
        val initial = linked?.scope
        zone = state?.getString("zone")?.let(ZoneId::of) ?: initial?.zone ?: ZoneId.systemDefault()
        end = state?.getString("end")?.let(LocalDate::parse) ?: initial?.end ?: LocalDate.now(zone).minusDays(1)
        screen = state?.getString("screen")?.let(Screen::valueOf) ?: Screen.SUMMARY
        summaryMetrics = state?.getStringArrayList("summary_metrics")?.map(HealthMetric::valueOf)?.toSet()
            ?: initial?.metrics ?: healthWeeklyMetrics.toSet()
        summaryComparison = state?.getBoolean("summary_comparison", initial?.comparison ?: true) ?: initial?.comparison ?: true
        metrics = state?.getStringArrayList("metrics")?.map(HealthMetric::valueOf)?.toSet() ?: summaryMetrics
        includeRecords = state?.getBoolean("records") ?: false
        comparison = state?.getBoolean("comparison", true) ?: summaryComparison
        stamp = state?.getBundle("stamp")?.weeklyStamp()
        pendingSave = state?.getBundle("save")?.weeklyStamp()
        body = healthProfileBody(R.string.health_weekly_title) { back() }
        title = ((body.parent as LinearLayout).getChildAt(0) as LinearLayout).getChildAt(1) as TextView
    }
    override fun onSaveInstanceState(state: Bundle) {
        if (!::body.isInitialized) { super.onSaveInstanceState(state); return }
        state.putString("zone", zone.id); state.putString("end", end.toString()); state.putString("screen", screen.name)
        state.putStringArrayList("metrics", ArrayList(metrics.map { it.name }))
        state.putStringArrayList("summary_metrics", ArrayList(summaryMetrics.map { it.name }))
        state.putBoolean("summary_comparison", summaryComparison)
        linked?.let { state.putBundle("linked", it.bundle()) }
        state.putBoolean("records", includeRecords); state.putBoolean("comparison", comparison)
        stamp?.let { state.putBundle("stamp", it.bundle()) }
        pendingSave?.let { state.putBundle("save", it.bundle()) }
        super.onSaveInstanceState(state)
    }
    override fun onStart() {
        super.onStart()
        if (!::body.isInitialized) return
        active = true
        contentResolver.registerContentObserver(HealthRecordStore.changes(this, database), false, observer)
        contentResolver.registerContentObserver(HealthPrivacyStore.changes(this, privacy), false, observer)
        refresh()
    }
    override fun onStop() {
        if (!active) { super.onStop(); return }
        active = false; request++; signal?.cancel(); signal = null; body.removeAllViews()
        contentResolver.unregisterContentObserver(observer)
        super.onStop()
    }
    override fun onDestroy() { io.shutdown(); super.onDestroy() }
    @Deprecated("Native back callback") override fun onBackPressed() = back()
    private fun back() {
        if (writing || pendingSave != null) return
        saved = false; saveError = null; stamp = null; resetPages()
        when (screen) {
            Screen.SUMMARY -> finish()
            Screen.OPTIONS -> { screen = Screen.SUMMARY; refresh() }
            Screen.REVIEW -> { screen = Screen.OPTIONS; refresh() }
        }
    }

    private fun resetPages() { cursor = null; history.clear() }
    private fun refresh() {
        title.setText(when (screen) {
            Screen.SUMMARY -> R.string.health_weekly_title
            Screen.OPTIONS -> R.string.health_weekly_options
            Screen.REVIEW -> R.string.health_weekly_preview
        })
        when {
            writing || pendingSave != null -> status(R.string.health_export_saving)
            screen == Screen.OPTIONS -> renderOptions()
            else -> load()
        }
    }
    private fun scope(review: Boolean) = if (review) HealthWeeklyScope(end, zone, metrics, includeRecords, comparison)
        else HealthWeeklyScope(end, zone, summaryMetrics, comparison = summaryComparison)
    private fun status(message: Int): LinearLayout = healthProfileContent(body).apply { addView(ui.text(getString(message), 15f, muted = true)) }
    private fun load(known: HealthWeeklySnapshot? = null) {
        if (!active) return
        val review = screen == Screen.REVIEW
        val selected = scope(review)
        val reference = linked
        val expected = if (review) stamp else reference
        val after = cursor
        val token = ++request
        signal?.cancel()
        val cancellation = CancellationSignal().also { signal = it }
        status(R.string.health_loading)
        io.execute {
            val result = runCatching {
                HealthPrivacyStore.track(applicationContext, HealthAccessScope.weekly(selected), privacy) {
                    HealthRecordStore(applicationContext, database).use { store ->
                        val bound = expected ?: reference?.let { base ->
                            val versions = store.metricVersions(selected.metrics)
                            if (base.versions.any { (metric, version) -> metric in selected.metrics && versions[metric] != version })
                                throw HealthWeeklyChanged()
                            HealthWeeklyStamp(selected, versions, System.currentTimeMillis())
                        }
                        val snapshot = known?.also { HealthWeeklyRepository.requireCurrent(store, it.stamp) }
                            ?: HealthWeeklyRepository.calculate(store, selected, bound, cancellation)
                        val rows = if (selected.records && snapshot.recordCount <= HealthWeeklyScope.MAX_PDF_RECORDS)
                            HealthWeeklyRepository.page(store, snapshot.stamp, after, cancellation) else null
                        snapshot to rows
                    }
                }
            }
            main.post {
                if (!active || request != token) return@post
                result.fold({ (snapshot, records) ->
                    if (review) stamp = snapshot.stamp
                    renderReport(snapshot, records, review)
                }, ::renderError)
            }
        }
    }

    private fun action(label: Int, key: String, secondary: Boolean = false, block: () -> Unit) = ui.command(label, block).apply {
        tag = key; setPadding(ui.dp(8), ui.dp(8), ui.dp(8), ui.dp(8))
        if (secondary) { background = ui.background(stroke = getColor(R.color.separator), radius = 8); setTextColor(getColor(R.color.text_primary)) }
    }
    private fun renderReport(snapshot: HealthWeeklySnapshot, rows: HealthWeeklyRecords?, review: Boolean) {
        val content = healthProfileContent(body)
        content.addView(ui.text(text.range(snapshot.scope), 19f, bold = true).apply { tag = "health-weekly-range" })
        ui.add(content, ui.text(text.version(snapshot), 12f, muted = true), 6)
        if (linked != null && !review) ui.add(content,
            ui.text(getString(if (fromSleepReminder) R.string.health_weekly_reminder_scope else R.string.health_weekly_assistant_scope), 13f, muted = true)
                .apply { tag = "health-weekly-linked" }, 4)
        if (!review) ui.add(content, ui.line().apply {
            val previous = action(R.string.health_weekly_previous, "health-weekly-previous", true) { linked = null; end = end.minusDays(7); load() }
            val next = action(R.string.health_weekly_next, "health-weekly-next", true) {
                linked = null; end = minOf(end.plusDays(7), LocalDate.now(zone).minusDays(1)); load()
            }
            previous.isEnabled = !end.minusDays(27).isBefore(LocalDate.of(1970, 1, 2))
            next.isEnabled = end.isBefore(LocalDate.now(zone).minusDays(1))
            addView(previous, LinearLayout.LayoutParams(0, -2, 1f).apply { marginEnd = ui.dp(4) })
            addView(next, LinearLayout.LayoutParams(0, -2, 1f).apply { marginStart = ui.dp(4) })
        }, 12)
        ui.add(content, ui.text(getString(R.string.health_weekly_metrics), 18f, bold = true), 20)
        snapshot.stats.forEach { stat ->
            val label = "${text.title(stat.metric)} \u00b7 ${text.summary(stat)}"
            val view = if (!review && stat.records > 0) ui.profileRow(label, text.coverage(stat)) { openCohort(snapshot, stat.metric) }
                else ui.column().apply { addView(ui.text(label, bold = true)); ui.add(this, ui.text(text.coverage(stat), 13f, muted = true), 4) }
            ui.add(content, view.apply { tag = "health-weekly-stat-${stat.metric.name}" }, 10)
        }
        val observations = text.comparison(snapshot)
        if (observations.isNotEmpty()) {
            ui.add(content, ui.text(getString(R.string.health_weekly_attention), 18f, bold = true), 20)
            observations.forEach { ui.add(content, ui.text(it, 14f), 7) }
            if (!review && snapshot.sleep?.baseline?.records?.let { it > 0 } == true) {
                ui.add(content, ui.profileRow(getString(R.string.health_weekly_baseline_records)) { openCohort(snapshot, HealthMetric.SLEEP_DURATION, true) })
            }
        }
        ui.add(content, ui.text(getString(R.string.health_weekly_method), 13f, muted = true), 16)
        ui.add(content, ui.text(getString(R.string.health_weekly_exclusions), 13f, muted = true), 8)
        ui.add(content, ui.text(getString(R.string.health_not_diagnosis), 13f, muted = true), 8)
        if (!review) {
            ui.add(content, action(R.string.health_weekly_prepare, "health-weekly-prepare") { screen = Screen.OPTIONS; refresh() }, 16)
            return
        }
        if (snapshot.scope.records) {
            ui.add(content, ui.text(getString(R.string.health_weekly_raw_count, snapshot.recordCount), 17f, bold = true), 20)
            if (rows == null) {
                ui.add(content, ui.text(getString(R.string.health_weekly_limit, HealthWeeklyScope.MAX_PDF_RECORDS), 14f, muted = true), 10)
                ui.add(content, action(R.string.health_weekly_options, "health-weekly-change-scope", true) { back() }, 12)
                return
            }
            rows.records.forEach { record ->
                val (header, values) = text.raw(record, snapshot.scope.zone)
                ui.add(content, ui.column().apply {
                    addView(ui.text(header, 13f, bold = true)); ui.add(this, ui.text(values, 13f), 4)
                    ui.add(this, ui.text(text.rawVersion(record), 11f, muted = true), 4)
                }
                    .apply { tag = "health-weekly-record" }, 10)
            }
            if (history.isNotEmpty()) ui.add(content, action(R.string.health_previous_page, "health-weekly-raw-prev", true) {
                cursor = history.removeAt(history.lastIndex); load(snapshot)
            }, 10)
            rows.next?.let { next -> ui.add(content, action(R.string.health_next_page, "health-weekly-raw-next", true) {
                history += cursor; cursor = next; load(snapshot)
            }, 10) }
        }
        if (saved) ui.add(content, ui.text(getString(R.string.health_weekly_saved), 15f, bold = true).apply { tag = "health-weekly-saved" }, 12)
        saveError?.let { ui.add(content, ui.text(getString(errorResource(it)), 14f), 12) }
        val confirm = CheckBox(this).apply { setText(R.string.health_weekly_confirm); isSaveEnabled = false; tag = "health-weekly-consent" }
        ui.add(content, confirm, 16)
        val save = action(R.string.health_weekly_save, "health-weekly-save") {
            if (confirm.isChecked && pendingSave == null && !writing) chooseDestination(snapshot)
        }.apply { isEnabled = false; alpha = .5f }
        confirm.setOnCheckedChangeListener { _, checked -> save.isEnabled = checked; save.alpha = if (checked) 1f else .5f }
        ui.add(content, save, 8)
    }

    private fun openCohort(snapshot: HealthWeeklySnapshot, metric: HealthMetric, baseline: Boolean = false) {
        val s = snapshot.scope
        val spec = HealthTrendSpec(metric, if (baseline) s.baselineFirst else s.first, if (baseline) s.baselineLast else s.end,
            s.zone, metric.units.first())
        startActivity(Intent(this, HealthTrendRecordsActivity::class.java).putHealthTrend(spec)
            .putExtra("health_fixed_version", true).putExtra("health_version", snapshot.versions.getValue(metric))
            .putExtra("health_privacy_test_db", privacy).putHealthNavigationFixture(names))
    }
    private fun renderOptions() {
        val content = healthProfileContent(body)
        content.addView(ui.text(getString(R.string.health_weekly_options), 18f, bold = true))
        lateinit var preview: TextView
        healthWeeklyMetrics.forEach { metric -> ui.add(content, CheckBox(this).apply {
            text = this@HealthWeeklyActivity.text.title(metric); isChecked = metric in metrics; isSaveEnabled = false
            tag = "health-weekly-select-${metric.name}"
            setOnCheckedChangeListener { _, checked ->
                metrics = if (checked) metrics + metric else metrics - metric
                preview.isEnabled = metrics.isNotEmpty(); preview.alpha = if (preview.isEnabled) 1f else .5f
            }
        }, 5) }
        ui.add(content, CheckBox(this).apply {
            setText(R.string.health_weekly_raw); isChecked = includeRecords; isSaveEnabled = false; tag = "health-weekly-include-raw"
            setOnCheckedChangeListener { _, checked -> includeRecords = checked }
        }, 12)
        ui.add(content, CheckBox(this).apply {
            setText(R.string.health_weekly_include_comparison); isChecked = comparison; isSaveEnabled = false
            tag = "health-weekly-include-comparison"; setOnCheckedChangeListener { _, checked -> comparison = checked }
        }, 5)
        preview = action(R.string.health_weekly_preview, "health-weekly-preview-action") {
            if (metrics.isNotEmpty()) { stamp = null; resetPages(); screen = Screen.REVIEW; saved = false; saveError = null; refresh() }
        }.apply { isEnabled = metrics.isNotEmpty(); alpha = if (isEnabled) 1f else .5f }
        ui.add(content, preview, 16)
    }

    private fun chooseDestination(snapshot: HealthWeeklySnapshot) {
        pendingSave = snapshot.stamp
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE).setType("application/pdf")
            .putExtra(Intent.EXTRA_TITLE, "GalaxySSI-Health-${snapshot.scope.first}-${snapshot.scope.end}.pdf")
        try { startActivityForResult(intent, SAVE) } catch (_: android.content.ActivityNotFoundException) {
            pendingSave = null; Toast.makeText(this, R.string.health_import_save_failed, Toast.LENGTH_LONG).show()
        }
    }
    @Deprecated("Storage Access Framework result") override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != SAVE) return
        val expected = pendingSave; pendingSave = null
        val uri = data?.data
        if (expected == null || resultCode != RESULT_OK || uri?.scheme != "content") { if (active) refresh(); return }
        writing = true; saved = false; saveError = null; signal?.cancel(); request++
        if (active) refresh()
        io.execute {
            val result = runCatching { save(expected, uri) }
            main.post {
                writing = false; saved = result.isSuccess; saveError = result.exceptionOrNull()
                if (active) refresh()
            }
        }
    }
    private fun save(expected: HealthWeeklyStamp, uri: Uri) {
        var opened = false
        try {
            HealthPrivacyStore(applicationContext, privacy).use { access ->
                access.track(HealthAccessScope.weekly(expected.scope, save = true)) {
                    val authorization = access.policy()
                    HealthRecordStore(applicationContext, database).use { store ->
                        val report = HealthWeeklyRepository.calculate(store, expected.scope, expected)
                        HealthWeeklyPdf.render(applicationContext, store, report) { document ->
                            val current = access.policy()
                            if (!current.metrics || current.version != authorization.version) throw HealthAccessBlocked()
                            contentResolver.openOutputStream(uri, "wt")?.use { output ->
                                opened = true; document.writeTo(output)
                            } ?: error("Weekly report destination unavailable")
                            HealthWeeklyRepository.requireCurrent(store, expected)
                        }
                    }
                }
            }
        } catch (failure: Exception) {
            if (opened) runCatching { android.provider.DocumentsContract.deleteDocument(contentResolver, uri) }
            throw failure
        }
    }
    private fun errorResource(failure: Throwable) = when (failure) {
        is HealthAccessBlocked -> R.string.health_privacy_trend_blocked
        is HealthWeeklyChanged -> R.string.health_weekly_changed
        else -> R.string.health_storage_error
    }
    private fun renderError(failure: Throwable) {
        val staleLink = failure is HealthWeeklyChanged && linked != null && screen == Screen.SUMMARY
        val content = status(when {
            staleLink && fromSleepReminder -> R.string.health_weekly_reminder_changed
            staleLink -> R.string.health_weekly_assistant_changed
            else -> errorResource(failure)
        })
        if (failure is HealthAccessBlocked) ui.add(content, action(R.string.health_privacy_title, "health-weekly-blocked") { startActivity(healthPrivacyIntent()) }, 16)
        if (failure is HealthWeeklyChanged && screen == Screen.REVIEW) {
            ui.add(content, action(R.string.health_weekly_review_again, "health-weekly-review-again") {
                linked = null; stamp = null; resetPages(); saveError = null; saved = false; load()
            }, 16)
        } else if (staleLink) {
            ui.add(content, action(R.string.health_weekly_review_again, "health-weekly-refresh-link") {
                linked = null; load()
            }, 16)
        } else ui.add(content, action(R.string.common_retry, "health-weekly-retry") { load() }, 16)
    }

    companion object { private const val SAVE = 65 }
}

private const val HEALTH_WEEKLY_HANDOFF = "health_weekly_handoff"

internal fun Intent.putHealthWeeklyHandoff(stamp: HealthWeeklyStamp, fromSleepReminder: Boolean = false): Intent {
    require(!stamp.scope.records)
    if (fromSleepReminder) putExtra("health_weekly_from_sleep_reminder", true)
    return putExtra(HEALTH_WEEKLY_HANDOFF, stamp.bundle())
}

private fun HealthWeeklyStamp.bundle() = Bundle().apply {
    putString("end", scope.end.toString()); putString("zone", scope.zone.id); putLong("created", calculatedAt)
    putBoolean("records", scope.records); putBoolean("comparison", scope.comparison)
    putBundle("versions", Bundle().apply { versions.forEach { (metric, version) -> putString(metric.name, version) } })
}
private fun Bundle.weeklyStamp(): HealthWeeklyStamp? = runCatching {
    val tokens = requireNotNull(getBundle("versions"))
    val versions = tokens.keySet().associate { HealthMetric.valueOf(it) to requireNotNull(tokens.getString(it)) }
    val selected = HealthWeeklyScope(LocalDate.parse(getString("end")), ZoneId.of(getString("zone")), versions.keys,
        getBoolean("records"), getBoolean("comparison"))
    HealthWeeklyStamp(selected, versions, getLong("created"))
}.getOrNull()

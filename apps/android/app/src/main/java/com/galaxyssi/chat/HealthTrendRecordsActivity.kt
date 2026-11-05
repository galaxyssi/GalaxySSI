package com.galaxyssi.chat

import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.database.ContentObserver
import android.os.Bundle
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.Toast
import androidx.core.view.OneShotPreDrawListener
import java.time.Instant
import java.time.format.DateTimeFormatter
import java.util.concurrent.CancellationException
import java.util.concurrent.Executors

/** An aggregate point opens its own date/unit/source cohort, never a full unfiltered history. */
class HealthTrendRecordsActivity : Activity() {
    private data class Page(val records: HealthRecordPage, val version: String, val point: HealthTrendPoint?, val sourceName: String)
    private val names by lazy { intent.healthNavigationDatabases() }
    private val ui by lazy { HealthCenterViews(this) }
    private val worker = Executors.newSingleThreadExecutor(); private val main = Handler(Looper.getMainLooper())
    private lateinit var body: LinearLayout; private lateinit var spec: HealthTrendSpec
    private var numeric = false; private var active = false; @Volatile private var generation = 0
    private var fixedVersion = false
    private var manageBluetooth = false
    private var deletionBusy = false
    private var deletionDialog: AlertDialog? = null
    private var deletionPreviewGeneration = 0
    private var pointField: String? = null
    private var audit: HealthTrendPoint? = null
    private var sourceName = ""
    private var scroll: ScrollView? = null
    private var scrollY = 0
    private var signal: CancellationSignal? = null; private var cursor: HealthPageCursor? = null
    private var version: String? = null
    private val previous = arrayListOf<HealthPageCursor?>()
    private val privacyDatabase by lazy { if (names.fixture == null) healthPrivacyDatabaseName() else names.privacy }
    private val privacyObserver = object : android.database.ContentObserver(main) {
        override fun onChange(selfChange: Boolean) {
            if (!active) return
            deletionDialog?.dismiss(); deletionDialog = null
            scrollY = scroll?.scrollY ?: scrollY
            audit = null
            sourceName = ""
            load()
        }
    }
    private val checkVersion = Runnable { verifyVisibleVersion() }
    private val recordsObserver = object : ContentObserver(main) {
        override fun onChange(selfChange: Boolean) {
            if (!active) return
            main.removeCallbacks(checkVersion)
            main.postDelayed(checkVersion, 120)
        }
    }
    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        spec = intent.healthTrendSpec() ?: run { finish(); return }; numeric = intent.getBooleanExtra("health_numeric", false)
        fixedVersion = intent.getBooleanExtra("health_fixed_version", false)
        pointField = intent.getStringExtra("health_point_field")
        manageBluetooth = intent.getBooleanExtra("health_manage_bluetooth_history", false) &&
            !fixedVersion && !numeric && spec.metric == HealthMetric.BLOOD_PRESSURE && spec.source.bluetoothGroup.isNotEmpty()
        if (pointField != null && (!numeric || pointField !in spec.metric.requiredFields)) { finish(); return }
        version = state?.getString("version") ?: intent.getStringExtra("health_version")
        if ((numeric || fixedVersion) && version == null) { finish(); return }
        scrollY = state?.getInt("scroll") ?: 0
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
    override fun onStart() { super.onStart(); if (::body.isInitialized) {
        active = true
        contentResolver.registerContentObserver(HealthPrivacyStore.changes(this, privacyDatabase), false, privacyObserver)
        if (pointField != null) contentResolver.registerContentObserver(HealthRecordStore.changes(this, names.records), false, recordsObserver)
        load()
    } }
    override fun onStop() {
        if (active) {
            contentResolver.unregisterContentObserver(privacyObserver)
            if (pointField != null) contentResolver.unregisterContentObserver(recordsObserver)
        }
        scrollY = scroll?.scrollY ?: scrollY
        scroll = null
        audit = null
        sourceName = ""
        main.removeCallbacks(checkVersion)
        active = false; generation++; signal?.cancel(); signal = null; if (::body.isInitialized) body.removeAllViews(); super.onStop()
    }
    override fun onDestroy() { worker.shutdown(); super.onDestroy() }
    override fun onPause() {
        deletionPreviewGeneration++
        deletionDialog?.dismiss(); deletionDialog = null
        super.onPause()
    }
    override fun onSaveInstanceState(state: Bundle) {
        cursor?.let { state.putLong("cursor_time", it.measuredAt); state.putString("cursor_id", it.id) }
        state.putStringArrayList("previous", ArrayList(previous.map { if (it == null) "" else "${it.measuredAt}|${it.id}" }))
        version?.let { state.putString("version", it) }
        state.putInt("scroll", scroll?.scrollY ?: scrollY)
        super.onSaveInstanceState(state)
    }
    private fun load() {
        val token = ++generation; signal?.cancel(); val cancellation = CancellationSignal(); signal = cancellation; val after = cursor
        val expected = version
        val priorAudit = audit
        val priorSource = sourceName
        scroll = null
        body.removeAllViews(); body.addView(ui.text(getString(R.string.health_loading), 14f, muted = true))
        worker.execute {
            val result = runCatching { HealthPrivacyStore.track(applicationContext, HealthAccessScope.trend(HealthAccessPurpose.TREND_RECORDS, spec), privacyDatabase) { HealthRecordStore(applicationContext, names.records).use { store ->
                fun cancelled() { if (token != generation || cancellation.isCanceled) throw CancellationException() }
                val before = store.metricVersion(spec.metric)
                if (expected != null && expected != before) throw HealthTrendChangedException()
                val point = priorAudit ?: pointField?.let { field ->
                    HealthTrendRepository.point(store, spec, field, before, ::cancelled, cancellation)
                }
                val label = when {
                    point == null -> ""
                    priorAudit != null -> priorSource
                    spec.source.bluetoothGroup.isNotEmpty() ->
                        store.trendBluetoothLabel(spec, spec.source.bluetoothGroup, cancellation).orEmpty()
                    spec.source.originalId.isNotBlank() ->
                        HealthOriginalStore(applicationContext, names.originals, names.originalRoot(applicationContext))
                            .use { it.original(spec.source.originalId)?.name.orEmpty() }
                    else -> ""
                }
                val page = store.trendRecords(spec, after, numeric, ::cancelled, cancellation)
                if (store.metricVersion(spec.metric) != before) throw HealthTrendChangedException()
                Page(page, before, point, label)
            } } }
            main.post { if (active && token == generation) result.fold({ page ->
                version = page.version; audit = page.point; sourceName = page.sourceName; render(page.records)
            }, ::failure) }
        }
    }
    private fun verifyVisibleVersion() {
        val expected = version ?: return
        val token = generation
        if (!active) return
        worker.execute {
            val current = runCatching { HealthRecordStore(applicationContext, names.records).use { it.metricVersion(spec.metric) } }
            main.post {
                if (active && token == generation && audit != null && current.getOrNull() != expected) {
                    failure(current.exceptionOrNull() ?: HealthTrendChangedException())
                }
            }
        }
    }
    private fun failure(cause: Throwable) {
        audit = null
        sourceName = ""
        scroll = null
        body.removeAllViews()
        body.addView(ui.text(getString(when (cause) {
            is HealthTrendChangedException -> R.string.health_trend_changed
            is HealthAccessBlocked -> R.string.health_privacy_trend_blocked
            else -> R.string.health_storage_error
        }), 14f, muted = true).apply { tag = "health-trend-records-status" })
        if (cause is HealthAccessBlocked) body.addView(ui.command(R.string.health_privacy_title) { startActivity(healthPrivacyIntent()) }.apply { tag = "health-privacy-blocked" })
        body.addView(ui.command(if (numeric || fixedVersion) R.string.health_trend_return else R.string.health_trend_refresh) {
            if (numeric || fixedVersion) finish() else { version = null; cursor = null; previous.clear(); scrollY = 0; load() }
        }.apply { tag = "health-trend-records-recover" })
    }
    private fun openRevision(id: String, revision: Int) {
        startActivity(Intent(this, HealthRecordRevisionActivity::class.java).putExtra("health_record", id)
            .putExtra("health_revision", revision).putHealthNavigationFixture(names))
    }
    private fun previewBluetoothDeletion(name: String) {
        if (!active || deletionBusy || deletionDialog?.isShowing == true) return
        val request = generation
        val previewRequest = ++deletionPreviewGeneration
        deletionBusy = true
        worker.execute {
            val result = runCatching {
                HealthPrivacyStore.track(applicationContext, HealthAccessScope.trend(HealthAccessPurpose.TREND_SOURCES, spec),
                    privacyDatabase) {
                    HealthRecordStore(applicationContext, names.records).use { it.bluetoothHistoryPreview(spec.source.bluetoothGroup) }
                }
            }
            main.post {
                deletionBusy = false
                if (!active || request != generation || previewRequest != deletionPreviewGeneration || !hasWindowFocus()) return@post
                result.fold({ preview ->
                    if (preview.count == 0L) { refreshBluetoothHistory(); return@fold }
                    val first = Instant.ofEpochMilli(preview.first).atZone(spec.zone).toLocalDate()
                    val last = Instant.ofEpochMilli(preview.last).atZone(spec.zone).toLocalDate()
                    deletionDialog = AlertDialog.Builder(this)
                        .setTitle(R.string.health_sources_delete_history)
                        .setMessage(getString(R.string.health_sources_delete_preview, name, preview.count, first, last))
                        .setNegativeButton(R.string.common_cancel, null)
                        .setPositiveButton(R.string.common_delete) { _, _ -> eraseBluetoothHistory(preview) }
                        .show()
                }, { failure ->
                    if (failure is HealthAccessBlocked) this.failure(failure)
                    else Toast.makeText(this, R.string.health_storage_error, Toast.LENGTH_LONG).show()
                })
            }
        }
    }
    private fun eraseBluetoothHistory(preview: HealthBluetoothHistoryPreview) {
        if (!active || deletionBusy) return
        deletionBusy = true
        val access = HealthAccessScope(HealthAccessPurpose.DELETE_BLUETOOTH_HISTORY, setOf(HealthMetric.BLOOD_PRESSURE),
            preview.first, preview.last + 1, spec.zone.id, count = preview.count, source = HealthAccessSource.BLUETOOTH)
        worker.execute {
            val result = runCatching {
                HealthPrivacyStore.track(applicationContext, access, privacyDatabase) {
                    HealthRecordStore(applicationContext, names.records).use { it.eraseBluetoothHistory(preview) }
                }
            }
            main.post {
                deletionBusy = false
                if (!active) return@post
                result.fold({
                    Toast.makeText(this, R.string.health_sources_history_deleted, Toast.LENGTH_SHORT).show()
                    finish()
                }, { failure ->
                    val message = if (failure is HealthBluetoothHistoryChanged) R.string.health_sources_history_changed else R.string.health_storage_error
                    Toast.makeText(this, message, Toast.LENGTH_LONG).show()
                    refreshBluetoothHistory()
                })
            }
        }
    }
    private fun refreshBluetoothHistory() {
        version = null; cursor = null; previous.clear(); scrollY = 0
        load()
    }
    private fun pointHeader(content: LinearLayout, point: HealthTrendPoint) {
        val unit = spec.unit.ifBlank { getString(R.string.health_unit_not_applicable) }
        ui.add(content, ui.text(getString(R.string.health_trend_point_result,
            getString(healthFieldResource(point.field)), getString(spec.aggregation.titleResource()),
            point.value.toPlainString(), unit), 18f, bold = true).apply { tag = "health-trend-audit-result" }, 8)
        ui.add(content, ui.text(getString(R.string.health_trend_point_contributors, point.count), 13f, muted = true).apply {
            tag = "health-trend-audit-count"
        }, 6)
        val source = when {
            spec.source.manualOnly -> getString(R.string.health_source_manual)
            spec.source.bluetoothGroup.isNotEmpty() -> healthBluetoothTrendLabel(spec.source.bluetoothGroup, sourceName)
            spec.source.platformOrigin.isNotEmpty() -> healthConnectTrendLabel(spec.source.platformOrigin, spec.metric)
            spec.source.originalId.isBlank() -> getString(R.string.health_trend_all_sources)
            else -> sourceName.ifBlank { getString(R.string.health_trend_original_source, spec.source.originalId.take(8)) }
        }
        ui.add(content, ui.text(source, 13f, muted = true).apply { tag = "health-trend-audit-source" }, 4)
        if (point.recordId.isNotBlank()) ui.add(content, ui.row(getString(R.string.health_trend_open_extremum)) {
            openRevision(point.recordId, point.recordRevision)
        }.apply { tag = "health-trend-audit-extremum" }, 6)
    }
    private fun render(page: HealthRecordPage) {
        body.removeAllViews()
        val content = ui.column().apply { setPadding(ui.dp(16), ui.dp(16), ui.dp(16), ui.dp(24)) }
        content.addView(ui.text("${spec.first} \u2014 ${spec.last} \u00b7 ${spec.zone.id}", 13f, muted = true))
        val point = audit
        if (point != null) pointHeader(content, point)
        else if (numeric) ui.add(content, ui.text(getString(R.string.health_trend_numeric_records, spec.unit), 13f, muted = true), 8)
        if (manageBluetooth && page.records.isNotEmpty()) {
            val name = healthBluetoothTrendLabel(spec.source.bluetoothGroup, page.records.first().platformOrigin)
            ui.add(content, ui.profileRow(getString(R.string.health_sources_delete_history), name) {
                previewBluetoothDeletion(name)
            }.apply { tag = "health-bluetooth-delete-history" }, 8)
        }
        if (page.records.isEmpty()) ui.add(content, ui.text(getString(R.string.health_no_records)), 20)
        page.records.forEach { record ->
            val time = Instant.ofEpochMilli(record.draft.measuredAt).atZone(spec.zone).format(DateTimeFormatter.ofPattern("uuuu-MM-dd HH:mm"))
            val source = when (record.source) {
                "bluetooth" -> healthBluetoothTrendLabel(record.bluetoothGroup, record.platformOrigin)
                "health_connect" -> healthConnectTrendLabel(record.platformOrigin, record.draft.metric)
                else -> getString(healthRecordSourceResource(record.source))
            }
            ui.add(content, ui.row(healthDisplayValue(record.draft), "$time \u00b7 $source") {
                if (numeric || fixedVersion) openRevision(record.id, record.revision)
                else startActivity(Intent(this, HealthCenterActivity::class.java).putExtra("health_record", record.id).putHealthNavigationFixture(names))
            }.apply { tag = "health-trend-record-${record.id}" }, 8)
        }
        val current = ScrollView(this).apply { addView(content); tag = "health-trend-records-scroll" }
        scroll = current
        body.addView(current, LinearLayout.LayoutParams(-1, 0, 1f))
        OneShotPreDrawListener.add(current) { if (active && scroll === current) current.scrollTo(0, scrollY) }
        val footer = ui.line().apply { setPadding(ui.dp(16), ui.dp(8), ui.dp(16), ui.dp(12)) }
        if (previous.isNotEmpty()) footer.addView(ui.command(R.string.health_previous_page) {
            cursor = previous.removeAt(previous.lastIndex); scrollY = 0; load()
        }.apply { tag = "health-trend-records-previous" }, LinearLayout.LayoutParams(0, -2, 1f))
        page.next?.let { next -> footer.addView(ui.command(R.string.health_next_page) {
            previous += cursor; cursor = next; scrollY = 0; load()
        }.apply { tag = "health-trend-records-next" }, LinearLayout.LayoutParams(0, -2, 1f)) }
        if (footer.childCount > 0) body.addView(footer, LinearLayout.LayoutParams(-1, -2))
    }
}

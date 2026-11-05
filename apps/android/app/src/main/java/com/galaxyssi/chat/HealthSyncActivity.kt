package com.galaxyssi.chat

import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.widget.LinearLayout
import android.widget.ScrollView
import java.text.DateFormat
import java.time.ZoneId
import java.util.Date
import java.util.UUID
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull

class HealthSyncActivity : Activity() {
    private data class VisibleCheckpoint(
        val scope: HealthConnectScope,
        val outcome: HealthSyncOutcome = HealthSyncOutcome.NOT_STARTED,
        val lastSuccess: Long = 0,
        val latestMeasurement: Long = 0,
        val lastAttempt: Long = 0,
        val lastInserts: Int = 0,
        val pendingInserts: Int = 0,
        val retainedSourceDeletion: Boolean = false,
        val historyGap: Boolean = false,
    ) {
        constructor(mark: HealthSyncCheckpoint) : this(mark.scope, mark.outcome, mark.lastSuccess, mark.latestMeasurement,
            mark.lastAttempt, mark.lastInserts, mark.pendingInserts, mark.lastDeletes > 0 || mark.pendingDeletes > 0, mark.historyGap)
    }

    private data class Screen(
        val availability: HealthPlatformAvailability,
        val selected: Set<HealthConnectScope>,
        val granted: Set<String>?,
        val marks: List<VisibleCheckpoint>,
        val bluetoothReceipt: Long,
    )

    private val ui by lazy { HealthCenterViews(this) }
    private val tasks = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private lateinit var body: LinearLayout
    private lateinit var scroll: ScrollView
    private lateinit var names: HealthOverviewDatabases
    private var screen: Screen? = null
    private var job: Job? = null
    private var active = false
    private var running = false
    private var loading = false
    private var generation = 0
    private var dialog: AlertDialog? = null
    private var notice: Int? = null
    private var focusScope: HealthConnectScope? = null
    private var focusScrollPending = true

    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        val fixture = if (BuildConfig.DEBUG) intent.getStringExtra("health_sync_test_id")
            ?.takeIf { runCatching { UUID.fromString(it).toString() == it }.getOrDefault(false) } else null
        names = HealthOverviewDatabases(fixture)
        focusScope = (state?.getString("sync_scope") ?: if (state == null) intent.getStringExtra("health_sync_scope") else null)
            ?.let { id -> HealthConnectScope.entries.firstOrNull { it.name == id } }
        window.statusBarColor = getColor(R.color.page_bg)
        window.navigationBarColor = getColor(R.color.page_bg)
        if (Build.VERSION.SDK_INT >= 33) setRecentsScreenshotEnabled(false)
        body = ui.column().apply { setPadding(ui.dp(16), ui.dp(12), ui.dp(16), ui.dp(24)) }
        setContentView(ui.column().apply {
            setBackgroundColor(getColor(R.color.page_bg))
            addView(ui.line().apply {
                addView(ui.icon(R.drawable.ic_navigation_back, R.string.health_back) { finish() })
                addView(ui.text(getString(R.string.health_sync_title), 19f, bold = true).apply { gravity = Gravity.CENTER },
                    LinearLayout.LayoutParams(0, -2, 1f))
                addView(View(this@HealthSyncActivity), LinearLayout.LayoutParams(ui.dp(48), 1))
            }, LinearLayout.LayoutParams(-1, ui.dp(56)))
            scroll = ScrollView(this@HealthSyncActivity).apply { addView(body) }
            addView(scroll, LinearLayout.LayoutParams(-1, 0, 1f))
        })
    }

    override fun onResume() { super.onResume(); active = true; refresh() }
    override fun onPause() {
        active = false; generation++
        dialog?.dismiss(); dialog = null
        job?.cancel(); job = null
        running = false; loading = false; screen = null; notice = null
        body.removeAllViews()
        super.onPause()
    }
    override fun onDestroy() { tasks.cancel(); super.onDestroy() }
    override fun onSaveInstanceState(outState: Bundle) {
        outState.putString("sync_scope", focusScope?.name)
        super.onSaveInstanceState(outState)
    }

    private fun refresh() {
        if (!active || running || loading) return
        val request = ++generation
        loading = true; show()
        job = tasks.launch {
            try {
                val loaded = withContext(Dispatchers.IO) {
                    val platform = HealthSourcesRepository.platform(this@HealthSyncActivity)
                    val selected = if (names.fixture == null) HealthConnectSettings.selection(this@HealthSyncActivity) else emptySet()
                    val granted = if (platform == HealthPlatformAvailability.AVAILABLE) {
                        try { withTimeoutOrNull(4_000) { AndroidHealthConnectReader(this@HealthSyncActivity).granted() } }
                        catch (cancelled: CancellationException) { throw cancelled }
                        catch (_: Exception) { null }
                    } else null
                    val marks = if (getDatabasePath(names.records).exists()) HealthRecordStore(this@HealthSyncActivity, names.records).use { store ->
                        HealthConnectScope.entries.map { VisibleCheckpoint(store.healthSyncCheckpoint(it)) } to store.lastBluetoothReceipt()
                    } else emptyList<VisibleCheckpoint>() to 0L
                    Screen(platform, selected, granted, marks.first, marks.second)
                }
                if (request == generation) screen = loaded
            } catch (cancelled: CancellationException) { throw cancelled }
            catch (_: Exception) { if (request == generation) notice = R.string.health_sync_storage }
            finally { if (request == generation) { loading = false; if (active) show() } }
        }
    }

    private fun confirm() {
        val selected = screen?.selected?.toSet().orEmpty()
        if (selected.isEmpty() || running || names.fixture != null) return
        val names = selected.joinToString(", ") { getString(it.metric.titleResource()) }
        dialog = AlertDialog.Builder(this).setTitle(R.string.health_sync_confirm)
            .setMessage(getString(R.string.health_sync_confirm_detail, names))
            .setNegativeButton(android.R.string.cancel, null)
            .setPositiveButton(R.string.health_sync_retry) { _, _ -> synchronize(selected) }
            .show()
    }

    private fun synchronize(selected: Set<HealthConnectScope>) {
        if (running || loading || !active) return
        val request = ++generation
        running = true; notice = null; show()
        job = tasks.launch {
            try {
                val completed = withContext(Dispatchers.IO) {
                    val platform = HealthSourcesRepository.platform(this@HealthSyncActivity)
                    val reader = if (platform == HealthPlatformAvailability.AVAILABLE) AndroidHealthConnectReader(this@HealthSyncActivity) else null
                    HealthRecordStore(this@HealthSyncActivity, names.records).use { store ->
                        HealthSyncEngine.run(store, selected, platform, reader, System::currentTimeMillis, ZoneId.systemDefault()) { checkpoint ->
                            val visible = VisibleCheckpoint(checkpoint)
                            runOnUiThread {
                                if (request == generation && active) {
                                    screen = screen?.let { current ->
                                        current.copy(marks = (current.marks.filterNot { it.scope == visible.scope } + visible).sortedBy { it.scope.ordinal })
                                    }
                                    show()
                                }
                            }
                        }
                    }
                }
                if (!completed && request == generation) notice = R.string.health_sync_busy
            } catch (cancelled: CancellationException) { throw cancelled }
            catch (_: android.database.sqlite.SQLiteException) { if (request == generation) notice = R.string.health_sync_storage }
            catch (_: Exception) { if (request == generation) notice = R.string.health_sync_failed }
            finally {
                if (request == generation) {
                    running = false
                    if (active) refresh()
                }
            }
        }
    }

    private fun pause() {
        generation++
        job?.cancel(); job = null
        running = false
        notice = R.string.health_sync_paused
        refresh()
    }

    private fun show() {
        body.removeAllViews()
        notice?.let { ui.add(body, ui.text(getString(it), 15f, bold = true), 2) }
        val current = screen
        if (current == null) {
            if (loading) ui.add(body, ui.text(getString(R.string.health_sources_checking), 14f, muted = true), 6)
            else ui.add(body, ui.command(R.string.health_connect_check_again, ::recheck), 10)
            return
        }
        ui.add(body, ui.card().apply {
            addView(ui.text(getString(R.string.health_sources_platform_name), 20f, bold = true))
            val status = when (current.availability) {
                HealthPlatformAvailability.AVAILABLE -> when {
                    running -> R.string.health_sync_running
                    current.selected.isEmpty() -> R.string.health_sync_select
                    current.granted == null -> R.string.health_connect_grant_status_unavailable
                    HealthConnectImport.allowed(current.selected, current.granted).isEmpty() -> R.string.health_sync_permission
                    else -> R.string.health_sync_foreground
                }
                HealthPlatformAvailability.INSTALL_OR_UPDATE -> R.string.health_sources_platform_install
                HealthPlatformAvailability.UNSUPPORTED -> R.string.health_sources_platform_unsupported
                HealthPlatformAvailability.CHECK_FAILED -> R.string.health_sync_transport
            }
            ui.add(this, ui.text(getString(status), 14f, muted = true).apply { tag = "health-sync-platform-status" }, 6)
            val successful = current.marks.maxOfOrNull { it.lastSuccess } ?: 0L
            ui.add(this, ui.text(if (successful > 0) getString(R.string.health_sync_success_time, date(successful))
                else getString(R.string.health_sync_no_success), 13f, muted = true), 6)
        }, 4)
        ui.add(body, ui.text(getString(R.string.health_sync_coverage), 18f, bold = true), 18)
        val marks = current.marks.associateBy { it.scope }
        val displayed = HealthConnectScope.entries.filter { scope ->
            scope == focusScope || scope in current.selected || marks[scope]?.let { it.lastAttempt > 0 || it.lastSuccess > 0 } == true
        }
        if (displayed.isEmpty()) ui.add(body, ui.text(getString(R.string.health_sync_no_coverage), 14f, muted = true), 8)
        displayed.forEach { scope ->
            val mark = marks[scope] ?: VisibleCheckpoint(scope)
            ui.add(body, ui.card().apply {
                tag = "health-sync-scope-${scope.name}"
                addView(ui.text(getString(scope.metric.titleResource()), 16f, bold = true))
                val outcome = if (scope in current.selected && current.granted != null && scope.permission !in current.granted)
                    HealthSyncOutcome.PERMISSION else mark.outcome
                val result = if (outcome == HealthSyncOutcome.UPDATED) getString(R.string.health_sync_updated, mark.lastInserts)
                    else getString(outcome.statusResource(running))
                ui.add(this, ui.text(result, 14f), 4)
                if (mark.lastSuccess > 0) ui.add(this, ui.text(getString(R.string.health_sync_success_time, date(mark.lastSuccess)),
                    13f, muted = true).apply { tag = "health-sync-scope-success" }, 4)
                if (mark.latestMeasurement > 0) ui.add(this, ui.text(getString(R.string.health_sync_latest, date(mark.latestMeasurement)), 13f, muted = true), 4)
                if (mark.lastAttempt > 0) ui.add(this, ui.text(getString(R.string.health_sync_attempt, date(mark.lastAttempt)), 13f, muted = true), 4)
                if (mark.pendingInserts > 0) ui.add(this, ui.text(getString(R.string.health_sync_pending, mark.pendingInserts), 13f), 4)
                if (mark.retainedSourceDeletion) ui.add(this, ui.text(getString(R.string.health_sync_source_deleted), 13f), 4)
                if (mark.historyGap) ui.add(this, ui.text(getString(R.string.health_sync_gap), 13f), 4)
            }, 8)
        }
        focusScope?.takeIf { focusScrollPending }?.let { scope ->
            val card = body.findViewWithTag<View>("health-sync-scope-${scope.name}")
            if (card != null) {
                focusScrollPending = false
                scroll.post { if (active && card.isAttachedToWindow) scroll.scrollTo(0, body.top + card.top) }
            }
        }
        ui.add(body, ui.text(getString(R.string.health_sources_bluetooth), 18f, bold = true), 18)
        ui.add(body, ui.card().apply {
            addView(ui.text(getString(R.string.health_sync_ble_disconnected), 15f, bold = true))
            ui.add(this, ui.text(if (current.bluetoothReceipt > 0) getString(R.string.health_sync_ble_receipt, date(current.bluetoothReceipt))
                else getString(R.string.health_sync_ble_no_receipt), 13f, muted = true), 4)
            if (!running) addView(ui.profileRow(getString(R.string.health_ble_title)) { open(HealthBluetoothActivity::class.java) })
        }, 8)
        if (running) ui.add(body, ui.command(R.string.health_sync_pause, ::pause), 14)
        else {
            if (current.availability == HealthPlatformAvailability.AVAILABLE && current.selected.isNotEmpty())
                ui.add(body, ui.command(R.string.health_sync_retry, ::confirm).apply { isEnabled = !loading }, 14)
            ui.add(body, ui.row(getString(R.string.health_connect_authorize)) { open(HealthConnectActivity::class.java) })
            if (current.availability != HealthPlatformAvailability.AVAILABLE) {
                ui.add(body, ui.row(getString(R.string.health_connect_check_again), action = ::recheck))
            }
        }
    }

    private fun open(type: Class<*>) { if (names.fixture == null) startActivity(Intent(this, type)) }
    private fun recheck() { notice = null; refresh() }
    private fun date(value: Long) = DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT).format(Date(value))
}

internal fun HealthSyncOutcome.statusResource(running: Boolean = false) = when (this) {
    HealthSyncOutcome.NOT_STARTED -> R.string.health_sync_not_started
    HealthSyncOutcome.RUNNING -> if (running) R.string.health_sync_running else R.string.health_sync_interrupted
    HealthSyncOutcome.UPDATED -> R.string.health_sync_updated
    HealthSyncOutcome.NO_NEW -> R.string.health_sync_no_new
    HealthSyncOutcome.PERMISSION -> R.string.health_sync_permission
    HealthSyncOutcome.UNAVAILABLE -> R.string.health_sync_unavailable
    HealthSyncOutcome.NETWORK -> R.string.health_sync_network
    HealthSyncOutcome.TRANSPORT -> R.string.health_sync_transport
    HealthSyncOutcome.TIMEOUT -> R.string.health_sync_timeout
    HealthSyncOutcome.STORAGE -> R.string.health_sync_storage
    HealthSyncOutcome.FAILED -> R.string.health_sync_failed
}

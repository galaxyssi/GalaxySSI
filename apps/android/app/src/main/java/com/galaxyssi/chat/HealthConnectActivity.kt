package com.galaxyssi.chat

import android.app.Activity
import android.app.AlertDialog
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.os.Build
import android.view.Gravity
import android.view.View
import android.widget.CheckBox
import android.widget.LinearLayout
import android.widget.ScrollView
import androidx.activity.ComponentActivity
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.PermissionController
import java.text.DateFormat
import java.time.Instant
import java.time.ZoneId
import java.util.Date
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout

internal object HealthConnectSettings {
    private fun prefs(context: Context) = context.getSharedPreferences("health-connect-local", Context.MODE_PRIVATE)
    fun selection(context: Context) = prefs(context).getStringSet("scopes", emptySet()).orEmpty()
        .mapNotNull { raw -> HealthConnectScope.entries.firstOrNull { it.name == raw } }.toSet()
    fun setSelection(context: Context, selected: Set<HealthConnectScope>) {
        val removed = selection(context).any { it !in selected }
        prefs(context).edit().putStringSet("scopes", selected.mapTo(hashSetOf()) { it.name }).apply()
        if (removed) HealthReminderWork.sourceRemindersChanged(context)
    }
    fun lastImport(context: Context) = prefs(context).getLong("last_confirmed_import", 0L)
    fun markImport(context: Context, time: Long) { prefs(context).edit().putLong("last_confirmed_import", time).apply() }
}

private fun Activity.connectPage(ui: HealthCenterViews, title: Int): LinearLayout {
    window.statusBarColor = getColor(R.color.page_bg)
    window.navigationBarColor = getColor(R.color.page_bg)
    if (Build.VERSION.SDK_INT >= 33) setRecentsScreenshotEnabled(false)
    val body = ui.column().apply { setPadding(ui.dp(16), ui.dp(12), ui.dp(16), ui.dp(24)) }
    setContentView(ui.column().apply {
        setBackgroundColor(getColor(R.color.page_bg))
        addView(ui.line().apply {
            addView(ui.icon(R.drawable.ic_navigation_back, R.string.health_back) { finish() })
            addView(ui.text(getString(title), 19f, bold = true).apply { gravity = Gravity.CENTER }, LinearLayout.LayoutParams(0, -2, 1f))
            addView(View(this@connectPage), LinearLayout.LayoutParams(ui.dp(48), 1))
        }, LinearLayout.LayoutParams(-1, ui.dp(56)))
        addView(ScrollView(this@connectPage).apply { addView(body) }, LinearLayout.LayoutParams(-1, 0, 1f))
    })
    return body
}

class HealthConnectRationaleActivity : Activity() {
    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        val ui = HealthCenterViews(this)
        val body = connectPage(ui, R.string.health_connect_privacy)
        body.addView(ui.text(getString(R.string.health_connect_read_only), 18f, bold = true))
        listOf(R.string.health_connect_policy, R.string.health_connect_retention, R.string.health_connect_revocation).forEach {
            ui.add(body, ui.text(getString(it), 15f), 12)
        }
    }
}

class HealthConnectActivity : ComponentActivity() {
    private val ui by lazy { HealthCenterViews(this) }
    private val tasks = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var task: Job? = null
    private var active = false
    private var busy = false
    private var generation = 0
    private lateinit var body: LinearLayout
    private var platform = HealthPlatformAvailability.CHECK_FAILED
    private var granted: Set<String>? = null
    private var selected = emptySet<HealthConnectScope>()
    private var hours = 24
    private var preview: HealthConnectPreview? = null
    private var notice = ""
    private var dialog: AlertDialog? = null
    private val request = registerForActivityResult(PermissionController.createRequestPermissionResultContract()) {
        if (active) refresh()
    }

    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        body = connectPage(ui, R.string.health_connect_authorize)
        selected = state?.getStringArray("health_scopes")?.let { names ->
            HealthConnectScope.entries.filterTo(linkedSetOf()) { it.name in names }
        } ?: HealthConnectSettings.selection(this)
        hours = state?.getInt("health_hours", 24)?.takeIf { it in rangeOptions() } ?: 24
    }

    override fun onResume() { super.onResume(); active = true; refresh() }
    override fun onPause() {
        active = false
        generation++
        dialog?.dismiss(); dialog = null
        task?.cancel(); task = null
        busy = false
        preview = null
        granted = null
        body.removeAllViews()
        super.onPause()
    }
    override fun onDestroy() { tasks.cancel(); super.onDestroy() }
    override fun onSaveInstanceState(outState: Bundle) {
        outState.putStringArray("health_scopes", selected.map { it.name }.toTypedArray())
        outState.putInt("health_hours", hours)
        super.onSaveInstanceState(outState)
    }

    private fun refresh() {
        if (busy) return
        perform(15_000, {
            val current = HealthSourcesRepository.platform(this)
            current to if (current == HealthPlatformAvailability.AVAILABLE) AndroidHealthConnectReader(this).granted() else null
        }) { (current, permissions) ->
            platform = current
            granted = permissions
        }
    }

    private fun show() {
        body.removeAllViews()
        if (busy) {
            body.addView(ui.text(getString(R.string.health_connect_working), 15f, muted = true))
            return
        }
        if (notice.isNotBlank()) ui.add(body, ui.text(notice, 14f).apply { tag = "health-connect-notice" }, 4)
        ui.add(body, ui.text(getString(R.string.health_sources_platform_name), 21f, bold = true), 8)
        ui.add(body, ui.text(getString(R.string.health_connect_intro), 14f, muted = true), 6)
        ui.add(body, ui.profileRow(getString(R.string.health_connect_history_title)) {
            startActivity(Intent(this, HealthMeasurementHistoryActivity::class.java))
        }, 8)
        if (platform != HealthPlatformAvailability.AVAILABLE || granted == null) {
            val status = when (platform) {
                HealthPlatformAvailability.INSTALL_OR_UPDATE -> R.string.health_sources_platform_install
                HealthPlatformAvailability.UNSUPPORTED -> R.string.health_sources_platform_unsupported
                else -> R.string.health_sources_platform_error
            }
            ui.add(body, ui.text(getString(status), 16f, bold = true).apply { tag = "health-connect-unavailable" }, 14)
            ui.add(body, ui.row(getString(R.string.health_manual)) {
                startActivity(Intent(this, HealthCenterActivity::class.java).putExtra("health_manual", true))
            })
            if (platform != HealthPlatformAvailability.UNSUPPORTED)
                ui.add(body, ui.row(getString(R.string.health_connect_check_again)) { notice = ""; refresh() })
            return
        }
        val permissions = granted.orEmpty()
        ui.add(body, ui.card().apply {
            addView(ui.text(getString(R.string.health_connect_scopes), 17f, bold = true))
            HealthConnectScope.entries.forEach { scope ->
                ui.add(this, CheckBox(this@HealthConnectActivity).apply {
                    minimumHeight = ui.dp(48)
                    val name = getString(scope.metric.titleResource())
                    text = if (scope.permission in permissions) getString(R.string.health_connect_scope_granted, name) else name
                    isChecked = scope in selected
                    tag = "health-connect-scope-${scope.name}"
                    setOnCheckedChangeListener { _, checked ->
                        selected = if (checked) selected + scope else selected - scope
                        HealthConnectSettings.setSelection(this@HealthConnectActivity, selected)
                        if (hours !in rangeOptions()) hours = 24
                        preview = null; notice = ""
                        body.findViewWithTag<View>("health-connect-notice")?.let(body::removeView)
                        renderActions(permissions)
                    }
                })
            }
        }, 14)
        ui.add(body, ui.text(getString(R.string.health_connect_read_only), 14f, bold = true), 12)
        ui.add(body, ui.text(getString(R.string.health_connect_policy), 13f, muted = true), 4)
        ui.add(body, ui.column().apply { tag = "health-connect-actions" }, 10)
        renderActions(permissions)
    }

    private fun renderActions(permissions: Set<String>) {
        val actions = body.findViewWithTag<LinearLayout>("health-connect-actions") ?: return
        actions.removeAllViews()
        val allowed = HealthConnectImport.allowed(selected, permissions)
        val missing = (selected - allowed).mapTo(linkedSetOf()) { it.permission }
        if (selected.isEmpty()) actions.addView(ui.text(getString(R.string.health_connect_select_first), 14f, muted = true))
        if (missing.isNotEmpty()) ui.add(actions, ui.command(R.string.health_connect_continue) {
            HealthConnectSettings.setSelection(this, selected)
            try { request.launch(missing) } catch (_: ActivityNotFoundException) { failed(R.string.health_connect_failed) }
            catch (_: SecurityException) { failed(R.string.health_connect_failed) }
        })
        if (allowed.isNotEmpty()) {
            ui.add(actions, ui.row(getString(R.string.health_connect_range), rangeLabel(hours)) {
                val options = rangeOptions()
                dialog = AlertDialog.Builder(this).setTitle(R.string.health_connect_range)
                    .setSingleChoiceItems(options.map(::rangeLabel).toTypedArray(), options.indexOf(hours)) { prompt, index ->
                        hours = options[index]; preview = null; notice = ""; prompt.dismiss(); show()
                    }.setNegativeButton(android.R.string.cancel, null).show()
            })
            ui.add(actions, ui.text(getString(R.string.health_connect_interval_note), 13f, muted = true), 4)
            ui.add(actions, ui.command(R.string.health_connect_preview) {
                val scopes = selected.toSet()
                val window = HealthConnectWindow(hours, Instant.now(), ZoneId.systemDefault())
                HealthConnectSettings.setSelection(this, scopes)
                preview = null
                perform(60_000, { HealthConnectImport.preview(AndroidHealthConnectReader(this), scopes, window) }) {
                    preview = it
                    if (it.rows.isEmpty()) notice = getString(R.string.health_connect_no_records)
                }
            }, 10)
        }
        preview?.let { staged ->
            if (staged.allowed != staged.selected) ui.add(actions, ui.text(getString(R.string.health_connect_partial), 14f), 8)
            if (staged.rows.isNotEmpty()) {
                ui.add(actions, ui.card().apply {
                    addView(ui.text(getString(R.string.health_connect_preview_count, staged.rows.size), 16f, bold = true))
                    staged.rows.groupBy { it.draft.metric }.forEach { (metric, rows) ->
                        val recent = rows.maxBy { it.draft.measuredAt }
                        ui.add(this, ui.text(getString(R.string.health_connect_preview_metric,
                            getString(metric.titleResource()), rows.size, healthDisplayValue(recent.draft),
                            DateFormat.getDateTimeInstance().format(Date(recent.draft.measuredAt))), 13f), 6)
                    }
                    ui.add(this, ui.text(getString(R.string.health_connect_self_confirmation), 13f, muted = true), 10)
                }, 10)
                ui.add(actions, ui.command(R.string.health_connect_save) { save(staged) }, 8)
            }
        }
        if (HealthConnectScope.entries.any { it.permission in permissions }) {
            ui.add(actions, ui.row(getString(R.string.health_connect_disconnect), getString(R.string.health_connect_retention)) {
                dialog = AlertDialog.Builder(this).setTitle(R.string.health_connect_disconnect)
                    .setMessage(R.string.health_connect_retention)
                    .setNegativeButton(android.R.string.cancel, null)
                    .setPositiveButton(R.string.health_connect_disconnect) { _, _ ->
                        selected = emptySet()
                        HealthConnectSettings.setSelection(this, selected)
                        preview = null
                        perform(15_000, {
                            val reader = AndroidHealthConnectReader(this)
                            reader.revoke()
                            reader.granted()
                        }) { granted = it }
                    }.show()
            }, 10)
        }
        ui.add(actions, ui.row(getString(R.string.health_sources_system_settings)) {
            try { startActivity(Intent(HealthConnectClient.ACTION_HEALTH_CONNECT_SETTINGS)) }
            catch (_: ActivityNotFoundException) { failed(R.string.health_sources_external_unavailable) }
            catch (_: SecurityException) { failed(R.string.health_sources_external_unavailable) }
        })
    }

    private fun save(staged: HealthConnectPreview) {
        preview = null
        perform(45_000, {
            HealthRecordStore(this).use { HealthConnectImport.save(AndroidHealthConnectReader(this), it, staged) }
                .also { HealthConnectSettings.markImport(this, System.currentTimeMillis()) }
        }) { saved ->
            notice = getString(R.string.health_connect_saved, saved, staged.rows.size - saved)
        }
    }

    private fun rangeOptions() = HealthConnectWindow.RANGES.filter { it >= 24 || HealthConnectScope.STEPS !in selected }
    private fun rangeLabel(hours: Int) = if (hours < 24) getString(R.string.health_connect_hours, hours)
        else getString(R.string.health_connect_days, hours / 24)

    private fun failed(message: Int) { notice = getString(message); show() }

    private fun <T> perform(timeout: Long, work: suspend () -> T, done: (T) -> Unit) {
        if (!active || busy) return
        val request = ++generation
        busy = true; notice = ""; show()
        task = tasks.launch {
            try {
                val result = withTimeout(timeout) { withContext(Dispatchers.IO) { work() } }
                if (request == generation) done(result)
            } catch (_: TimeoutCancellationException) {
                if (request == generation) notice = getString(R.string.health_connect_timeout)
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (_: SecurityException) {
                if (request == generation) {
                    preview = null
                    granted = null
                    notice = getString(R.string.health_connect_permissions_changed)
                }
            } catch (_: HealthConnectTooManyRecords) {
                if (request == generation) notice = getString(R.string.health_connect_too_many)
            } catch (_: Exception) {
                if (request == generation) notice = getString(R.string.health_connect_failed)
            } finally {
                if (request == generation) {
                    busy = false
                    if (active) show()
                }
            }
        }
    }
}

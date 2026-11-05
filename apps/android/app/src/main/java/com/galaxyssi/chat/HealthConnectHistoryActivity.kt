package com.galaxyssi.chat

import android.app.Activity
import android.app.AlertDialog
import android.os.Bundle
import android.os.CancellationSignal
import android.widget.LinearLayout
import java.time.Instant
import java.time.ZoneId
import java.util.concurrent.Executors

internal data class HealthConnectHistoryPreview(
    val scope: HealthConnectScope,
    val version: String,
    val count: Long,
    val first: Long,
    val last: Long,
)

internal class HealthConnectHistoryChanged : IllegalStateException("Health Connect history changed after preview")

/** Manages app-owned copies without consulting the Health Connect provider or its grants. */
class HealthConnectHistoryActivity : Activity() {
    private val ui by lazy { HealthCenterViews(this) }
    private val names by lazy { intent.healthNavigationDatabases() }
    private val worker = Executors.newSingleThreadExecutor()
    private lateinit var body: LinearLayout
    private var active = false
    private var deleting = false
    private var dialog: AlertDialog? = null
    private var signal: CancellationSignal? = null
    private var notice: Int? = null

    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        body = healthProfileBody(R.string.health_connect_history_title) { finish() }
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
        notice?.let { ui.add(content, ui.text(getString(it), 14f).apply { tag = "health-connect-history-notice" }, 4) }
        for (scope in HealthConnectScope.entries) {
            ui.add(content, ui.profileRow(getString(scope.metric.titleResource())) { preview(scope) }
                .apply { tag = "health-connect-history-${scope.name}" }, 6)
        }
    }

    private fun preview(scope: HealthConnectScope) {
        if (!active || deleting || signal != null || dialog?.isShowing == true) return
        val request = CancellationSignal().also { signal = it }
        notice = null; show()
        worker.execute {
            val app = applicationContext
            val result = runCatching {
                if (!app.getDatabasePath(names.records).isFile) null
                else HealthRecordStore(app, names.records).use { it.healthConnectHistoryPreview(scope, request::throwIfCanceled) }
            }
            runOnUiThread {
                if (!active || signal !== request) return@runOnUiThread
                signal = null
                result.fold({ current ->
                    if (current == null || current.count == 0L) notice = R.string.health_connect_history_empty
                    else if (hasWindowFocus()) confirm(current)
                }, { notice = failureResource(it) })
                show()
            }
        }
    }

    private fun confirm(preview: HealthConnectHistoryPreview) {
        val zone = ZoneId.systemDefault()
        fun date(time: Long) = Instant.ofEpochMilli(time).atZone(zone).toLocalDate()
        dialog = AlertDialog.Builder(this).setTitle(R.string.health_connect_history_delete)
            .setMessage(getString(R.string.health_connect_history_preview, getString(preview.scope.metric.titleResource()),
                preview.count, date(preview.first), date(preview.last)))
            .setNegativeButton(R.string.common_cancel, null)
            .setPositiveButton(R.string.common_delete) { _, _ -> erase(preview, zone) }
            .show()
    }

    private fun erase(preview: HealthConnectHistoryPreview, zone: ZoneId) {
        if (!active || deleting) return
        deleting = true; notice = null; show()
        val access = HealthAccessScope(HealthAccessPurpose.DELETE_HEALTH_CONNECT_HISTORY, setOf(preview.scope.metric),
            preview.first, preview.last + 1, zone.id, count = preview.count, source = HealthAccessSource.HEALTH_CONNECT)
        worker.execute {
            val app = applicationContext
            val result = runCatching {
                HealthPrivacyStore.track(app, access, names.privacy) {
                    HealthRecordStore(app, names.records).use { it.eraseHealthConnectHistory(preview) }
                }
            }
            runOnUiThread {
                deleting = false
                notice = result.fold({ R.string.health_connect_history_deleted }, ::failureResource)
                if (active) show()
            }
        }
    }

    private fun failureResource(failure: Throwable) =
        if (failure is HealthConnectHistoryChanged) R.string.health_connect_history_changed else R.string.health_storage_error
}

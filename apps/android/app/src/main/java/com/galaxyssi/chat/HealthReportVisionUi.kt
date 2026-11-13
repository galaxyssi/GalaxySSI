package com.galaxyssi.chat

import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.widget.Toast
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

internal data class HealthReportImportScreen(val id: String, val name: String, val stage: HealthReportImportStage,
    val bytes: Int = 0, val failure: Int? = null, val legacy: Boolean = false)

internal class HealthReportVisionUi(private val activity: Activity, private val names: HealthOverviewDatabases,
    private val progress: (HealthReportImportScreen) -> Unit, private val completed: (String) -> Unit) {
    private val tasks = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var reader = HealthReportVisionReader(activity.applicationContext, names)
    private var dialog: AlertDialog? = null
    private var task: Job? = null
    private var generation = 0

    fun clear() { generation++; task?.cancel(); task = null; dialog?.dismiss(); dialog = null }
    fun destroy() { clear(); tasks.cancel() }
    internal fun useFixtureGateway(value: HealthReportVisionGateway) {
        check(BuildConfig.DEBUG && names.fixture != null)
        clear(); reader = HealthReportVisionReader(activity.applicationContext, names, value)
    }
    fun show(id: String) {
        clear()
        run({ reader.prepare(id) to reader.target() }) { (input, target) ->
            if (target == null) { message(R.string.health_vision_no_model); return@run }
            confirm(input, target)
        }
    }
    fun finishImport(id: String, name: String) {
        clear()
        val screen = HealthReportImportScreen(id, name, HealthReportImportStage.SAVING, legacy = true)
        progress(screen)
        run({ reader.finishLegacy(id) }, { progress(screen.copy(failure = it)) }) { completed(id) }
    }
    private fun confirm(input: HealthReportVisionInput, target: HealthReportVisionTarget) {
        dialog = AlertDialog.Builder(activity).setTitle(R.string.health_vision_consent)
            .setMessage(activity.getString(R.string.health_vision_disclosure, target.destination))
            .setNegativeButton(android.R.string.cancel, null).setPositiveButton(R.string.health_vision_action) { _, _ ->
                dialog = null
                val screen = HealthReportImportScreen(input.job.id, input.source.name, HealthReportImportStage.COMPRESSING)
                val token = generation
                var last = screen
                progress(screen)
                run({ reader.read(input, target) { stage, bytes ->
                    val update = screen.copy(stage = stage, bytes = bytes)
                    activity.runOnUiThread { if (token == generation) { last = update; progress(update) } }
                } }, { progress(last.copy(failure = it)) }) { completed(input.job.id) }
            }.show()
    }
    private fun <T> run(work: suspend () -> T, failed: ((Int) -> Unit)? = null, success: (T) -> Unit) {
        val token = generation
        task = tasks.launch {
            try {
                val value = withContext(Dispatchers.IO) { work() }
                if (token == generation && !activity.isFinishing && !activity.isDestroyed) success(value)
            } catch (failure: Exception) {
                if (failure is CancellationException) throw failure
                if (token != generation || activity.isFinishing || activity.isDestroyed) return@launch
                dialog?.dismiss(); dialog = null
                if (failed == null && (failure is HealthAccessBlocked || failure is HealthPrivacyConflict)) {
                    privacy()
                } else {
                    val text = when (failure) {
                        is HealthAccessBlocked, is HealthPrivacyConflict -> R.string.health_vision_blocked
                        is HealthReportVisionChanged -> R.string.health_vision_changed
                        is HealthAnalysisInvalidReply -> R.string.health_vision_unreadable
                        is HealthReportCodexUnavailable -> R.string.health_vision_request_failed
                        is HealthImportFailure -> R.string.health_vision_image_failed
                        else -> R.string.health_report_storage_failed
                    }
                    (failed ?: ::message)(text)
                }
            } catch (_: OutOfMemoryError) {
                if (token == generation) { dialog?.dismiss(); dialog = null; (failed ?: ::message)(R.string.health_vision_image_failed) }
            }
        }
    }
    private fun privacy() {
        dialog = AlertDialog.Builder(activity).setTitle(R.string.health_vision_action).setMessage(R.string.health_vision_blocked)
            .setNegativeButton(android.R.string.cancel, null)
            .setPositiveButton(R.string.health_privacy_title) { _, _ ->
                activity.startActivity(Intent(activity, HealthPrivacyActivity::class.java).putHealthNavigationFixture(names))
            }.show()
    }
    private fun message(id: Int) { Toast.makeText(activity, id, Toast.LENGTH_LONG).show() }
}

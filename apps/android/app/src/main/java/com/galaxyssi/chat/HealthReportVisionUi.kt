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

internal class HealthReportVisionUi(private val activity: Activity, private val names: HealthOverviewDatabases,
    private val completed: (String) -> Unit) {
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
        run({ reader.prepare(id) to reader.targets() }) { (input, targets) ->
            if (targets.isEmpty()) { message(R.string.health_vision_no_model); return@run }
            dialog = AlertDialog.Builder(activity).setTitle(R.string.health_vision_model)
                .setItems(targets.map { "${it.label}\n${it.destination}" }.toTypedArray()) { _, index -> confirm(input, targets[index]) }
                .setNegativeButton(android.R.string.cancel, null).show()
        }
    }
    private fun confirm(input: HealthReportVisionInput, target: HealthAnalysisTarget) {
        dialog = AlertDialog.Builder(activity).setTitle(R.string.health_vision_consent)
            .setMessage(activity.getString(R.string.health_vision_disclosure, target.destination))
            .setNegativeButton(android.R.string.cancel, null).setPositiveButton(R.string.health_assistant_send) { _, _ ->
                dialog = AlertDialog.Builder(activity).setTitle(R.string.health_vision_action).setMessage(R.string.health_vision_reading)
                    .setNegativeButton(android.R.string.cancel) { _, _ -> clear() }.setOnCancelListener { clear() }.show()
                run({ reader.read(input, target) }) {
                    dialog?.dismiss(); dialog = null; completed(input.job.id)
                }
            }.show()
    }
    private fun <T> run(work: suspend () -> T, success: (T) -> Unit) {
        val token = generation
        task = tasks.launch {
            try {
                val value = withContext(Dispatchers.IO) { work() }
                if (token == generation && !activity.isFinishing && !activity.isDestroyed) success(value)
            } catch (failure: Exception) {
                if (failure is CancellationException) throw failure
                if (token != generation || activity.isFinishing || activity.isDestroyed) return@launch
                dialog?.dismiss(); dialog = null
                when (failure) {
                    is HealthAccessBlocked, is HealthPrivacyConflict -> privacy()
                    is HealthReportVisionChanged -> message(R.string.health_vision_changed)
                    is HealthAnalysisInvalidReply -> message(R.string.health_vision_unreadable)
                    is HealthImportFailure -> message(R.string.health_vision_image_failed)
                    else -> message(R.string.health_vision_request_failed)
                }
            } catch (_: OutOfMemoryError) {
                if (token == generation) { dialog?.dismiss(); dialog = null; message(R.string.health_vision_image_failed) }
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

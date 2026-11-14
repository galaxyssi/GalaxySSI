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
internal data class HealthReportPickerApproval(val policy: HealthPrivacyPolicy, val target: HealthReportVisionTarget)

internal class HealthReportVisionUi(private val activity: Activity, private val names: HealthOverviewDatabases,
    private val progress: (HealthReportImportScreen) -> Unit, private val completed: (String) -> Unit) {
    private val tasks = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var reader = HealthReportVisionReader(activity.applicationContext, names)
    private var dialog: AlertDialog? = null
    private var task: Job? = null
    private var generation = 0
    private val supplementUi = HealthReportSupplementUi(activity)

    fun clear() { generation++; task?.cancel(); task = null; dialog?.dismiss(); dialog = null; supplementUi.clear() }
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
    fun chooseFile(cancel: () -> Unit, pick: (HealthReportPickerApproval?) -> Unit) {
        clear()
        run({
            val policy = HealthPrivacyStore(activity.applicationContext, names.privacy).use { it.policy() }
            if (!policy.online || !policy.metrics) null else reader.target()?.let { HealthReportPickerApproval(policy, it) }
        }, { cancel() }) { approval ->
            if (approval == null) { pick(null); return@run }
            dialog = AlertDialog.Builder(activity).setTitle(R.string.health_choose_files)
                .setMessage(activity.getString(R.string.health_report_picker_disclosure, approval.target.destination))
                .setNegativeButton(R.string.health_report_picker_local) { _, _ -> dialog = null; pick(null) }
                .setPositiveButton(R.string.health_report_picker_select) { _, _ -> dialog = null; pick(approval) }
                .setOnCancelListener { dialog = null; cancel() }.show()
        }
    }
    fun importSelected(job: HealthImportJob, approval: HealthReportPickerApproval, holdForBatch: Boolean = false) {
        clear()
        val screen = HealthReportImportScreen(job.id, job.name, HealthReportImportStage.COMPRESSING)
        progress(screen)
        run({
            val input = reader.prepare(job.id)
            if (input.privacy != approval.policy) throw HealthAccessBlocked()
            input
        }, { progress(screen.copy(failure = it)) }) { input -> start(input, approval.target, holdForBatch) }
    }
    fun completeReports(ids: List<String>, scope: HealthReportSupplementScope, finished: (Boolean) -> Unit) {
        fun save(supplement: HealthReportSupplement) {
            run({ reader.complete(ids, supplement) }, {
                message(it); finished(false)
            }) { finished(true) }
        }
        if (scope.needed) supplementUi.show(scope, ids.size, ::save) { finished(false) } else save(HealthReportSupplement())
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
                start(input, target)
            }.show()
    }
    private fun start(input: HealthReportVisionInput, target: HealthReportVisionTarget, holdForBatch: Boolean = false) {
        val screen = HealthReportImportScreen(input.job.id, input.source.name, HealthReportImportStage.COMPRESSING)
        val token = generation
        var last = screen
        progress(screen)
        run({ reader.read(input, target, holdForBatch) { stage, bytes ->
            val update = screen.copy(stage = stage, bytes = bytes)
            activity.runOnUiThread { if (token == generation) { last = update; progress(update) } }
        } }, { progress(last.copy(failure = it)) }) { completed(input.job.id) }
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
                        is HealthReportTimeInvalid -> R.string.health_report_invalid_time
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

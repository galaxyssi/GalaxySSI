package com.galaxyssi.chat

import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.os.CancellationSignal
import android.os.OperationCanceledException
import android.text.InputType
import android.view.View
import android.view.WindowManager
import android.widget.CheckBox
import android.widget.LinearLayout
import java.text.DateFormat
import java.util.Date
import java.util.concurrent.Executors
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class HealthRestoreActivity : Activity() {
    private val ui by lazy { HealthCenterViews(this) }
    private val worker = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private lateinit var body: LinearLayout
    private lateinit var repository: HealthRestoreRepository
    private var started = false
    private var busy: CancellationSignal? = null
    private var dialog: AlertDialog? = null
    private var plan: HealthRestorePlan? = null
    private var conflictPage: HealthRestoreConflictPage? = null
    private var completed: HealthRestoreReceipt? = null
    private var history = emptyList<HealthRestoreReceipt>()
    private var notice: Int? = null

    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        val fixture = if (BuildConfig.DEBUG) intent.getStringExtra("health_restore_test_id")?.takeIf(HealthProfilePolicy::uuid) else null
        val names = HealthOverviewDatabases(fixture)
        repository = if (fixture == null) HealthRestoreRepository(applicationContext, names)
            else HealthRestoreRepository(applicationContext, names) { "" }
        body = healthProfileBody(R.string.health_restore_title) { back() }
    }

    override fun onStart() {
        super.onStart()
        started = true
        render()
        refreshHistory()
    }

    override fun onStop() {
        started = false
        busy?.cancel()
        dialog?.dismiss()
        dialog = null
        clearPlan()
        body.removeAllViews()
        super.onStop()
    }

    override fun onDestroy() { worker.cancel(); super.onDestroy() }

    @Deprecated("Native back callback")
    override fun onBackPressed() = back()

    private fun back() {
        when {
            busy != null -> busy?.cancel()
            conflictPage != null -> { conflictPage = null; render() }
            plan != null -> { clearPlan(); render() }
            else -> finish()
        }
    }

    private fun clearPlan() {
        val previous = plan
        plan = null
        conflictPage = null
        if (previous != null) disposal.execute { runCatching { previous.close() } }
    }

    private fun refreshHistory() {
        worker.launch {
            val rows = withContext(Dispatchers.IO) { runCatching { repository.recent() }.getOrDefault(emptyList()) }
            if (started) {
                history = rows
                if (busy == null && plan == null) render()
            }
        }
    }

    private fun render() {
        val content = healthProfileContent(body)
        notice?.let { ui.add(content, ui.text(getString(it), 14f).apply { tag = "health-restore-error" }, 8) }
        busy?.let { current ->
            ui.add(content, ui.text(getString(R.string.health_backup_working)), 8)
            ui.add(content, ui.profileRow(getString(android.R.string.cancel)) { current.cancel() }, 8)
            return
        }
        conflictPage?.let { page ->
            ui.add(content, ui.text(getString(R.string.health_restore_conflicts), 18f, bold = true), 8)
            page.rows.forEach { row ->
                val incoming = row.record
                val title = getString(incoming.draft.metric.titleResource())
                val time = DateFormat.getDateTimeInstance().format(Date(incoming.draft.measuredAt))
                ui.add(content, ui.text("$title · $time", 15f, bold = true), 13)
                ui.add(content, ui.text(getString(R.string.health_restore_incoming, healthDisplayValue(incoming.draft))), 4)
                val current = row.existing
                ui.add(content, ui.text(when {
                    row.deleted -> getString(R.string.health_restore_deleted)
                    current != null -> getString(R.string.health_restore_local_value, healthDisplayValue(current.draft))
                    else -> getString(R.string.health_restore_keep_existing)
                }, 14f, muted = true), 4)
                if (current != null && current.draft.note != incoming.draft.note) {
                    val empty = getString(R.string.health_restore_no_note)
                    ui.add(content, ui.text(getString(R.string.health_restore_incoming_note, incoming.draft.note.ifBlank { empty }),
                        13f, muted = true), 4)
                    ui.add(content, ui.text(getString(R.string.health_restore_local_note, current.draft.note.ifBlank { empty }),
                        13f, muted = true), 4)
                }
            }
            page.next?.let { after -> ui.add(content, ui.profileRow(getString(R.string.health_next_page)) { openConflicts(after) }, 8) }
            ui.add(content, ui.profileRow(getString(R.string.health_restore_back_preview)) { conflictPage = null; render() }, 10)
            return
        }
        plan?.let { value ->
            ui.add(content, ui.text(getString(R.string.health_restore_verified), 19f, bold = true).apply { tag = "health-restore-preview" }, 8)
            ui.add(content, ui.text(getString(R.string.health_restore_owner_pair,
                value.manifest.owner.ifBlank { getString(R.string.health_backup_self) },
                value.owner.ifBlank { getString(R.string.health_backup_self) }), 15f), 8)
            ui.add(content, ui.text(getString(R.string.health_backup_counts, value.manifest.records, value.manifest.originals,
                value.manifest.linked, value.manifest.missing), 14f), 6)
            if (value.manifest.records > 0) {
                val dates = DateFormat.getDateInstance()
                ui.add(content, ui.text(getString(R.string.health_backup_dates, dates.format(Date(value.manifest.first)),
                    dates.format(Date(value.manifest.last))), 14f, muted = true), 4)
            }
            showCounts(content, value.counts)
            if (value.counts.conflicts > 0L) ui.add(content, ui.profileRow(getString(R.string.health_restore_conflicts),
                getString(R.string.health_restore_keep_existing)) { openConflicts("") }, 7)
            val confirmation = CheckBox(this).apply {
                setText(if (value.counts.missing == 0) R.string.health_restore_confirm else R.string.health_restore_confirm_missing)
                isSaveEnabled = false
                tag = "health-restore-consent"
            }
            ui.add(content, confirmation, 14)
            val commit = ui.command(R.string.health_restore_commit) {
                if (confirmation.isChecked && plan === value) restore(value)
            }.apply { isEnabled = false; tag = "health-restore-commit" }
            confirmation.setOnCheckedChangeListener { _, checked -> commit.isEnabled = checked }
            ui.add(content, commit, 8)
            return
        }
        completed?.let { receipt ->
            ui.add(content, ui.text(getString(if (receipt.counts.missing != 0 || receipt.counts.conflicts > 0)
                R.string.health_restore_partial else R.string.health_restore_complete), 19f, bold = true).apply { tag = "health-restore-receipt" }, 8)
            showCounts(content, receipt.counts)
        }
        ui.add(content, ui.text(getString(R.string.health_restore_intro), 14f, muted = true), 8)
        ui.add(content, ui.command(R.string.health_backup_select) { pick() }.apply { tag = "health-restore-select" }, 12)
        if (history.isNotEmpty()) {
            ui.add(content, ui.text(getString(R.string.health_restore_history), 17f, bold = true), 20)
            val date = DateFormat.getDateTimeInstance()
            history.forEach { row ->
                ui.add(content, ui.text(date.format(Date(row.createdAt)), 15f, bold = true), 8)
                if (row.first > 0) ui.add(content, ui.text(getString(R.string.health_backup_dates,
                    date.format(Date(row.first)), date.format(Date(row.last))), 13f, muted = true), 4)
                showCounts(content, row.counts)
            }
        }
    }

    private fun showCounts(content: LinearLayout, counts: HealthRestoreCounts) {
        ui.add(content, ui.text(getString(R.string.health_restore_record_counts, counts.added, counts.duplicates, counts.conflicts), 15f), 7)
        ui.add(content, ui.text(getString(R.string.health_restore_file_counts, counts.originalsAdded, counts.originalsReused,
            counts.repaired, counts.missing), 14f, muted = true), 4)
    }

    private fun pick() {
        try {
            startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE).setType("*/*"), OPEN)
        } catch (_: android.content.ActivityNotFoundException) { notice = R.string.health_backup_io_error; render() }
    }

    @Deprecated("Storage Access Framework result")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != OPEN || resultCode != RESULT_OK) return
        val uri = data?.data?.takeIf { it.scheme == "content" } ?: return
        unlock(uri)
    }

    private fun unlock(uri: Uri) {
        val input = healthProfileInput("", 256).apply {
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PASSWORD
            importantForAutofill = View.IMPORTANT_FOR_AUTOFILL_NO
            setHint(R.string.health_backup_password)
        }
        val layout = ui.column().apply { setPadding(ui.dp(20), ui.dp(10), ui.dp(20), ui.dp(8)); addView(input) }
        val prompt = AlertDialog.Builder(this).setTitle(R.string.health_backup_unlock).setView(layout)
            .setNegativeButton(android.R.string.cancel, null).setPositiveButton(android.R.string.ok, null).create()
        prompt.window?.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        prompt.setOnDismissListener { input.text.clear() }
        prompt.setOnShowListener {
            prompt.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener {
                val password = CharArray(input.text.length) { input.text[it] }
                if (!HealthBackupCodec.passwordAllowed(password)) {
                    password.fill('\u0000')
                    input.error = getString(R.string.health_backup_password_rules)
                } else {
                    prompt.dismiss()
                    completed = null
                    run({ signal ->
                        repository.prepare({ requireNotNull(contentResolver.openInputStream(uri)) }, password, signal)
                    }, release = { it.close() }, cleanup = { password.fill('\u0000') }) { plan = it }
                }
            }
        }
        dialog = prompt
        prompt.show()
    }

    private fun openConflicts(after: String) {
        val source = plan ?: return
        run({ source.conflicts(after) }) { if (plan === source) conflictPage = it }
    }

    private fun restore(source: HealthRestorePlan) {
        run({ source.commit(it) }) { result ->
            completed = result
            clearPlan()
            refreshHistory()
        }
    }

    private fun <T : Any> run(operation: (CancellationSignal) -> T, release: (T) -> Unit = {},
        cleanup: () -> Unit = {}, deliver: (T) -> Unit) {
        if (busy != null) { cleanup(); return }
        val signal = CancellationSignal()
        busy = signal
        notice = null
        render()
        worker.launch {
            var result: T? = null
            try {
                withContext(Dispatchers.IO) { result = operation(signal) }
                if (started) {
                    deliver(requireNotNull(result))
                    result = null
                }
            } catch (failure: Exception) {
                if (failure is CancellationException) throw failure
                notice = error(failure)
                if (failure is HealthRestoreChanged) clearPlan()
            } finally {
                withContext(NonCancellable + Dispatchers.IO) {
                    try { runCatching { result?.let(release) } } finally { cleanup() }
                }
                busy = null
                if (started) render()
            }
        }
    }

    private fun error(failure: Exception) = when (failure) {
        is OperationCanceledException -> R.string.health_backup_cancelled
        is HealthRestoreChanged -> R.string.health_restore_changed
        is HealthRestoreOwnerMismatch -> R.string.health_restore_owner_mismatch
        is HealthRestoreOriginalUnavailable -> R.string.health_restore_original_unavailable
        is HealthBackupException -> when (failure.issue) {
            HealthBackupIssue.FORMAT -> R.string.health_backup_bad_format
            HealthBackupIssue.OLDER_VERSION -> R.string.health_backup_old
            HealthBackupIssue.NEWER_VERSION -> R.string.health_backup_new
            HealthBackupIssue.UNLOCK -> R.string.health_backup_wrong_password
            HealthBackupIssue.OTHER_PROFILE -> R.string.health_backup_other_profile
            HealthBackupIssue.MISSING_MANIFEST -> R.string.health_backup_bad_link
            HealthBackupIssue.SOURCE_CHANGED -> R.string.health_restore_changed
            HealthBackupIssue.DAMAGED -> R.string.health_backup_damaged
        }
        else -> R.string.health_restore_failed
    }

    companion object {
        private const val OPEN = 73
        private val disposal = Executors.newSingleThreadExecutor { task -> Thread(task, "health-restore-disposal").apply { isDaemon = true } }
    }
}

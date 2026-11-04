package com.galaxyssi.chat

import android.app.Activity
import android.app.AlertDialog
import android.content.ClipData
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.os.CancellationSignal
import android.os.OperationCanceledException
import android.provider.DocumentsContract
import android.text.InputType
import android.text.format.Formatter
import android.view.View
import android.view.WindowManager
import android.widget.CheckBox
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.Toast
import androidx.core.content.FileProvider
import java.io.OutputStream
import java.text.DateFormat
import java.util.Date
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class HealthBackupActivity : Activity() {
    private val ui by lazy { HealthCenterViews(this) }
    private val worker = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private lateinit var body: LinearLayout
    private lateinit var names: HealthOverviewDatabases
    private val repository by lazy { HealthBackupRepository(applicationContext, names) }
    private val verifyOnly by lazy { intent.getBooleanExtra("verify_backup", false) }
    private var preview: HealthBackupPreview? = null
    private var verification: HealthBackupManifest? = null
    private var artifact: HealthBackupArtifact? = null
    private var saved = false
    private var notice: Int? = null
    private var busy: CancellationSignal? = null
    private var dialog: AlertDialog? = null
    private var started = false

    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        names = HealthOverviewDatabases(if (BuildConfig.DEBUG) intent.getStringExtra("health_backup_test_id")
            ?.takeIf(HealthProfilePolicy::uuid) else null)
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        body = healthProfileBody(if (verifyOnly) R.string.health_backup_verify else R.string.health_backup_create) { finish() }
        artifact = state?.getString("artifact")?.let { id ->
            HealthBackupArtifact(id, state.getLong("size"), state.getString("hash").orEmpty(), state.getInt("missing"))
        }
        saved = state?.getBoolean("saved") ?: false
        worker.launch { withContext(Dispatchers.IO) { repository.cleanup() } }
    }

    override fun onStart() { super.onStart(); started = true; render() }

    override fun onStop() {
        started = false
        busy?.cancel()
        dialog?.dismiss()
        dialog = null
        preview = null
        verification = null
        body.removeAllViews()
        super.onStop()
    }

    override fun onDestroy() { worker.cancel(); super.onDestroy() }

    override fun onSaveInstanceState(state: Bundle) {
        artifact?.let {
            state.putString("artifact", it.id); state.putLong("size", it.size)
            state.putString("hash", it.hash); state.putInt("missing", it.missing)
            state.putBoolean("saved", saved)
        }
        super.onSaveInstanceState(state)
    }

    private fun render() {
        val content = healthProfileContent(body)
        notice?.let { ui.add(content, ui.text(getString(it), 14f, muted = true).apply { tag = "health-backup-status" }, 8) }
        busy?.let { signal ->
            ui.add(content, ui.text(getString(R.string.health_backup_working)), 10)
            ui.add(content, ui.profileRow(getString(android.R.string.cancel)) { signal.cancel() }, 8)
            return
        }
        if (verifyOnly) {
            verification?.let {
                manifest(content, it)
                ui.add(content, ui.text(getString(if (it.missing == 0) R.string.health_backup_verified else R.string.health_backup_missing),
                    14f, bold = true).apply { tag = "health-backup-verified" }, 10)
            }
            ui.add(content, ui.text(getString(R.string.health_backup_verify_intro), 14f, muted = true), 8)
            ui.add(content, ui.command(R.string.health_backup_select) {
                launchPicker(Intent(Intent.ACTION_OPEN_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE).setType("*/*"), OPEN)
            }.apply { tag = "health-backup-select" }, 14)
            return
        }
        artifact?.let { result ->
            val title = when {
                result.missing != 0 -> R.string.health_backup_incomplete
                saved -> R.string.health_backup_saved
                else -> R.string.health_backup_generated
            }
            content.addView(ui.text(getString(title), 18f, bold = true).apply { tag = "health-backup-generated" })
            ui.add(content, ui.text(Formatter.formatFileSize(this, result.size), 14f, muted = true), 6)
            ui.add(content, ui.command(R.string.health_backup_save) {
                launchPicker(Intent(Intent.ACTION_CREATE_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE).setType(MIME)
                    .putExtra(Intent.EXTRA_TITLE, "GalaxySSI-Health-${result.id.take(8)}.${HealthBackupCodec.EXTENSION}"), SAVE)
            }.apply { tag = "health-backup-save" }, 14)
            ui.add(content, ui.profileRow(getString(R.string.health_backup_share)) { share(result) }, 8)
            ui.add(content, ui.profileRow(getString(R.string.health_backup_discard)) {
                work({ repository.forget(result) }) { artifact = null; saved = false }
            }, 8)
            return
        }
        preview?.let { value ->
            manifest(content, value.manifest)
            ui.add(content, ui.text(getString(R.string.health_backup_estimate, Formatter.formatFileSize(this, value.estimate)), 14f), 7)
            ui.add(content, ui.text(getString(R.string.health_backup_photos, value.photos, value.manifest.originals - value.photos), 14f), 7)
            if (value.manifest.missing != 0) ui.add(content, ui.text(getString(R.string.health_backup_missing), 14f, bold = true), 8)
            value.examples.forEach { original ->
                ui.add(content, ui.text(if (original.present) original.name
                    else getString(R.string.health_backup_missing_name, original.name), 13f, muted = true), 4)
            }
            if (value.manifest.originals > value.examples.size)
                ui.add(content, ui.text(getString(R.string.health_backup_more, value.manifest.originals - value.examples.size), 13f, muted = true), 4)
            val acknowledge = CheckBox(this).apply { setText(R.string.health_backup_acknowledge); isSaveEnabled = false }
            ui.add(content, acknowledge, 12)
            val create = ui.command(R.string.health_backup_encrypt) {
                passwordDialog(confirm = true) { password ->
                    val manifest = value.manifest
                    work({ signal ->
                        val scope = HealthAccessScope(HealthAccessPurpose.GENERATE_BACKUP,
                            from = manifest.first, until = if (manifest.records > 0L) manifest.last + 1 else Long.MAX_VALUE,
                            count = manifest.records, format = HealthAccessFormat.GHBACKUP, annotations = true)
                        HealthPrivacyStore.track(applicationContext, scope, names.privacy) { repository.generate(value, password, signal) }
                    }, cleanup = { password.fill('\u0000') }) { artifact = it; preview = null }
                }
            }.apply { isEnabled = false; tag = "health-backup-encrypt" }
            acknowledge.setOnCheckedChangeListener { _, checked -> create.isEnabled = checked }
            ui.add(content, create, 8)
            return
        }
        ui.add(content, ui.text(getString(R.string.health_backup_export_intro), 14f, muted = true), 8)
        ui.add(content, ui.command(R.string.health_backup_preview) {
            work({ signal ->
                val owner = if (names.fixture == null) HealthProfileStore(applicationContext).use {
                    it.snapshot().cells[HealthProfileField.NAME]?.value?.text.orEmpty()
                }.filterNot(Char::isISOControl).take(120) else ""
                repository.preview(owner, signal)
            }) { preview = it }
        }.apply { tag = "health-backup-preview" }, 14)
    }

    private fun manifest(content: LinearLayout, data: HealthBackupManifest) {
        ui.add(content, ui.text(getString(R.string.health_backup_manifest), 18f, bold = true).apply { tag = "health-backup-manifest" }, 10)
        ui.add(content, ui.text(getString(R.string.health_backup_owner,
            data.owner.ifBlank { getString(R.string.health_backup_self) }), 15f), 8)
        ui.add(content, ui.text(getString(R.string.health_backup_counts, data.records, data.originals, data.linked, data.missing), 15f), 6)
        if (data.records > 0) {
            val date = DateFormat.getDateInstance()
            ui.add(content, ui.text(getString(R.string.health_backup_dates, date.format(Date(data.first)), date.format(Date(data.last))), 14f), 6)
        }
    }

    private fun passwordDialog(confirm: Boolean, accept: (CharArray) -> Unit) {
        fun field(label: Int) = healthProfileInput("", 256).apply {
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PASSWORD
            importantForAutofill = View.IMPORTANT_FOR_AUTOFILL_NO
            setHint(label)
        }
        fun chars(edit: EditText) = CharArray(edit.text.length) { edit.text[it] }
        val first = field(R.string.health_backup_password)
        val again = if (confirm) field(R.string.health_backup_repeat) else null
        val fields = ui.column().apply {
            setPadding(ui.dp(22), ui.dp(12), ui.dp(22), ui.dp(8))
            addView(first)
            again?.let { addView(it) }
        }
        val prompt = AlertDialog.Builder(this).setTitle(if (confirm) R.string.health_backup_encrypt else R.string.health_backup_unlock)
            .setView(fields).setNegativeButton(android.R.string.cancel, null).setPositiveButton(android.R.string.ok, null).create()
        prompt.window?.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        prompt.setOnDismissListener { first.text.clear(); again?.text?.clear() }
        prompt.setOnShowListener {
            prompt.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener {
                val password = chars(first)
                val repeated = again?.let(::chars)
                val allowed = HealthBackupCodec.passwordAllowed(password)
                val matches = repeated?.contentEquals(password) ?: true
                repeated?.fill('\u0000')
                if (!allowed || !matches) {
                    password.fill('\u0000')
                    (if (allowed) again else first)?.error = getString(if (allowed) R.string.health_backup_mismatch else R.string.health_backup_password_rules)
                } else {
                    prompt.dismiss()
                    accept(password)
                }
            }
        }
        dialog = prompt
        prompt.show()
    }

    private fun <T> work(operation: (CancellationSignal) -> T, cleanup: () -> Unit = {}, success: (T) -> Unit) {
        if (busy != null) { cleanup(); return }
        val signal = CancellationSignal()
        busy = signal
        notice = null
        render()
        worker.launch {
            try {
                val result = withContext(Dispatchers.IO) { operation(signal) }
                signal.throwIfCanceled()
                success(result)
            } catch (failure: Exception) {
                if (failure is CancellationException) throw failure
                notice = when (failure) {
                    is OperationCanceledException -> R.string.health_backup_cancelled
                    is HealthBackupException -> when (failure.issue) {
                        HealthBackupIssue.FORMAT -> R.string.health_backup_bad_format
                        HealthBackupIssue.OLDER_VERSION -> R.string.health_backup_old
                        HealthBackupIssue.NEWER_VERSION -> R.string.health_backup_new
                        HealthBackupIssue.UNLOCK -> R.string.health_backup_wrong_password
                        HealthBackupIssue.DAMAGED -> R.string.health_backup_damaged
                        HealthBackupIssue.OTHER_PROFILE -> R.string.health_backup_other_profile
                        HealthBackupIssue.SOURCE_CHANGED -> R.string.health_backup_changed.also { preview = null }
                        HealthBackupIssue.MISSING_MANIFEST -> R.string.health_backup_bad_link
                    }
                    else -> R.string.health_backup_io_error
                }
            } finally {
                cleanup()
                busy = null
                if (started) render()
            }
        }
    }

    private fun launchPicker(action: Intent, code: Int) {
        try { startActivityForResult(action, code) }
        catch (_: android.content.ActivityNotFoundException) { toast() }
    }

    @Deprecated("Storage Access Framework result")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        val uri = data?.data?.takeIf { it.scheme == "content" } ?: return
        if (resultCode != RESULT_OK) return
        if (requestCode == OPEN) {
            verification = null
            passwordDialog(confirm = false) { password ->
                work({ signal ->
                    val input = contentResolver.openInputStream(uri) ?: error("Backup unavailable")
                    input.use { HealthBackupCodec.verify(it, password, signal::throwIfCanceled) }
                }, cleanup = { password.fill('\u0000') }) { verification = it }
            }
        } else if (requestCode == SAVE) artifact?.let { value ->
            work({ signal -> saveVerified(value, uri, signal) }) {
                saved = true
                notice = if (value.missing == 0) null else R.string.health_backup_saved_partial
            }
        }
    }

    private fun saveVerified(value: HealthBackupArtifact, uri: Uri, signal: CancellationSignal) {
        var opened = false
        try {
            val destination = contentResolver.openOutputStream(uri, "wt") ?: error("Backup destination unavailable")
            opened = true
            destination.use { repository.save(value, it, signal) }
            val savedBytes = contentResolver.openInputStream(uri) ?: error("Backup read-back unavailable")
            val sink = object : OutputStream() {
                override fun write(value: Int) = Unit
                override fun write(bytes: ByteArray, offset: Int, length: Int) = Unit
            }
            HealthPrivateExportFile.copyVerified(savedBytes, sink, HealthExportDigest(value.size, value.hash), signal::throwIfCanceled)
        } catch (failure: Exception) {
            if (opened) runCatching { DocumentsContract.deleteDocument(contentResolver, uri) }
            throw failure
        }
    }

    private fun share(result: HealthBackupArtifact) {
        try {
            val uri = FileProvider.getUriForFile(this, "${packageName}.files", repository.file(result),
                "GalaxySSI-Health.${HealthBackupCodec.EXTENSION}")
            val action = Intent(Intent.ACTION_SEND).setType(MIME).putExtra(Intent.EXTRA_STREAM, uri).apply {
                clipData = ClipData.newUri(contentResolver, "GalaxySSI health backup", uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            startActivity(Intent.createChooser(action, null))
        } catch (_: Exception) { toast() }
    }

    private fun toast() { Toast.makeText(this, R.string.health_backup_io_error, Toast.LENGTH_LONG).show() }

    companion object {
        private const val MIME = "application/octet-stream"
        private const val OPEN = 71
        private const val SAVE = 72
    }
}

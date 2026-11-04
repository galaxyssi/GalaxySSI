package com.galaxyssi.chat

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.widget.CheckBox
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.Toast
import java.util.concurrent.Executors

/** Generation is private/encrypted. A separate explicit SAF operation writes an unencrypted standard ZIP. */
class HealthOriginalExportActivity : Activity() {
    private val ui by lazy { HealthCenterViews(this) }; private val worker = Executors.newSingleThreadExecutor(); private val main = Handler(Looper.getMainLooper())
    private val fixture by lazy { intent.getStringExtra("health_original_export_test_id").orEmpty().takeIf { BuildConfig.DEBUG && HealthProfilePolicy.uuid(it) } }
    private lateinit var body: LinearLayout; private var id = ""; private var active = false; private var generation = 0
    private var querying = false; private var dirty = false; private var saving = false; private var cursor = ""; private val previous = arrayListOf<String>()
    private var shareDialog: android.app.AlertDialog? = null
    private var pendingPickerAttempt = ""
    private var observedWork = ""; private var workUpdates: androidx.lifecycle.LiveData<List<androidx.work.WorkInfo>>? = null
    private val workObserver = androidx.lifecycle.Observer<List<androidx.work.WorkInfo>> { load() }
    private val observer = object : android.database.ContentObserver(main) {
        override fun onChange(selfChange: Boolean, uri: android.net.Uri?) { if (uri?.lastPathSegment == "exports") load() }
    }
    override fun onCreate(state: Bundle?) {
        super.onCreate(state); id = intent.getStringExtra("export_id").orEmpty()
        if (runCatching { java.util.UUID.fromString(id).toString() == id }.getOrDefault(false).not()) { finish(); return }
        cursor = state?.getString("cursor").orEmpty(); previous.addAll(state?.getStringArrayList("previous").orEmpty())
        pendingPickerAttempt = state?.getString("pending_picker_attempt").orEmpty()
        window.statusBarColor = getColor(R.color.page_bg); window.navigationBarColor = getColor(R.color.page_bg)
        if (android.os.Build.VERSION.SDK_INT >= 33) setRecentsScreenshotEnabled(false)
        val root = ui.column().apply { setBackgroundColor(getColor(R.color.page_bg)) }
        root.addView(ui.line().apply {
            addView(ui.icon(R.drawable.ic_navigation_back, R.string.health_back) { finish() })
            addView(ui.text(getString(R.string.health_library_export), 19f, bold = true).apply { gravity = Gravity.CENTER }, LinearLayout.LayoutParams(0, -2, 1f))
            addView(ui.icon(R.drawable.ic_health_grid, R.string.health_functions) { startActivity(Intent(this@HealthOriginalExportActivity, HealthCenterActivity::class.java).putExtra("health_functions", true)) })
        }, LinearLayout.LayoutParams(-1, ui.dp(56)))
        body = ui.column(); root.addView(body, LinearLayout.LayoutParams(-1, 0, 1f)); setContentView(root)
    }
    override fun onStart() { super.onStart(); if (!::body.isInitialized) return; active = true; contentResolver.registerContentObserver(HealthOriginalStore.changesUri(this), true, observer); load() }
    override fun onStop() {
        active = false; generation++; workUpdates?.removeObserver(workObserver); workUpdates = null; observedWork = ""
        shareDialog?.dismiss(); shareDialog = null
        if (::body.isInitialized) body.removeAllViews()
        contentResolver.unregisterContentObserver(observer); super.onStop()
    }
    override fun onDestroy() { worker.shutdown(); super.onDestroy() }
    override fun onSaveInstanceState(out: Bundle) {
        out.putString("cursor", cursor)
        out.putStringArrayList("previous", ArrayList(previous))
        out.putString("pending_picker_attempt", pendingPickerAttempt)
        super.onSaveInstanceState(out)
    }
    private fun <T> withLibrary(read: (HealthOriginalLibraryStore) -> T): T =
        HealthExportShare.openOriginals(applicationContext, fixture).use { read(HealthExportShare.originalLibrary(applicationContext, it, fixture)) }
    private fun load() {
        if (!active || saving) return
        if (querying) { dirty = true; return }; querying = true; val token = generation; val after = cursor
        worker.execute {
            val result = runCatching { withLibrary { library ->
                var session = requireNotNull(library.session(id))
                if (session.state in listOf(HealthOriginalExportState.QUEUED, HealthOriginalExportState.GENERATING)) {
                    val states = androidx.work.WorkManager.getInstance(applicationContext).getWorkInfosForUniqueWork(HealthOriginalExportScheduler.workName(id, session.dispatch)).get().map { it.state }
                    if (HealthOriginalExportScheduler.terminal(states)) { library.cannotStart(id, session.dispatch, "worker_failed"); session = requireNotNull(library.session(id)) }
                }
                val completed = session.state in listOf(HealthOriginalExportState.GENERATED, HealthOriginalExportState.SAVED)
                val files = if (completed || session.state == HealthOriginalExportState.REVIEW) library.items(id, after) else emptyList()
                Triple(session, files, completed && library.file(session).isFile)
            } }
            main.post {
                querying = false
                if (active && token == generation) result.fold({ (session, files, available) -> render(session, files, available) }, {
                    body.removeAllViews(); body.addView(ui.text(getString(R.string.health_storage_error))); body.addView(ui.command(R.string.common_retry) { load() })
                })
                if (active && (dirty || token != generation)) { dirty = false; load() }
            }
        }
    }
    private fun render(session: HealthOriginalExportSession, files: List<HealthOriginal>, available: Boolean) {
        val name = if (session.state in listOf(HealthOriginalExportState.QUEUED, HealthOriginalExportState.GENERATING)) HealthOriginalExportScheduler.workName(id, session.dispatch) else ""
        if (name != observedWork) {
            workUpdates?.removeObserver(workObserver); workUpdates = null; observedWork = name
            if (name.isNotEmpty()) workUpdates = androidx.work.WorkManager.getInstance(applicationContext).getWorkInfosForUniqueWorkLiveData(name).also { it.observeForever(workObserver) }
        }
        body.removeAllViews(); val content = ui.column().apply { setPadding(ui.dp(16), ui.dp(16), ui.dp(16), ui.dp(24)) }
        body.addView(ScrollView(this).apply { addView(content) }, LinearLayout.LayoutParams(-1, 0, 1f))
        content.addView(ui.text(getString(session.title()), 20f, bold = true).apply { tag = "health-export-state" })
        ui.add(content, ui.text(getString(R.string.health_library_summary, session.count, android.text.format.Formatter.formatShortFileSize(this, session.sourceBytes)), 15f), 12)
        ui.add(content, ui.text(getString(R.string.health_library_originals_only), 13f, muted = true), 8)
        when (session.state) {
            HealthOriginalExportState.REVIEW -> {
                if (session.missing > 0) ui.add(content, ui.text(getString(R.string.health_library_missing_count, session.missing), 14f), 12)
                manifest(content, files)
                val consent = CheckBox(this).apply { text = getString(R.string.health_library_plain_consent); textSize = 14f; tag = "health-export-consent"; isSaveEnabled = false }
                ui.add(content, consent, 16)
                ui.add(content, ui.command(R.string.health_library_generate) {
                    if (!consent.isChecked) Toast.makeText(this, R.string.health_library_consent_required, Toast.LENGTH_LONG).show()
                    else mutate { library -> library.queue(id); HealthOriginalExportScheduler.enqueue(applicationContext, id) }
                }.apply { isEnabled = session.missing == 0L; alpha = if (isEnabled) 1f else .4f; tag = "health-export-generate" }, 12)
                ui.add(content, ui.command(R.string.health_library_edit_selection) { edit() }, 12)
            }
            HealthOriginalExportState.QUEUED, HealthOriginalExportState.GENERATING -> {
                ui.add(content, ui.text(getString(R.string.health_library_progress, session.completed, session.count), 15f), 16)
                ui.add(content, ui.command(R.string.common_cancel) { mutate { it.cancel(id) } }, 16)
            }
            HealthOriginalExportState.GENERATED, HealthOriginalExportState.SAVED -> {
                val item = HealthExportShareItem.originals(session)
                ui.add(content, ui.text(android.text.format.Formatter.formatShortFileSize(this, session.archiveBytes), 16f), 16)
                ui.add(content, ui.text(session.sha256, 11f, muted = true).apply { setTextIsSelectable(true) }, 8)
                ui.add(content, ui.text(getString(R.string.health_library_plain_warning), 14f, muted = true), 12)
                if (session.verifiedSaveAt > 0) ui.add(content, ui.text(getString(R.string.health_library_verified_at,
                    java.text.DateFormat.getDateTimeInstance().format(java.util.Date(session.verifiedSaveAt))), 13f, muted = true), 8)
                val running = HealthOriginalArchive.isSaving(id)
                val status = when {
                    running -> R.string.health_library_saving
                    session.pendingSave.isNotBlank() -> R.string.health_library_save_interrupted
                    session.saveFailed -> R.string.health_library_save_unverified
                    else -> null
                }
                if (status != null) ui.add(content, ui.text(getString(status), 14f).apply { tag = "health-original-save-notice" }, 8)
                if (available) {
                    ui.add(content, ui.command(R.string.health_library_save_zip) {
                        if (!saving && !HealthOriginalArchive.isSaving(id) && pendingPickerAttempt.isBlank()) {
                            pendingPickerAttempt = session.attempt
                            try {
                                startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE).setType(item.mime)
                                    .putExtra(Intent.EXTRA_TITLE, item.name), SAVE)
                            } catch (_: Exception) {
                                pendingPickerAttempt = ""
                                Toast.makeText(this, R.string.health_import_save_failed, Toast.LENGTH_LONG).show()
                            }
                        }
                    }.apply { tag = "health-export-save"; isEnabled = !running }, 16)
                    ui.add(content, ui.row(getString(R.string.health_export_share)) {
                        shareDialog?.dismiss()
                        shareDialog = HealthExportShare.confirm(this, item, fixture)
                    }.apply { tag = "health-original-export-share" }, 8)
                } else ui.add(content, ui.text(getString(R.string.health_library_archive_missing), 14f), 12)
                manifest(content, files)
            }
            else -> {
                ui.add(content, ui.text(getString(when (session.error) { "original_missing" -> R.string.health_original_missing; "original_changed" -> R.string.health_library_source_changed; "background_unavailable" -> R.string.health_library_background_failed; else -> R.string.health_library_failed }), 14f), 16)
                if (session.state == HealthOriginalExportState.FAILED) ui.add(content, ui.command(R.string.common_retry) { mutate { library -> library.queue(id); HealthOriginalExportScheduler.enqueue(applicationContext, id) } }, 16)
                ui.add(content, ui.command(R.string.health_library_edit_selection) { edit() }, 12)
            }
        }
    }
    private fun manifest(content: LinearLayout, files: List<HealthOriginal>) {
        if (files.isNotEmpty()) ui.add(content, ui.text(getString(R.string.health_library_export_manifest), 17f, bold = true), 12)
        files.take(30).forEach { original -> ui.add(content, ui.row(original.name, "${original.mime} \u00b7 ${android.text.format.Formatter.formatShortFileSize(this, original.size)}") {
            startActivity(Intent(this, HealthCaptureActivity::class.java).putExtra("original", original.id)
                .putExtra("health_review_test_id", fixture))
        }, 6) }
        if (previous.isNotEmpty()) ui.add(content, ui.command(R.string.health_previous_page) { cursor = previous.removeAt(previous.lastIndex); load() }, 12)
        if (files.size > 30) ui.add(content, ui.command(R.string.health_next_page) { previous += cursor; cursor = files[29].id; load() }, 12)
    }
    private fun edit() { mutate({ finish() }) { it.edit(id) } }
    private fun mutate(success: () -> Unit = { load() }, action: (HealthOriginalLibraryStore) -> Any) {
        worker.execute {
            val result = runCatching { withLibrary(action) }
            main.post { if (active) result.fold({ success() }, { Toast.makeText(this, R.string.health_storage_error, Toast.LENGTH_LONG).show(); load() }) }
        }
    }
    @Deprecated("Native document result") override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != SAVE) return
        val attempt = pendingPickerAttempt
        pendingPickerAttempt = ""
        if (resultCode != RESULT_OK || attempt.isBlank()) return
        val uri = data?.data ?: return; saving = true; body.removeAllViews(); body.addView(ui.text(getString(R.string.health_library_saving)))
        worker.execute {
            val result = runCatching { withLibrary { library ->
                val session = requireNotNull(library.session(id))
                check(session.attempt == attempt)
                HealthPrivacyStore.track(applicationContext, HealthAccessScope.originals(session.count, zip = true), HealthOverviewDatabases(fixture).privacy) {
                    HealthOriginalArchive.saveVerified(library, session,
                        { contentResolver.openOutputStream(uri, "wt") ?: error("Cannot open export destination") },
                        { contentResolver.openInputStream(uri) ?: error("Cannot verify export destination") },
                        { android.provider.DocumentsContract.deleteDocument(contentResolver, uri) })
                }
            } }
            main.post { saving = false; if (active) { if (result.isFailure) Toast.makeText(this, R.string.health_import_save_failed, Toast.LENGTH_LONG).show(); load() } }
        }
    }
    companion object { private const val SAVE = 91 }
}

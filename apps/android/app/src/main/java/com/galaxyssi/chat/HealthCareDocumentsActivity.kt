package com.galaxyssi.chat

import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.database.ContentObserver
import android.graphics.Bitmap
import android.os.Bundle
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper
import android.widget.LinearLayout
import java.util.concurrent.Executors

class HealthCareDocumentsActivity : Activity() {
    private val ui by lazy { HealthCenterViews(this) }
    private val names by lazy { intent.healthNavigationDatabases() }
    private val repository by lazy { HealthCareDocumentRepository(applicationContext, names) }
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private lateinit var body: LinearLayout
    private var concernId = ""
    private var encounterId = ""
    private var active = false
    private var busy = false
    private var dirty = false
    private var generation = 0
    private var signal = CancellationSignal()
    private var snapshot: HealthCareDocumentSnapshot? = null
    private var library = false
    private var cursor = Int.MAX_VALUE
    private var pageRevision: Int? = null
    private val previous = mutableListOf<Int>()
    private var fileCursor: Pair<Long, String>? = null
    private val filePrevious = mutableListOf<Pair<Long, String>?>()
    private var dialog: AlertDialog? = null
    private var dialogContent: LinearLayout? = null
    private var preview: HealthReviewSourceView? = null
    private var bitmap: Bitmap? = null
    private val expiry = Runnable { if (active) invalidate() }
    private val observer = object : ContentObserver(main) { override fun onChange(selfChange: Boolean) { if (active) invalidate() } }

    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        concernId = intent.getStringExtra("health_care_id").orEmpty()
        encounterId = intent.getStringExtra("health_encounter_id").orEmpty()
        if (!HealthProfilePolicy.uuid(concernId) || !HealthProfilePolicy.uuid(encounterId)) { finish(); return }
        body = healthProfileBody(R.string.health_document_title) { back() }
    }
    override fun onStart() {
        super.onStart(); if (!::body.isInitialized) return
        active = true
        listOf(HealthCareStore.changes(this, names.care), HealthRecordStore.changes(this, names.records),
            HealthPrivacyStore.changes(this, names.privacy), HealthOriginalStore.changesUri(this)).forEach {
            contentResolver.registerContentObserver(it, true, observer)
        }
        load()
    }
    override fun onStop() {
        if (::body.isInitialized) { active = false; clear(); reset(); contentResolver.unregisterContentObserver(observer) }
        super.onStop()
    }
    override fun onDestroy() { worker.shutdown(); super.onDestroy() }
    override fun onTrimMemory(level: Int) {
        super.onTrimMemory(level)
        if (::body.isInitialized && level >= TRIM_MEMORY_RUNNING_LOW) { clear(); reset(); if (active) load() }
    }
    @Deprecated("Native activity navigation")
    override fun onBackPressed() { back() }
    private fun back() { if (library) { clear(); reset(); load() } else finish() }
    private fun reset() { library = false; cursor = Int.MAX_VALUE; pageRevision = null; previous.clear(); fileCursor = null; filePrevious.clear() }
    private fun closeDialog() {
        dialog?.setOnDismissListener(null); dialog?.dismiss(); dialog = null
        preview?.bitmap = null; preview = null
        dialogContent?.removeAllViews(); dialogContent = null
        bitmap?.let(HealthOriginalThumbnail::clear); bitmap = null
    }
    private fun clear() {
        generation++; signal.cancel(); signal = CancellationSignal(); snapshot = null
        closeDialog(); body.removeAllViews(); main.removeCallbacks(expiry)
    }
    private fun invalidate() { clear(); reset(); load() }
    private fun load() {
        if (!active) return
        if (busy) { dirty = true; return }
        clear()
        healthProfileContent(body).addView(ui.text(getString(R.string.health_loading), 15f))
        val picking = library; val before = cursor; val expected = pageRevision; val filesBefore = fileCursor; val cancellation = signal
        work({
            val value = repository.load(concernId, encounterId, if (picking) Int.MAX_VALUE else before, expected)
            value to if (picking) repository.library(value.visit, filesBefore, cancellation) else null
        }) { (value, files) ->
            snapshot = value; pageRevision = value.visit.issue.revision
            val content = healthProfileContent(body).apply { tag = "health-document-content" }
            content.addView(ui.text(value.visit.selected!!.details.purpose, 18f, bold = true))
            ui.add(content, ui.text(getString(R.string.health_document_notice), 13f, muted = true), 8)
            if (files == null) linked(content, value) else originals(content, value, files)
            main.postDelayed(expiry, 600_000L)
        }
    }
    private fun pageText(source: HealthCareDocumentRef) = source.page?.let { getString(R.string.health_document_page, it, source.pageCount) }
        ?: getString(R.string.health_document_whole)
    private fun linked(content: LinearLayout, value: HealthCareDocumentSnapshot) {
        ui.add(content, ui.command(R.string.health_document_add) { library = true; fileCursor = null; filePrevious.clear(); load() }
            .apply { tag = "document-add" }, 16)
        if (value.items.isEmpty()) ui.add(content, ui.text(getString(R.string.health_document_empty), 15f, muted = true), 16)
        value.items.forEach { item ->
            ui.add(content, ui.profileRow(item.original?.name ?: getString(R.string.health_document_missing),
                pageText(item.link.source) + if (item.available) "" else "\n${getString(R.string.health_document_missing)}") {
                choose(value, item.original.takeIf { item.available }, item.link)
            }.apply { tag = "document-row-${item.link.id}" }, 12)
        }
        if (previous.isNotEmpty()) ui.add(content, ui.command(R.string.health_agenda_previous) {
            cursor = previous.removeAt(previous.lastIndex); load()
        }.apply { tag = "document-previous" }, 12)
        value.next?.let { next -> ui.add(content, ui.command(R.string.health_agenda_next) { previous += cursor; cursor = next; load() }
            .apply { tag = "document-next" }, 12) }
    }
    private fun originals(content: LinearLayout, value: HealthCareDocumentSnapshot, files: HealthLibraryPage) {
        ui.add(content, ui.profileRow(getString(R.string.health_document_import)) {
            startActivity(healthCaptureIntent(this, names, HealthCaptureEntry.FILE))
        }.apply { tag = "document-import" }, 12)
        if (files.originals.isEmpty()) ui.add(content, ui.text(getString(R.string.health_document_library_empty), 15f, muted = true), 16)
        files.originals.forEach { original -> ui.add(content, ui.profileRow(original.name, original.mime) { choose(value, original, null) }
            .apply { tag = "document-original-${original.id}" }, 12) }
        if (filePrevious.isNotEmpty()) ui.add(content, ui.command(R.string.health_agenda_previous) {
            fileCursor = filePrevious.removeAt(filePrevious.lastIndex); load()
        }.apply { tag = "document-library-previous" }, 12)
        files.next?.let { next -> ui.add(content, ui.command(R.string.health_agenda_next) {
            filePrevious += fileCursor; fileCursor = next; load()
        }.apply { tag = "document-library-next" }, 12) }
    }
    private fun choose(value: HealthCareDocumentSnapshot, original: HealthOriginal?, link: HealthCareDocumentLink?) {
        if (busy) return
        closeDialog()
        val content = ui.column().apply { setPadding(ui.dp(20), ui.dp(8), ui.dp(20), ui.dp(8)) }
        if (original != null) {
            if (original.mime == "application/pdf" || original.mime.startsWith("image/")) {
                ui.add(content, ui.command(R.string.health_document_choose_page) {
                    closeDialog(); showPage(value, original, link?.source?.page ?: 1, link == null)
                }.apply { tag = "document-preview" }, 8)
            }
            if (link == null) ui.add(content, ui.command(R.string.health_document_link_whole) { prepare(value, original, null) }
                .apply { tag = "document-whole" }, 8)
        }
        if (link != null) ui.add(content, ui.command(R.string.health_document_remove) {
            closeDialog()
            dialog = AlertDialog.Builder(this).setTitle(R.string.health_document_remove).setMessage(R.string.health_document_remove_notice)
                .setNegativeButton(R.string.common_cancel, null).setPositiveButton(R.string.health_document_remove) { _, _ ->
                    closeDialog(); work({ repository.remove(value, link) }) { reset(); load() }
                }.show()
        }.apply { tag = "document-remove" }, 8)
        dialogContent = content
        dialog = AlertDialog.Builder(this).setTitle(original?.name ?: getString(R.string.health_document_missing)).setView(content)
            .setNegativeButton(R.string.common_cancel, null).show().also { it.setOnDismissListener { closeDialog() } }
    }
    private fun showPage(value: HealthCareDocumentSnapshot, original: HealthOriginal, page: Int, allowLink: Boolean) {
        val cancellation = signal
        work({ repository.raster(value.visit, original, page, cancellation) }, { HealthOriginalThumbnail.clear(it.bitmap) }) { raster ->
            closeDialog(); bitmap = raster.bitmap
            val content = ui.column()
            preview = HealthReviewSourceView(this).apply { bitmap = raster.bitmap; contentDescription = getString(R.string.health_document_preview); tag = "document-raster" }
            val viewport = GalaxySSIPinchZoomViewport(this).apply { attach(preview!!) }
            content.addView(viewport, LinearLayout.LayoutParams(-1, ui.dp(minOf(360, resources.configuration.screenHeightDp / 2))))
            val controls = ui.line()
            if (page > 1) controls.addView(ui.command(R.string.health_agenda_previous) {
                closeDialog(); showPage(value, original, page - 1, allowLink)
            }.apply { tag = "document-page-previous" }, LinearLayout.LayoutParams(0, -2, 1f))
            if (page < raster.pageCount) controls.addView(ui.command(R.string.health_agenda_next) {
                closeDialog(); showPage(value, original, page + 1, allowLink)
            }.apply { tag = "document-page-next" }, LinearLayout.LayoutParams(0, -2, 1f))
            content.addView(controls)
            if (allowLink) ui.add(content, ui.command(R.string.health_document_link_page) { prepare(value, original, page) }
                .apply { tag = "document-link-page" }, 8)
            if (!allowLink) value.items.firstOrNull { item -> item.link.source.matches(original) &&
                (item.link.source.page == null || item.link.source.page == page) }?.let { item ->
                ui.add(content, ui.command(R.string.health_instruction_extract) {
                    closeDialog()
                    startActivity(Intent(this, HealthCareInstructionsActivity::class.java).putHealthNavigationFixture(names)
                        .putExtra("health_care_id", concernId).putExtra("health_encounter_id", encounterId)
                        .putExtra("health_document_id", item.link.id).putExtra("health_document_page", page))
                }.apply { tag = "document-instructions" }, 8)
            }
            dialogContent = content
            dialog = AlertDialog.Builder(this).setTitle(getString(R.string.health_document_page, page, raster.pageCount))
                .setView(content).setNegativeButton(R.string.common_cancel, null).show().also { it.setOnDismissListener { closeDialog() } }
        }
    }
    private fun prepare(value: HealthCareDocumentSnapshot, original: HealthOriginal, page: Int?) {
        closeDialog(); val cancellation = signal
        work({ repository.prepare(value.visit, original, page, cancellation) }) { candidate ->
            dialog = AlertDialog.Builder(this).setTitle(R.string.health_document_confirm)
                .setMessage(getString(R.string.health_document_confirm_notice, candidate.original.name, pageText(candidate.source)))
                .setNegativeButton(R.string.common_cancel, null).setPositiveButton(R.string.health_document_link) { _, _ ->
                    closeDialog(); work({ repository.confirm(candidate) }) { reset(); load() }
                }.show()
        }
    }
    private fun <T> work(action: () -> T, dispose: (T) -> Unit = {}, done: (T) -> Unit) {
        if (busy) return
        busy = true; dirty = false; val token = generation
        worker.execute {
            val result = runCatching(action)
            main.post {
                busy = false
                if (!active || isFinishing || isDestroyed || dirty || token != generation) {
                    result.getOrNull()?.let(dispose)
                    if (active && !isFinishing && !isDestroyed) { dirty = false; load() }
                    return@post
                }
                result.fold(done) { error ->
                    clear(); reset()
                    val content = healthProfileContent(body)
                    val blocked = error is HealthAccessBlocked || error is HealthPrivacyConflict
                    val message = if (error is HealthCareSourceInUse) R.string.health_instruction_source_in_use else if (blocked) R.string.health_overview_permission else if (error is HealthCareConflict)
                        R.string.health_document_changed else R.string.health_document_failed
                    content.addView(ui.text(getString(message), 15f))
                    ui.add(content, if (blocked) ui.profileRow(getString(R.string.health_privacy_title)) {
                        startActivity(Intent(this, HealthPrivacyActivity::class.java).putHealthNavigationFixture(names))
                    } else ui.command(R.string.health_agenda_retry) { load() }.apply { tag = "document-retry" }, 12)
                }
            }
        }
    }
}

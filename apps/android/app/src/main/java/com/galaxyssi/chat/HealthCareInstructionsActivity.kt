package com.galaxyssi.chat

import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.database.ContentObserver
import android.os.Bundle
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper
import android.widget.CheckBox
import android.widget.LinearLayout
import android.widget.ScrollView
import java.util.UUID
import java.util.concurrent.Executors

class HealthCareInstructionsActivity : Activity() {
    private val ui by lazy { HealthCenterViews(this) }
    private val names by lazy { intent.healthNavigationDatabases() }
    private val repository by lazy { HealthCareInstructionRepository(applicationContext, names) }
    private val editor by lazy { HealthCareInstructionEditor(this) }
    private val actions by lazy { HealthCareActionReview(this, names) }
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
    private var snapshot: HealthCareInstructionSnapshot? = null
    private var reading: HealthCareInstructionReading? = null
    private var requestSource: String? = null
    private var requestPage = 1
    private var lineStart = 0
    private val selectedLines = mutableSetOf<Int>()
    private var selectedId: String? = null
    private var history = false
    private var cursor = Int.MAX_VALUE
    private var pageRevision: Int? = null
    private val previous = mutableListOf<Int>()
    private var historyCursor = Int.MAX_VALUE
    private val historyPrevious = mutableListOf<Int>()
    private var dialog: AlertDialog? = null
    private var sourceDialog: HealthCareInstructionSourceDialog? = null
    private val expiry = Runnable { if (active) invalidate() }
    private val observer = object : ContentObserver(main) { override fun onChange(selfChange: Boolean) { if (active) invalidate() } }
    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        concernId = intent.getStringExtra("health_care_id").orEmpty(); encounterId = intent.getStringExtra("health_encounter_id").orEmpty()
        if (!HealthProfilePolicy.uuid(concernId) || !HealthProfilePolicy.uuid(encounterId)) { finish(); return }
        if (state == null) {
            requestSource = intent.getStringExtra("health_document_id")?.takeIf(HealthProfilePolicy::uuid)
            requestPage = intent.getIntExtra("health_document_page", 1)
        }
        body = healthProfileBody(R.string.health_instruction_title) { back() }
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
    override fun onDestroy() { editor.clear(); actions.destroy(); worker.shutdown(); super.onDestroy() }
    override fun onTrimMemory(level: Int) {
        super.onTrimMemory(level)
        if (::body.isInitialized && level >= TRIM_MEMORY_RUNNING_LOW) { clear(); reset(); if (active) load() }
    }
    @Deprecated("Native activity navigation")
    override fun onBackPressed() { back() }
    private fun back() {
        if (reading != null) { clear(); reset(); load() }
        else if (history) { history = false; historyCursor = Int.MAX_VALUE; historyPrevious.clear(); load() }
        else if (selectedId != null) { selectedId = null; load() }
        else finish()
    }
    private fun clear() {
        generation++; signal.cancel(); signal = CancellationSignal(); snapshot = null; reading = null
        editor.clear(); actions.clear(); dialog?.dismiss(); dialog = null; sourceDialog?.dismiss(); sourceDialog = null
        main.removeCallbacks(expiry); body.removeAllViews(); selectedLines.clear(); lineStart = 0
    }
    private fun reset() {
        requestSource = null; selectedId = null; history = false; cursor = Int.MAX_VALUE; pageRevision = null
        previous.clear(); historyCursor = Int.MAX_VALUE; historyPrevious.clear()
    }
    private fun invalidate() { val selected = selectedId; clear(); reset(); selectedId = selected; load() }
    private fun load() {
        if (!active) return
        if (busy) { dirty = true; return }
        clear()
        val source = requestSource; val cancellation = signal
        if (source != null) {
            healthProfileContent(body).addView(ui.text(getString(R.string.health_instruction_reading), 15f))
            work({ repository.read(concernId, encounterId, source, requestPage, cancellation) }) {
                requestSource = null; reading = it; renderReading(it); main.postDelayed(expiry, 600_000L)
            }
        } else {
            healthProfileContent(body).addView(ui.text(getString(R.string.health_loading), 15f))
            val selected = selectedId; val before = if (selected == null) cursor else Int.MAX_VALUE
            val expected = pageRevision; val older = historyCursor.takeIf { history }
            work({ repository.load(concernId, encounterId, before, expected, selected, older) }) {
                snapshot = it; pageRevision = it.visit.issue.revision; render(it); main.postDelayed(expiry, 600_000L)
            }
        }
    }
    private fun sources() { startActivity(Intent(this, HealthCareDocumentsActivity::class.java).putHealthNavigationFixture(names)
        .putExtra("health_care_id", concernId).putExtra("health_encounter_id", encounterId)) }
    private fun renderReading(value: HealthCareInstructionReading) {
        val content = healthProfileContent(body).apply { tag = "instruction-reading" }
        content.addView(ui.text(value.original.name, 17f, bold = true))
        ui.add(content, ui.text(getString(R.string.health_document_page, value.page.page, value.pageCount), 14f), 8)
        ui.add(content, ui.text(getString(if (value.page.recognition == HealthRecognition.PDF_TEXT) R.string.health_instruction_method_pdf else R.string.health_instruction_method_ocr), 13f, muted = true), 8)
        ui.add(content, ui.text(getString(R.string.health_instruction_select_notice), 14f, muted = true), 8)
        if (value.page.blurry) ui.add(content, ui.text(getString(R.string.health_instruction_blurry), 14f), 8)
        if (value.page.lines.isEmpty()) ui.add(content, ui.text(getString(R.string.health_instruction_no_text), 15f), 16)
        val error = ui.text("", 13f)
        for (index in lineStart until minOf(lineStart + 50, value.page.lines.size)) {
            val line = value.page.lines[index]
            ui.add(content, CheckBox(this).apply {
                text = line.text; setTextColor(getColor(R.color.text_primary)); textSize = 15f
                isChecked = index in selectedLines; isEnabled = line.text.isNotBlank(); tag = "instruction-line-$index"
                setOnCheckedChangeListener { button, checked ->
                    if (checked) selectedLines += index else selectedLines -= index
                    if (selectedLines.size > 200 || selectedLines.sumOf { value.page.lines[it].text.length + 1 } > 8000) {
                        button.isChecked = false; error.text = getString(R.string.health_instruction_selection_invalid)
                    }
                }
            }, 8)
        }
        if (lineStart > 0) ui.add(content, ui.command(R.string.health_agenda_previous) { lineStart -= 50; renderReading(value) }, 12)
        if (lineStart + 50 < value.page.lines.size) ui.add(content, ui.command(R.string.health_agenda_next) { lineStart += 50; renderReading(value) }, 12)
        ui.add(content, ui.command(R.string.health_instruction_select) {
            if (busy) return@command
            val chosen = selectedLines.toSet()
            if (runCatching { HealthCareInstructionSource.select(value.document, value.page, value.pageCount, chosen) }.isFailure) {
                error.text = getString(R.string.health_instruction_selection_invalid)
            } else {
                val operation = UUID.randomUUID().toString()
                selectedId = operation
                work({ repository.create(value, chosen, operation) }) { reset(); selectedId = it.value.id; load() }
            }
        }.apply { tag = "instruction-create" }, 16)
        content.addView(error)
    }
    private fun render(value: HealthCareInstructionSnapshot) {
        val content = healthProfileContent(body).apply { tag = "instruction-content" }
        content.addView(ui.text(value.visit.selected!!.details.purpose, 17f, bold = true))
        ui.add(content, ui.text(getString(R.string.health_instruction_notice), 13f, muted = true), 8)
        when {
            history -> {
                value.history!!.items.forEach { entry -> details(content, entry) }
                if (historyPrevious.isNotEmpty()) ui.add(content, ui.command(R.string.health_agenda_previous) {
                    historyCursor = historyPrevious.removeAt(historyPrevious.lastIndex); load()
                }, 12)
                value.history.next?.let { next -> ui.add(content, ui.command(R.string.health_agenda_next) { historyPrevious += historyCursor; historyCursor = next; load() }, 12) }
            }
            value.selected != null -> {
                val entry = value.selected
                details(content, entry)
                val mapped = value.visit.issue.actions.firstOrNull { it.id == HealthCareInstructionActionPolicy.actionId(entry) }
                if (mapped != null) ui.add(content, ui.command(R.string.health_instruction_action_open) {
                    actions.show(value.visit.issue.id, mapped.id)
                }.apply { tag = "instruction-action-open" }, 16)
                else if (value.available && HealthCareInstructionActionPolicy.eligible(entry)) ui.add(content,
                    ui.command(R.string.health_instruction_action_add) { confirmAction(value) }.apply { tag = "instruction-action-add" }, 16)
                else ui.add(content, ui.text(getString(R.string.health_instruction_action_incomplete), 14f, muted = true), 12)
                if (value.available) ui.add(content, ui.command(R.string.health_instruction_edit) {
                    if (busy) return@command
                    val operation = UUID.randomUUID().toString()
                    editor.show(entry) { draft -> work({ repository.update(value, draft, operation) }) { load() } }
                }.apply { tag = "instruction-edit" }, 16)
                else ui.add(content, ui.text(getString(R.string.health_document_missing), 15f), 16)
                ui.add(content, ui.profileRow(getString(R.string.health_document_preview)) { preview(value) }.apply { isEnabled = value.available; tag = "instruction-preview" }, 12)
                ui.add(content, ui.profileRow(getString(R.string.health_instruction_history)) { history = true; load() }.apply { tag = "instruction-history" }, 8)
                ui.add(content, ui.profileRow(getString(R.string.health_instruction_delete)) {
                    dialog = AlertDialog.Builder(this).setTitle(R.string.health_instruction_delete).setMessage(R.string.health_instruction_delete_notice)
                        .setNegativeButton(R.string.common_cancel, null).setPositiveButton(R.string.health_instruction_delete) { _, _ ->
                            if (busy) return@setPositiveButton
                            selectedId = null
                            work({ repository.delete(value) }) { reset(); load() }
                        }.show()
                }.apply { tag = "instruction-delete" }, 8)
            }
            else -> {
                ui.add(content, ui.profileRow(getString(R.string.health_instruction_sources)) { sources() }.apply { tag = "instruction-sources" }, 16)
                if (value.page.items.isEmpty()) ui.add(content, ui.text(getString(R.string.health_instruction_empty), 15f, muted = true), 12)
                value.page.items.forEach { entry -> ui.add(content, ui.profileRow(entry.draft.fields[HealthCareInstructionField.NAME]?.text?.takeIf(String::isNotBlank)
                    ?: getString(entry.draft.kind.label()), getString(entry.draft.label())) { selectedId = entry.id; load() }.apply { tag = "instruction-row-${entry.id}" }, 12) }
                if (previous.isNotEmpty()) ui.add(content, ui.command(R.string.health_agenda_previous) { cursor = previous.removeAt(previous.lastIndex); load() }, 12)
                value.page.next?.let { next -> ui.add(content, ui.command(R.string.health_agenda_next) { previous += cursor; cursor = next; load() }, 12) }
            }
        }
    }
    private fun confirmAction(value: HealthCareInstructionSnapshot) {
        if (busy) return
        val entry = value.selected ?: return
        val content = ui.column().apply { setPadding(ui.dp(20), ui.dp(8), ui.dp(20), ui.dp(16)) }
        details(content, entry)
        ui.add(content, ui.text(getString(R.string.health_instruction_action_notice), 14f, muted = true), 16)
        val checked = CheckBox(this).apply {
            text = getString(R.string.health_instruction_action_check); setTextColor(getColor(R.color.text_primary))
            tag = "instruction-action-checked"
        }
        ui.add(content, checked, 12)
        dialog = AlertDialog.Builder(this).setTitle(R.string.health_instruction_action_add)
            .setView(ScrollView(this).apply { addView(content) }).setNegativeButton(R.string.common_cancel, null)
            .setPositiveButton(R.string.health_instruction_action_confirm, null).create().also { d ->
                d.setOnDismissListener { content.removeAllViews() }
                d.setOnShowListener {
                    val button = d.getButton(AlertDialog.BUTTON_POSITIVE)
                    button.isEnabled = false
                    checked.setOnCheckedChangeListener { _, enabled -> button.isEnabled = enabled }
                    button.setOnClickListener {
                        if (!checked.isChecked || busy) return@setOnClickListener
                        val cancellation = signal
                        d.dismiss()
                        work({ repository.confirmAction(value, cancellation) }) { load() }
                    }
                }
                d.show()
            }
    }
    private fun details(content: LinearLayout, entry: HealthCareInstruction) {
        ui.add(content, ui.text("${getString(entry.draft.kind.label())}\n${getString(entry.draft.label())}", 17f, bold = true), 16)
        ui.add(content, ui.text(getString(R.string.health_revision, entry.revision), 13f, muted = true), 8)
        ui.add(content, ui.text(getString(R.string.health_document_page, entry.source.original.page, entry.source.original.pageCount), 14f), 8)
        ui.add(content, ui.text(entry.source.quote, 15f), 8)
        entry.draft.required.forEach { field ->
            val value = entry.draft.fields[field] ?: HealthCareInstructionValue()
            val status = when (value.review) { HealthCareFieldReview.TRANSCRIBED -> R.string.health_instruction_transcribed
                HealthCareFieldReview.NOT_STATED -> R.string.health_instruction_not_stated; else -> R.string.health_instruction_pending }
            ui.add(content, ui.text(getString(field.label()), 13f, muted = true), 12)
            ui.add(content, ui.text(listOf(value.text, getString(status)).filter(String::isNotEmpty).joinToString("\n"), 15f), 4)
        }
    }
    private fun preview(value: HealthCareInstructionSnapshot) {
        val entry = value.selected ?: return; val cancellation = signal
        work({
            val original = HealthExportShare.openOriginals(applicationContext, names.fixture).use { it.original(entry.source.original.originalId) } ?: throw HealthCareConflict()
            require(entry.source.original.matches(original))
            HealthCareDocumentRepository(applicationContext, names).raster(value.visit, original, entry.source.original.page!!, cancellation)
        }, { HealthOriginalThumbnail.clear(it.bitmap) }) {
            sourceDialog?.dismiss(); sourceDialog = HealthCareInstructionSourceDialog(this, it.bitmap, entry.source).also { it.show() }
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
                    content.addView(ui.text(getString(if (blocked) R.string.health_overview_permission else R.string.health_instruction_failed), 15f))
                    ui.add(content, if (blocked) ui.profileRow(getString(R.string.health_privacy_title)) {
                        startActivity(Intent(this, HealthPrivacyActivity::class.java).putHealthNavigationFixture(names))
                    } else ui.command(R.string.health_agenda_retry) { load() }.apply { tag = "instruction-retry" }, 12)
                }
            }
        }
    }
}

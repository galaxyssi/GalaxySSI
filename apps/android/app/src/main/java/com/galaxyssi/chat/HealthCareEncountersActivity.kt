package com.galaxyssi.chat

import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.database.ContentObserver
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.widget.LinearLayout
import java.util.UUID
import java.util.concurrent.Executors

class HealthCareEncountersActivity : Activity() {
    private val ui by lazy { HealthCenterViews(this) }
    private val names by lazy { intent.healthNavigationDatabases() }
    private val repository by lazy { HealthCareEncounterRepository(applicationContext, names) }
    private val editor by lazy { HealthCareEncounterEditor(this) }
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private lateinit var body: LinearLayout
    private var concernId = ""
    private var active = false
    private var generation = 0
    private var busy = false
    private var dirty = false
    private var snapshot: HealthCareEncounterSnapshot? = null
    private var dialog: AlertDialog? = null
    private var selectedId: String? = null
    private var history = false
    private var cursor = Int.MAX_VALUE
    private var pageRevision: Int? = null
    private val previous = mutableListOf<Int>()
    private var historyCursor = Int.MAX_VALUE
    private val historyPrevious = mutableListOf<Int>()
    private val expiry = Runnable { if (active) invalidate() }
    private val observer = object : ContentObserver(main) { override fun onChange(selfChange: Boolean) { if (active) invalidate() } }

    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        concernId = intent.getStringExtra("health_care_id").orEmpty()
        if (!HealthProfilePolicy.uuid(concernId)) { finish(); return }
        body = healthProfileBody(R.string.health_encounter_title) { back() }
    }
    override fun onStart() {
        super.onStart(); if (!::body.isInitialized) return
        active = true
        listOf(HealthCareStore.changes(this, names.care), HealthRecordStore.changes(this, names.records),
            HealthPrivacyStore.changes(this, names.privacy)).forEach { contentResolver.registerContentObserver(it, false, observer) }
        load()
    }
    override fun onStop() {
        if (::body.isInitialized) {
            active = false; clear(); reset(); contentResolver.unregisterContentObserver(observer)
        }
        super.onStop()
    }
    override fun onDestroy() { editor.clear(); worker.shutdown(); super.onDestroy() }
    override fun onTrimMemory(level: Int) {
        super.onTrimMemory(level)
        if (::body.isInitialized && level >= TRIM_MEMORY_RUNNING_LOW) { clear(); reset(); if (active) load() }
    }
    @Deprecated("Native activity navigation")
    override fun onBackPressed() { back() }
    private fun back() {
        editor.clear(); dialog?.dismiss(); dialog = null
        if (history) { history = false; historyCursor = Int.MAX_VALUE; historyPrevious.clear(); load() }
        else if (selectedId != null) { selectedId = null; load() }
        else finish()
    }
    private fun clear() {
        generation++; snapshot = null; editor.clear(); dialog?.dismiss(); dialog = null
        main.removeCallbacks(expiry); body.removeAllViews()
    }
    private fun reset() {
        cursor = Int.MAX_VALUE; pageRevision = null; previous.clear()
        selectedId = null; history = false; historyCursor = Int.MAX_VALUE; historyPrevious.clear()
    }
    private fun invalidate() {
        val selected = selectedId
        clear(); reset(); selectedId = selected; load()
    }
    private fun load() {
        if (!active) return
        if (busy) { dirty = true; return }
        clear()
        healthProfileContent(body).addView(ui.text(getString(R.string.health_loading), 15f))
        val selected = selectedId; val older = historyCursor.takeIf { history }
        val after = if (selected == null) cursor else Int.MAX_VALUE
        val expected = if (selected == null && cursor != Int.MAX_VALUE) pageRevision else null
        work({ repository.load(concernId, after, expected, selected, older) }) {
            snapshot = it
            if (selectedId == null) pageRevision = it.page.concernRevision
            render(it); main.postDelayed(expiry, 600_000L)
        }
    }
    private fun render(value: HealthCareEncounterSnapshot) {
        val content = healthProfileContent(body).apply { tag = "health-encounter-content" }
        content.addView(ui.text(getString(value.issue.metric.titleResource()), 17f, bold = true))
        ui.add(content, ui.text(getString(R.string.health_encounter_notice), 13f, muted = true), 8)
        when {
            history -> showHistory(content, value)
            value.selected != null -> showDetail(content, value)
            else -> showList(content, value)
        }
    }
    private fun showList(content: LinearLayout, value: HealthCareEncounterSnapshot) {
        ui.add(content, ui.command(R.string.health_encounter_add) { edit(value, null) }.apply { tag = "encounter-add" }, 16)
        ui.add(content, ui.profileRow(getString(R.string.health_visit_title)) {
            startActivity(Intent(this, HealthCareVisitActivity::class.java).putHealthNavigationFixture(names).putExtra("health_care_id", concernId))
        }, 8)
        if (value.page.items.isEmpty()) ui.add(content, ui.text(getString(R.string.health_encounter_empty), 15f, muted = true), 16)
        value.page.items.forEach { entry -> ui.add(content, ui.profileRow(entry.details.purpose,
            "${getString(entry.details.state.label())}\n${encounterTime(this, entry.details.attendedAt ?: entry.details.plannedAt, entry.details.zone)}") {
            selectedId = entry.id; load()
        }.apply { tag = "encounter-row-${entry.id}" }, 12) }
        if (previous.isNotEmpty()) ui.add(content, ui.command(R.string.health_agenda_previous) {
            cursor = previous.removeAt(previous.lastIndex); load()
        }.apply { tag = "encounter-previous" }, 12)
        value.page.next?.let { next -> ui.add(content, ui.command(R.string.health_agenda_next) {
            previous += cursor; cursor = next; load()
        }.apply { tag = "encounter-next" }, 12) }
    }
    private fun details(content: LinearLayout, entry: HealthCareEncounter) {
        ui.add(content, ui.text(entry.details.purpose, 18f, bold = true), 16)
        ui.add(content, ui.text(getString(entry.details.state.label()), 15f), 8)
        fun field(label: Int, text: String) {
            ui.add(content, ui.text(getString(label), 13f, muted = true), 12)
            ui.add(content, ui.text(text.ifBlank { getString(R.string.health_encounter_unspecified) }, 15f), 4)
        }
        field(R.string.health_encounter_facility, entry.details.facility)
        field(R.string.health_encounter_planned, encounterTime(this, entry.details.plannedAt, entry.details.zone))
        if (entry.details.state == HealthCareEncounterState.ATTENDED)
            field(R.string.health_encounter_attended, encounterTime(this, entry.details.attendedAt, entry.details.zone))
        field(R.string.health_encounter_note, entry.details.note)
        field(R.string.health_encounter_recorded, encounterTime(this, entry.updatedAt, entry.details.zone))
    }
    private fun showDetail(content: LinearLayout, value: HealthCareEncounterSnapshot) {
        val entry = value.selected!!
        details(content, entry)
        ui.add(content, ui.profileRow(getString(R.string.health_document_title)) {
            startActivity(Intent(this, HealthCareDocumentsActivity::class.java).putHealthNavigationFixture(names)
                .putExtra("health_care_id", concernId).putExtra("health_encounter_id", entry.id))
        }.apply { tag = "encounter-documents" }, 16)
        ui.add(content, ui.profileRow(getString(R.string.health_instruction_title)) {
            startActivity(Intent(this, HealthCareInstructionsActivity::class.java).putHealthNavigationFixture(names)
                .putExtra("health_care_id", concernId).putExtra("health_encounter_id", entry.id))
        }.apply { tag = "encounter-instructions" }, 8)
        ui.add(content, ui.profileRow(getString(R.string.health_visit_followup_title)) {
            startActivity(Intent(this, HealthCareVisitFollowUpActivity::class.java).putHealthNavigationFixture(names)
                .putExtra("health_care_id", concernId).putExtra("health_encounter_id", entry.id))
        }.apply { tag = "encounter-followup" }, 8)
        ui.add(content, ui.command(R.string.health_encounter_edit) { edit(value, entry) }.apply { tag = "encounter-edit" }, 20)
        ui.add(content, ui.profileRow(getString(R.string.health_encounter_history)) {
            history = true; historyCursor = Int.MAX_VALUE; historyPrevious.clear(); load()
        }.apply { tag = "encounter-history" }, 8)
        ui.add(content, ui.profileRow(getString(R.string.health_encounter_delete)) {
            dialog = AlertDialog.Builder(this).setTitle(R.string.health_encounter_delete).setMessage(R.string.health_encounter_delete_notice)
                .setNegativeButton(R.string.common_cancel, null).setPositiveButton(R.string.health_encounter_delete) { _, _ ->
                    clear(); reset(); work({ repository.delete(value, entry) }) { load() }
                }.show()
        }.apply { tag = "encounter-delete" }, 8)
    }
    private fun showHistory(content: LinearLayout, value: HealthCareEncounterSnapshot) {
        ui.add(content, ui.text(getString(R.string.health_encounter_history), 18f, bold = true), 16)
        value.history!!.items.forEach { entry ->
            val section = ui.column().apply { tag = "encounter-history-${entry.revision}" }
            ui.add(section, ui.text(getString(R.string.health_revision, entry.revision), 13f, muted = true), 16)
            details(section, entry); ui.add(content, section, 8)
        }
        if (historyPrevious.isNotEmpty()) ui.add(content, ui.command(R.string.health_agenda_previous) {
            historyCursor = historyPrevious.removeAt(historyPrevious.lastIndex); load()
        }.apply { tag = "encounter-history-previous" }, 12)
        value.history.next?.let { next -> ui.add(content, ui.command(R.string.health_agenda_next) {
            historyPrevious += historyCursor; historyCursor = next; load()
        }.apply { tag = "encounter-history-next" }, 12) }
    }
    private fun edit(value: HealthCareEncounterSnapshot, entry: HealthCareEncounter?) {
        val id = entry?.id ?: UUID.randomUUID().toString(); val operation = UUID.randomUUID().toString()
        editor.show(entry) { draft ->
            clear(); reset(); work({ repository.save(value, id, entry?.revision, draft, operation) }) { load() }
        }
    }
    private fun <T> work(action: () -> T, done: (T) -> Unit) {
        if (busy) return
        busy = true; dirty = false; val token = generation
        worker.execute {
            val result = runCatching(action)
            main.post {
                busy = false
                if (!active || isFinishing || isDestroyed) return@post
                // An invalidated operation cannot render either its data or its error.
                if (dirty || token != generation) { dirty = false; load(); return@post }
                result.fold(done) { error ->
                    clear(); reset()
                    val content = healthProfileContent(body)
                    val blocked = error is HealthAccessBlocked || error is HealthPrivacyConflict
                    content.addView(ui.text(getString(if (blocked) R.string.health_overview_permission else R.string.health_encounter_changed), 15f))
                    ui.add(content, if (blocked) ui.profileRow(getString(R.string.health_privacy_title)) {
                        startActivity(Intent(this, HealthPrivacyActivity::class.java).putHealthNavigationFixture(names))
                    } else ui.command(R.string.health_agenda_retry) { load() }.apply { tag = "encounter-retry" }, 12)
                }
            }
        }
    }
}

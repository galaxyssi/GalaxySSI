package com.galaxyssi.chat

import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.database.ContentObserver
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.widget.LinearLayout
import java.time.ZoneId
import java.util.UUID
import java.util.concurrent.Executors

class HealthCareVisitFollowUpActivity : Activity() {
    private val ui by lazy { HealthCenterViews(this) }
    private val names by lazy { intent.healthNavigationDatabases() }
    private val repository by lazy { HealthCareVisitFollowUpRepository(applicationContext, names) }
    private val editor by lazy { HealthCareVisitFollowUpEditor(this) }
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private lateinit var body: LinearLayout
    private var concernId = ""
    private var encounterId = ""
    private var active = false
    private var busy = false
    private var dirty = false
    private var openingAgent = false
    private var generation = 0
    private var snapshot: HealthCareVisitFollowUpSnapshot? = null
    private var dialog: AlertDialog? = null
    private var cursor = Int.MAX_VALUE
    private val previous = mutableListOf<Int>()
    private val expiry = Runnable { if (active) invalidate() }
    private val observer = object : ContentObserver(main) { override fun onChange(selfChange: Boolean) {
        // Conversation binding updates this store. The sharing preview revalidates all source revisions.
        if (active && !openingAgent) invalidate()
    } }
    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        concernId = intent.getStringExtra("health_care_id").orEmpty(); encounterId = intent.getStringExtra("health_encounter_id").orEmpty()
        if (!listOf(concernId, encounterId).all(HealthProfilePolicy::uuid)) { finish(); return }
        body = healthProfileBody(R.string.health_visit_followup_title) { finish() }
    }
    override fun onStart() {
        super.onStart(); if (!::body.isInitialized) return
        active = true
        listOf(HealthCareStore.changes(this, names.care), HealthRecordStore.changes(this, names.records),
            HealthPrivacyStore.changes(this, names.privacy), HealthProfileStore.changes(this, names.profile))
            .forEach { contentResolver.registerContentObserver(it, false, observer) }
        load()
    }
    override fun onStop() {
        if (::body.isInitialized) { active = false; clear(); reset(); contentResolver.unregisterContentObserver(observer) }
        super.onStop()
    }
    override fun onDestroy() { editor.clear(); worker.shutdown(); super.onDestroy() }
    override fun onTrimMemory(level: Int) {
        super.onTrimMemory(level)
        if (::body.isInitialized && level >= TRIM_MEMORY_RUNNING_LOW) { clear(); reset(); if (active) load() }
    }
    private fun reset() { cursor = Int.MAX_VALUE; previous.clear() }
    private fun clear() {
        generation++; openingAgent = false; snapshot = null; editor.clear(); dialog?.dismiss(); dialog = null
        main.removeCallbacks(expiry); body.removeAllViews()
    }
    private fun invalidate() { clear(); reset(); load() }
    private fun load() {
        if (!active) return
        if (busy) { dirty = true; return }
        clear(); healthProfileContent(body).addView(ui.text(getString(R.string.health_loading), 15f))
        val before = cursor
        work({ repository.load(concernId, encounterId, before) }) { snapshot = it; render(it); main.postDelayed(expiry, 600_000L) }
    }
    private fun edit(value: HealthCareVisitFollowUpSnapshot, kind: HealthCareVisitFollowUpKind) {
        if (busy) return
        val operation = UUID.randomUUID().toString()
        editor.show(kind, value.followUp) { input -> reset(); work({ repository.record(value, input, operation) }) { load() } }
    }
    private fun render(value: HealthCareVisitFollowUpSnapshot) {
        val content = healthProfileContent(body)
        content.addView(ui.text(value.visit.selected!!.details.purpose, 18f, bold = true))
        ui.add(content, ui.text(getString(R.string.health_visit_followup_notice), 14f, muted = true), 8)
        val current = value.followUp
        val attended = value.visit.selected.details.state == HealthCareEncounterState.ATTENDED
        fun command(kind: HealthCareVisitFollowUpKind) {
            val primary = kind in setOf(HealthCareVisitFollowUpKind.START, HealthCareVisitFollowUpKind.CHECK_IN)
            val action = if (primary) ui.command(kind.label()) { edit(value, kind) }
                else ui.profileRow(getString(kind.label())) { edit(value, kind) }
            ui.add(content, action.apply { tag = "visit-followup-${kind.name}" }, if (primary) 12 else 4)
        }
        if (current == null) {
            if (attended) command(HealthCareVisitFollowUpKind.START)
            else ui.add(content, ui.text(getString(R.string.health_visit_followup_attended_required), 15f), 16)
        } else {
            ui.add(content, ui.text(current.goal, 17f, bold = true), 16)
            ui.add(content, ui.text(getString(current.state.label()), 15f).apply { tag = "visit-followup-state" }, 8)
            if (current.encounterRevision != value.visit.selected.revision)
                ui.add(content, ui.text(getString(R.string.health_visit_followup_source_changed), 14f), 8)
            if (attended) when (current.state) {
                HealthCareVisitFollowUpState.ACTIVE, HealthCareVisitFollowUpState.REVIEW -> {
                    command(HealthCareVisitFollowUpKind.CHECK_IN); command(HealthCareVisitFollowUpKind.REVIEW)
                }
                HealthCareVisitFollowUpState.PAUSED -> command(HealthCareVisitFollowUpKind.RESUME)
                HealthCareVisitFollowUpState.ARCHIVED -> command(HealthCareVisitFollowUpKind.REOPEN)
            }
            if (current.state in setOf(HealthCareVisitFollowUpState.ACTIVE, HealthCareVisitFollowUpState.REVIEW)) command(HealthCareVisitFollowUpKind.PAUSE)
            if (current.state != HealthCareVisitFollowUpState.ARCHIVED) command(HealthCareVisitFollowUpKind.ARCHIVE)
            if (attended && names.fixture == null) ui.add(content, ui.profileRow(getString(R.string.health_visit_followup_agent)) {
                if (!busy) {
                    val scope = HealthCareVisitFollowUpScope.of(current, value.visit.selected)
                    openingAgent = true
                    work({ repository.discuss(value) }) { conversation ->
                        startActivity(Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                            .putExtra("galaxyssi_open_agent", true).putExtra("galaxyssi_agent_conversation_id", conversation)
                            .putExtra(HealthCareVisitFollowUpTool.INTENT_KEY, scope.json().toString()))
                    }
                }
            }.apply { tag = "visit-followup-agent" }, 12)
        }
        ui.add(content, ui.profileRow(getString(R.string.health_instruction_title)) {
            startActivity(Intent(this, HealthCareInstructionsActivity::class.java).putHealthNavigationFixture(names)
                .putExtra("health_care_id", concernId).putExtra("health_encounter_id", encounterId))
        }, 16)
        ui.add(content, ui.text(getString(R.string.health_visit_followup_history), 17f, bold = true), 20)
        if (value.history.items.isEmpty()) ui.add(content, ui.text(getString(R.string.health_visit_followup_empty), 14f, muted = true), 8)
        value.history.items.forEach { event ->
            val section = ui.column().apply { tag = "visit-followup-event-${event.value.revision}" }
            ui.add(section, ui.text(getString(event.input.kind.label()), 16f, bold = true), 16)
            ui.add(section, ui.text(encounterTime(this, event.recordedAt, ZoneId.systemDefault().id), 13f, muted = true), 4)
            val input = event.input
            fun field(label: Int, text: String) { if (text.isNotBlank()) {
                ui.add(section, ui.text(getString(label), 13f, muted = true), 8); ui.add(section, ui.text(text, 15f), 4)
            } }
            field(R.string.health_visit_followup_goal, input.goal)
            field(R.string.health_visit_followup_feelings, input.feelings)
            field(R.string.health_visit_followup_function, input.function)
            field(R.string.health_visit_followup_sleep, input.sleep)
            field(R.string.health_visit_followup_barriers, input.barriers)
            field(R.string.health_visit_followup_note, input.note)
            input.decision?.let { ui.add(section, ui.text(getString(it.label()), 14f), 8) }
            if (input.needsReview) ui.add(section, ui.text(getString(R.string.health_visit_followup_needs_review), 14f), 8)
            ui.add(content, section, 8)
        }
        if (previous.isNotEmpty()) ui.add(content, ui.command(R.string.health_agenda_previous) {
            cursor = previous.removeAt(previous.lastIndex); load()
        }.apply { tag = "visit-followup-previous" }, 12)
        value.history.next?.let { next -> ui.add(content, ui.command(R.string.health_agenda_next) {
            previous += cursor; cursor = next; load()
        }.apply { tag = "visit-followup-next" }, 12) }
        if (current != null) ui.add(content, ui.profileRow(getString(R.string.health_visit_followup_delete)) {
            dialog = AlertDialog.Builder(this).setTitle(R.string.health_visit_followup_delete).setMessage(R.string.health_visit_followup_delete_notice)
                .setNegativeButton(R.string.common_cancel, null).setPositiveButton(R.string.health_visit_followup_delete) { _, _ ->
                    reset(); work({ repository.delete(value) }) { load() }
                }.show()
        }.apply { tag = "visit-followup-delete" }, 16)
    }
    private fun <T> work(action: () -> T, done: (T) -> Unit) {
        if (busy) return
        busy = true; dirty = false; val token = generation
        worker.execute {
            val result = runCatching(action)
            main.post {
                busy = false; openingAgent = false
                if (!active || isFinishing || isDestroyed) return@post
                if (dirty || token != generation) { dirty = false; load(); return@post }
                result.fold(done) { error ->
                    clear(); reset()
                    val content = healthProfileContent(body)
                    val blocked = error is HealthAccessBlocked || error is HealthPrivacyConflict
                    content.addView(ui.text(getString(if (blocked) R.string.health_overview_permission else R.string.health_encounter_changed), 15f))
                    ui.add(content, if (blocked) ui.profileRow(getString(R.string.health_privacy_title)) {
                        startActivity(Intent(this, HealthPrivacyActivity::class.java).putHealthNavigationFixture(names))
                    } else ui.command(R.string.health_agenda_retry) { load() }, 12)
                }
            }
        }
    }
}

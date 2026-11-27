package com.galaxyssi.chat

import android.app.Activity
import android.app.AlertDialog
import android.app.DatePickerDialog
import android.app.TimePickerDialog
import android.content.Intent
import android.database.ContentObserver
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.WindowManager
import android.widget.*
import java.text.DateFormat
import java.util.Calendar
import java.util.Date
import java.util.concurrent.Executors

class HealthAgentLabActivity : Activity() {
    private val ui by lazy { HealthCenterViews(this) }
    private val names by lazy { intent.healthNavigationDatabases() }
    private val chat by lazy { intent.getStringExtra("chat").orEmpty() }
    private val mode by lazy { HealthAgentLabIntent.valueOf(intent.getStringExtra("mode") ?: "ABNORMAL") }
    private val until by lazy { intent.getLongExtra("anchor", System.currentTimeMillis()).coerceIn(1, System.currentTimeMillis()) }
    private var supplement = ""
    private val dates = mutableListOf<Long>()
    private val cutoff get() = dates.lastOrNull() ?: until
    private val worker = Executors.newSingleThreadExecutor()
    @Volatile private var generation = 0
    private var alive = false
    private lateinit var body: LinearLayout
    private var dialog: android.app.Dialog? = null
    private val observer = object : ContentObserver(Handler(Looper.getMainLooper())) {
        override fun onChange(self: Boolean) { if (alive) load() }
    }
    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        if (!HealthProfilePolicy.uuid(chat)) { finish(); return }
        supplement = intent.getStringExtra("supplement").orEmpty().take(500)
        intent.removeExtra("supplement")
        body = healthProfileBody(R.string.health_agent_title) { finish() }
    }
    override fun onStart() {
        super.onStart(); if (isFinishing) return
        alive = true
        listOf(HealthRecordStore.changes(this, names.records), HealthPrivacyStore.changes(this, names.privacy)).forEach {
            contentResolver.registerContentObserver(it, false, observer)
        }
        load()
    }
    override fun onStop() {
        if (alive) { alive = false; generation++; dialog?.dismiss(); dialog = null; body.removeAllViews(); contentResolver.unregisterContentObserver(observer) }
        super.onStop()
    }
    override fun onDestroy() { worker.shutdownNow(); super.onDestroy() }
    private fun load(once: HealthAgentLab.Once? = null) {
        val ticket = ++generation
        val anchor = cutoff
        dialog?.dismiss(); dialog = null
        healthProfileContent(body).addView(ui.text(getString(R.string.health_agent_loading)))
        worker.execute {
            val result = runCatching { HealthAgentLab.read(this, names, anchor, once) { if (generation != ticket) throw InterruptedException() } }
            val blockedVersion = if (result.exceptionOrNull() is HealthAccessBlocked) runCatching {
                HealthPrivacyStore(this, names.privacy).use { it.policy().version }
            }.getOrNull() else null
            runOnUiThread { if (alive && generation == ticket) result.fold(::show) { e ->
                val box = healthProfileContent(body)
                val blocked = e is HealthAccessBlocked
                box.addView(ui.text(getString(if (blocked) R.string.health_agent_blocked else R.string.health_storage_error)))
                if (blockedVersion != null) box.addView(ui.command(R.string.health_agent_once) {
                    load(HealthAgentLab.Once(blockedVersion, anchor))
                })
                if (blocked) box.addView(ui.command(R.string.health_agent_privacy) {
                    startActivity(Intent(this, HealthPrivacyActivity::class.java).putHealthNavigationFixture(names))
                }) else box.addView(ui.command(R.string.health_agenda_retry) { load() })
            } }
        }
    }
    private fun title(row: HealthObservation) = getString(row.draft.metric.titleResource())
    private fun show(s: HealthAgentLab.Snapshot) {
        val box = healthProfileContent(body)
        if (s.day == null) {
            box.addView(ui.text(getString(R.string.health_agent_empty)).apply { tag = "local-lab-empty" }); return
        }
        ui.add(box, ui.text(getString(if (s.imported) R.string.health_agent_report_day else R.string.health_agent_manual_day, s.day), 14f, true))
        ui.add(box, ui.text(getString(R.string.health_agent_counts, s.rows.size, s.abnormal.size, s.unknown), 18f, bold = true)
            .apply { tag = "local-lab-summary" }, 12)
        if (s.olderUntil != null || dates.isNotEmpty()) ui.add(box, LinearLayout(this).apply {
            s.olderUntil?.let { before -> addView(ui.command(R.string.health_agent_older) { dates.add(before); load() }) }
            if (dates.isNotEmpty()) addView(ui.command(R.string.health_agent_newer) { dates.removeAt(dates.lastIndex); load() })
        }, 8)
        val follow = mode in setOf(HealthAgentLabIntent.NOTE, HealthAgentLabIntent.REMIND)
        if (follow) ui.add(box, ui.text(getString(R.string.health_agent_choose), 14f, true), 12)
        val rows = if (mode == HealthAgentLabIntent.ABNORMAL) s.abnormal else s.rows
        if (rows.isEmpty()) ui.add(box, ui.text(getString(R.string.health_agent_no_flag)), 16)
        rows.forEach { row ->
            val range = HealthOverviewRangePolicy.report(row)
            val direction = when (range?.position) {
                HealthOverviewRangePosition.ABOVE -> R.string.health_agent_high
                HealthOverviewRangePosition.BELOW -> R.string.health_agent_low
                HealthOverviewRangePosition.WITHIN -> R.string.health_agent_within
                else -> R.string.health_agent_unknown
            }
            val ref = row.draft.reference.ifBlank { getString(R.string.health_agent_unknown) }
            val subtitle = getString(R.string.health_agent_range, getString(direction), ref)
            ui.add(box, ui.profileRow("${title(row)}   ${healthDisplayValue(row.draft)}", subtitle) {
                when (mode) {
                    HealthAgentLabIntent.NOTE -> note(row, s)
                    HealthAgentLabIntent.REMIND -> pickTime(row, s)
                    else -> actions(row, s)
                }
            }.apply { tag = "local-lab-record"; isEnabled = s.privacy.metrics }, 8)
        }
    }
    private fun actions(row: HealthObservation, s: HealthAgentLab.Snapshot) {
        dialog = AlertDialog.Builder(this).setTitle(title(row)).setItems(arrayOf(getString(R.string.health_agent_source),
            getString(R.string.health_agent_note), getString(R.string.health_agent_remind))) { _, n -> when (n) {
            0 -> startActivity(Intent(this, HealthRecordRevisionActivity::class.java).putHealthNavigationFixture(names)
                .putExtra("health_record", row.id).putExtra("health_revision", row.revision))
            1 -> note(row, s)
            else -> pickTime(row, s)
        } }.setNegativeButton(android.R.string.cancel, null).show()
    }
    private fun note(row: HealthObservation, s: HealthAgentLab.Snapshot) {
        val input = healthProfileInput(supplement, 500, true)
        val panel = ui.column().apply { setPadding(ui.dp(20), 0, ui.dp(20), 0); addView(input) }
        val values = listOf(null) + healthGlucoseConditions
        val select = Spinner(this).apply {
            adapter = ArrayAdapter(this@HealthAgentLabActivity, android.R.layout.simple_spinner_dropdown_item,
                values.map { if (it == null) getString(R.string.health_agent_keep_condition) else getString(healthContextResource(it)) })
            setSelection(values.indexOf(HealthAgentLab.suggestedCondition(supplement)).coerceAtLeast(0))
        }
        panel.addView(select)
        dialog = AlertDialog.Builder(this).setTitle(getString(R.string.health_agent_note_for, title(row)))
            .setView(ScrollView(this).apply { addView(panel) }).setNegativeButton(android.R.string.cancel, null)
            .setPositiveButton(R.string.common_save, null).create().also { d -> d.setOnShowListener {
                d.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener {
                    val condition = values[select.selectedItemPosition]
                    val text = input.text.toString().trim().ifEmpty { condition?.let { getString(healthContextResource(it)) }.orEmpty() }
                    if (text.isBlank()) { input.error = getString(R.string.health_agent_note); return@setOnClickListener }
                    d.dismiss()
                    commit(R.string.health_agent_note_saved) { HealthAgentLab.annotate(this, names, row, s.privacy, text, condition) }
                }
            }; d.show() }
    }
    private fun pickTime(row: HealthObservation, s: HealthAgentLab.Snapshot) {
        val c = Calendar.getInstance()
        HealthAgentLab.suggestedDay(supplement, java.time.LocalDate.now())?.let { c.set(it.year, it.monthValue - 1, it.dayOfMonth) }
        dialog = DatePickerDialog(this, { _, y, m, d ->
            c.set(y, m, d)
            dialog = TimePickerDialog(this, { _, hour, minute ->
                c.set(Calendar.HOUR_OF_DAY, hour); c.set(Calendar.MINUTE, minute); c.set(Calendar.SECOND, 0); c.set(Calendar.MILLISECOND, 0)
                val at = c.timeInMillis
                if (at <= System.currentTimeMillis()) { Toast.makeText(this, R.string.health_care_followup_future_time, Toast.LENGTH_LONG).show(); return@TimePickerDialog }
                dialog = AlertDialog.Builder(this).setTitle(R.string.health_agent_remind)
                    .setMessage(getString(R.string.health_agent_confirm, title(row), DateFormat.getDateTimeInstance().format(Date(at))))
                    .setNegativeButton(android.R.string.cancel, null).setPositiveButton(android.R.string.ok) { _, _ ->
                        commit(R.string.health_agent_reminder_saved, R.string.health_agent_not_tracked) { HealthAgentLab.schedule(this, names, row, s.privacy, chat, at) }
                    }.show()
            }, c.get(Calendar.HOUR_OF_DAY), c.get(Calendar.MINUTE), android.text.format.DateFormat.is24HourFormat(this)).also { it.show() }
        }, c.get(Calendar.YEAR), c.get(Calendar.MONTH), c.get(Calendar.DAY_OF_MONTH)).also { it.datePicker.minDate = System.currentTimeMillis(); it.show() }
    }
    private fun commit(success: Int, failure: Int = R.string.health_agent_changed, action: () -> Unit) {
        worker.execute {
            val ok = runCatching(action).isSuccess
            runOnUiThread { if (alive) {
                if (ok) supplement = ""
                Toast.makeText(this, if (ok) success else failure, Toast.LENGTH_LONG).show(); load()
            } }
        }
    }
}

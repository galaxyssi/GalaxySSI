package com.galaxyssi.chat

import android.app.Activity
import android.app.AlertDialog
import android.app.DatePickerDialog
import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.text.Editable
import android.text.TextWatcher
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.Toast
import java.time.LocalDate
import java.util.concurrent.Executors

class HealthProfileActivity : Activity() {
    private val ui by lazy { HealthCenterViews(this) }; private val worker = Executors.newSingleThreadExecutor(); private val main = Handler(Looper.getMainLooper())
    private val databaseName by lazy { healthProfileDatabaseName() }; private val store by lazy { HealthProfileStore(applicationContext, databaseName) }; private lateinit var body: LinearLayout
    private var active = false; private var generation = 0; private var querying = false; private var dirty = false; private var mutating = false
    private var state: HealthProfileSnapshot? = null; private var dialog: AlertDialog? = null; private var datePicker: DatePickerDialog? = null
    private var pending: (() -> HealthProfileDraft)? = null
    private var editChanged = false
    private val persistPending = Runnable { persistEdit() }
    private val observer = object : android.database.ContentObserver(main) { override fun onChange(selfChange: Boolean) { generation++; load() } }
    override fun onCreate(savedInstanceState: Bundle?) { super.onCreate(savedInstanceState); body = healthProfileBody(R.string.health_profile_title) { finish() } }
    override fun onStart() { super.onStart(); active = true; contentResolver.registerContentObserver(HealthProfileStore.changes(this, databaseName), false, observer); load() }
    override fun onStop() {
        if (!mutating) persistEdit(); active = false; generation++; main.removeCallbacks(persistPending); pending = null
        dialog?.dismiss(); dialog = null; datePicker?.dismiss(); datePicker = null; state = null; body.removeAllViews(); contentResolver.unregisterContentObserver(observer); super.onStop()
    }
    override fun onDestroy() { worker.execute { store.close() }; worker.shutdown(); super.onDestroy() }
    private fun load() {
        if (!active) return
        if (querying || mutating) { dirty = true; return }; querying = true; dirty = false; val token = generation
        worker.execute {
            val result = runCatching { store.snapshot() }
            main.post { querying = false
                if (active && token == generation) result.fold({ value ->
                    if (state?.generation?.let { it != value.generation } == true) {
                        pending = null; editChanged = false; main.removeCallbacks(persistPending); dialog?.dismiss(); dialog = null; datePicker?.dismiss(); datePicker = null
                    }
                    state = value; render(value)
                }, { failure -> error(failure) })
                if (active && (dirty || token != generation)) { dirty = false; load() }
            }
        }
    }
    private fun render(s: HealthProfileSnapshot) {
        val content = healthProfileContent(body)
        val name = healthProfileDisplay(HealthProfileField.NAME, s.draft?.changes?.get(HealthProfileField.NAME) ?: s.cells.getValue(HealthProfileField.NAME).value).let {
            if (it == getString(R.string.health_profile_missing)) getString(R.string.health_profile_self) else it
        }
        content.addView(ui.line().apply {
            addView(android.widget.ImageView(this@HealthProfileActivity).apply {
                setImageResource(R.drawable.ic_health_heart); imageTintList = android.content.res.ColorStateList.valueOf(0xff15975e.toInt())
                setPadding(ui.dp(12), ui.dp(12), ui.dp(12), ui.dp(12)); background = ui.background(0xffe8f6ee.toInt(), radius = 24)
            }, LinearLayout.LayoutParams(ui.dp(48), ui.dp(48)).apply { marginEnd = ui.dp(12) })
            addView(ui.column().apply {
                addView(ui.text(name, 23f, bold = true).apply { tag = "health-profile-name"; maxLines = 2; ellipsize = android.text.TextUtils.TruncateAt.END })
                ui.add(this, ui.text(getString(R.string.health_profile_source), 13f, muted = true), 6)
            }, LinearLayout.LayoutParams(0, -2, 1f))
            addView(ui.icon(R.drawable.ic_hub_compose, R.string.common_edit) { if (!mutating) edit(HealthProfileField.NAME, s) })
        })
        ui.add(content, ui.text(getString(R.string.health_profile_basics), 18f, bold = true), 24)
        HealthProfileField.entries.forEach { field ->
            val value = s.draft?.changes?.get(field) ?: s.cells.getValue(field).value
            ui.add(content, ui.profileRow(getString(field.titleResource()), healthProfileDisplay(field, value)) { if (!mutating) edit(field, s) }.apply { tag = "health-profile-field-${field.name}" })
        }
        if (s.draft != null) {
            ui.add(content, ui.text(getString(R.string.health_profile_unsaved), 13f, muted = true).apply { tag = "health-profile-unsaved" }, 10)
            if (s.draft.generation != s.generation || s.draft.expected.any { (field, token) -> s.cells.getValue(field).token != token })
                ui.add(content, ui.text(getString(R.string.health_profile_conflict), 14f), 8)
        }
        ui.add(content, ui.command(R.string.health_profile_save) { s.draft?.let { draft -> mutate { store.saveBasics(draft) } } }.apply {
            isEnabled = s.draft != null && !mutating; alpha = if (isEnabled) 1f else .45f; tag = "health-profile-save"
        }, 16)
        if (s.draft != null) ui.add(content, ui.profileRow(getString(R.string.health_profile_discard)) { mutate { store.discardBasic(s.generation) } }, 8)
        ui.add(content, ui.text(getString(R.string.health_profile_background), 18f, bold = true), 24)
        HealthBackgroundKind.entries.forEach { kind -> ui.add(content, ui.profileRow(getString(kind.titleResource()),
            getString(R.string.health_profile_entry_count, s.counts.getValue(kind))) { startActivity(Intent(this, HealthBackgroundActivity::class.java).putExtra("health_background", kind.name).putExtra("health_profile_test_db", databaseName)) }.apply { tag = "health-background-${kind.name}" }) }
        ui.add(content, ui.text(getString(R.string.health_profile_missing_notice), 13f, muted = true), 20)
        ui.add(content, ui.profileRow(getString(R.string.health_profile_delete)) { delete() }.apply { tag = "health-profile-delete" }, 16)
    }
    private fun edit(field: HealthProfileField, s: HealthProfileSnapshot) {
        if (field == HealthProfileField.REFERENCE_SEX) {
            val options = listOf<HealthReferenceSex?>(null) + HealthReferenceSex.entries
            dialog = AlertDialog.Builder(this).setTitle(field.titleResource()).setItems(options.map { value -> healthProfileDisplay(field, value?.let { HealthProfileInput(it.name) }) }.toTypedArray()) { _, which ->
                stage(s, field, HealthProfileInput(options[which]?.name.orEmpty()))
            }.setNegativeButton(R.string.common_cancel, null).show(); return
        }
        val base = s.draft ?: HealthProfileDraft(s.generation, emptyMap(), emptyMap())
        editChanged = false
        val initial = base.changes[field] ?: s.cells.getValue(field).value ?: HealthProfileInput(unit = if (field == HealthProfileField.HEIGHT) "cm" else "")
        val input = healthProfileInput(initial.text, when (field) { HealthProfileField.NAME -> 80; HealthProfileField.PHYSIOLOGICAL_CONTEXT -> 1000; else -> 20 }, field == HealthProfileField.PHYSIOLOGICAL_CONTEXT)
        input.tag = "health-profile-editor"; if (field == HealthProfileField.BIRTH_DATE) input.hint = "YYYY-MM-DD"
        if (field == HealthProfileField.HEIGHT) input.inputType = android.text.InputType.TYPE_CLASS_NUMBER or android.text.InputType.TYPE_NUMBER_FLAG_DECIMAL
        var unit = initial.unit; val content = ui.column().apply { setPadding(ui.dp(20), 0, ui.dp(20), 0); addView(input) }
        if (field == HealthProfileField.HEIGHT) content.addView(android.widget.RadioGroup(this).apply {
            orientation = LinearLayout.HORIZONTAL
            listOf("cm", "in").forEach { value -> addView(android.widget.RadioButton(this@HealthProfileActivity).apply {
                id = android.view.View.generateViewId(); text = value; isChecked = unit == value; setOnClickListener { unit = value; editChanged = true; main.removeCallbacks(persistPending); main.postDelayed(persistPending, 350) }
            }, android.widget.RadioGroup.LayoutParams(0, -2, 1f)) }
        })
        if (field == HealthProfileField.BIRTH_DATE) content.addView(ui.icon(android.R.drawable.ic_menu_my_calendar, R.string.health_profile_choose_date) {
            val date = runCatching { LocalDate.parse(input.text.toString()) }.getOrDefault(LocalDate.now())
            datePicker = DatePickerDialog(this, { _, y, m, d -> input.setText(LocalDate.of(y, m + 1, d).toString()) }, date.year, date.monthValue - 1, date.dayOfMonth).apply { datePicker.maxDate = System.currentTimeMillis(); show() }
        })
        pending = { HealthProfileDraft(base.generation, mapOf(field to HealthProfileInput(input.text.toString(), unit)), mapOf(field to (base.expected[field] ?: s.cells.getValue(field).token))) }
        input.addTextChangedListener(object : TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
            override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) { editChanged = true; main.removeCallbacks(persistPending); main.postDelayed(persistPending, 350) }
            override fun afterTextChanged(s: Editable?) {}
        })
        fun cancel() { main.removeCallbacks(persistPending); val observed = pending?.invoke()?.changes?.get(field); pending = null; worker.execute {
            val result = runCatching { store.restoreBasicField(field, s.draft, s.generation, observed) }; main.post { if (active) { result.exceptionOrNull()?.let(::error); load() } }
        } }
        dialog = AlertDialog.Builder(this).setTitle(field.titleResource()).setView(content).setPositiveButton(android.R.string.ok) { _, _ -> persistEdit(); pending = null }
            .setNegativeButton(R.string.common_cancel) { _, _ -> cancel() }.setOnCancelListener { cancel() }.show()
    }
    private fun stage(s: HealthProfileSnapshot, field: HealthProfileField, value: HealthProfileInput) {
        val draft = s.draft ?: HealthProfileDraft(s.generation, emptyMap(), emptyMap())
        val next = HealthProfileDraft(draft.generation, mapOf(field to value), mapOf(field to (draft.expected[field] ?: s.cells.getValue(field).token)))
        mutate { store.draft(next) }
    }
    private fun persistEdit() {
        main.removeCallbacks(persistPending); if (!editChanged) return; val draft = pending?.invoke() ?: return
        worker.execute { val result = runCatching { store.draft(draft) }; main.post { if (active) { result.exceptionOrNull()?.let(::error); load() } } }
    }
    private fun mutate(action: () -> Any) {
        if (mutating) return; mutating = true
        worker.execute { val result = runCatching(action); main.post { mutating = false; if (active) { result.exceptionOrNull()?.let(::error); load() } } }
    }
    private fun delete() {
        worker.execute { val result = runCatching { store.deletePreview() }; main.post { if (active) result.fold({ preview ->
            dialog = AlertDialog.Builder(this).setTitle(R.string.health_profile_delete).setMessage(getString(R.string.health_profile_delete_preview, preview.fields, preview.entries, preview.drafts))
                .setNegativeButton(R.string.common_cancel, null).setPositiveButton(R.string.common_delete) { _, _ -> pending = null; mutate {
                    HealthPrivacyStore.track(applicationContext, HealthAccessScope.deleteProfile(preview), healthPrivacyDatabaseName()) { store.clear(preview) }
                } }.show()
        }, ::error) } }
    }
    private fun error(failure: Throwable) { Toast.makeText(this, healthProfileError(failure), Toast.LENGTH_LONG).show()
        if (body.childCount == 0) { val content = healthProfileContent(body); content.addView(ui.text(healthProfileError(failure))); ui.add(content, ui.command(R.string.common_retry) { load() }, 16) }
    }
}

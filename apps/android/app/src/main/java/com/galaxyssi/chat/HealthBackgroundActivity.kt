package com.galaxyssi.chat

import android.app.Activity
import android.app.AlertDialog
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.text.Editable
import android.text.TextWatcher
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.Toast
import java.util.concurrent.Executors

class HealthBackgroundActivity : Activity() {
    private val ui by lazy { HealthCenterViews(this) }; private val worker = Executors.newSingleThreadExecutor(); private val main = Handler(Looper.getMainLooper())
    private val databaseName by lazy { healthProfileDatabaseName() }; private val store by lazy { HealthProfileStore(applicationContext, databaseName) }; private lateinit var body: LinearLayout
    private var kind = HealthBackgroundKind.HISTORY; private var route = "list"; private var key = ""
    private var cursor: HealthBackgroundCursor? = null; private val previous = arrayListOf<HealthBackgroundCursor?>()
    private var active = false; private var generation = 0; private var querying = false; private var dirty = false; private var mutating = false
    private var draft: HealthBackgroundDraft? = null; private var dialog: AlertDialog? = null; private val inputs = linkedMapOf<String, EditText>()
    private val persistPending = Runnable { persist() }
    private val observer = object : android.database.ContentObserver(main) { override fun onChange(selfChange: Boolean) {
        if (route == "list") load() else {
            val value = draft
            if (value == null) { generation++; load(); return }
            val token = generation
            worker.execute { val current = runCatching { store.currentGeneration() }; main.post {
                if (active && token == generation && current.getOrNull()?.let { it != value.generation } == true) {
                    main.removeCallbacks(persistPending); draft = null; inputs.clear(); route = "list"; cursor = null; previous.clear(); generation++; body.removeAllViews(); load()
                }
            } }
        }
    } }
    override fun onCreate(state: Bundle?) {
        super.onCreate(state); kind = HealthBackgroundKind.valueOf(state?.getString("kind") ?: intent.getStringExtra("health_background") ?: "HISTORY")
        route = state?.getString("route") ?: "list"; key = state?.getString("draft").orEmpty()
        fun cursor(raw: String?): HealthBackgroundCursor? = raw?.takeIf(String::isNotEmpty)?.split('|', limit = 3)?.let { HealthBackgroundCursor(kind, it[0].toLong(), it[1], it[2]) }
        cursor = cursor(state?.getString("cursor")); previous.addAll(state?.getStringArrayList("previous")?.map(::cursor).orEmpty())
        body = healthProfileBody(kind.titleResource()) { back() }
    }
    override fun onStart() { super.onStart(); active = true; contentResolver.registerContentObserver(HealthProfileStore.changes(this, databaseName), false, observer); load() }
    override fun onStop() {
        if (!mutating) persist(); active = false; generation++; main.removeCallbacks(persistPending); inputs.clear(); draft = null
        dialog?.dismiss(); dialog = null; body.removeAllViews(); contentResolver.unregisterContentObserver(observer); super.onStop()
    }
    override fun onDestroy() { worker.execute { store.close() }; worker.shutdown(); super.onDestroy() }
    override fun onSaveInstanceState(out: Bundle) {
        if (!mutating) persist()
        fun cursor(value: HealthBackgroundCursor?) = value?.let { "${it.updatedAt}|${it.id}|${it.version}" }.orEmpty()
        out.putString("kind", kind.name); out.putString("route", route); out.putString("draft", key); out.putString("cursor", cursor(cursor))
        out.putStringArrayList("previous", ArrayList(previous.map(::cursor))); super.onSaveInstanceState(out)
    }
    @Deprecated("Native back callback") override fun onBackPressed() = back()
    private fun back() {
        if (mutating) return
        if (route == "edit") { persist(); main.removeCallbacks(persistPending); route = "list"; inputs.clear(); draft = null; generation++; load() } else finish()
    }
    private fun load() {
        if (!active) return
        if (querying || mutating) { dirty = true; return }; querying = true; dirty = false
        val token = generation; val selectedRoute = route; val selectedKey = key; val after = cursor
        worker.execute {
            val result = runCatching {
                if (selectedRoute == "list") Page(page = store.page(kind, after)) else Page(draft = if (selectedKey.startsWith("new:")) store.newEntry(kind) else store.editEntry(selectedKey.removePrefix("edit:")))
            }
            main.post { querying = false
                if (active && token == generation && selectedRoute == route) result.fold({ value -> if (selectedRoute == "list") listing(requireNotNull(value.page)) else editor(requireNotNull(value.draft)) }, { error(it) })
                if (active && (dirty || token != generation)) { dirty = false; load() }
            }
        }
    }
    private fun listing(page: HealthBackgroundPage) {
        val content = healthProfileContent(body)
        content.addView(ui.text(getString(R.string.health_profile_source), 13f, muted = true))
        ui.add(content, ui.command(R.string.health_profile_add_entry) { key = "new:${kind.name}"; route = "edit"; generation++; load() }.apply { tag = "health-background-add" }, 16)
        if (page.entries.isEmpty()) ui.add(content, ui.text(getString(R.string.health_profile_no_entries), 15f, muted = true).apply { tag = "health-background-empty" }, 24)
        page.entries.forEach { entry -> ui.add(content, ui.profileRow(entry.name, listOf(entry.dose, entry.timing, entry.detail).filter(String::isNotBlank).joinToString(" \u00b7 ")) {
            key = "edit:${entry.id}"; route = "edit"; generation++; load()
        }, 8) }
        if (previous.isNotEmpty()) ui.add(content, ui.command(R.string.health_previous_page) { cursor = previous.removeAt(previous.lastIndex); load() }, 16)
        page.next?.let { next -> ui.add(content, ui.command(R.string.health_next_page) { previous += cursor; cursor = next; load() }, 16) }
        ui.add(content, ui.text(getString(R.string.health_profile_missing_notice), 13f, muted = true), 24)
    }
    private fun editor(value: HealthBackgroundDraft) {
        draft = value; inputs.clear(); val content = healthProfileContent(body)
        content.addView(ui.text(getString(R.string.health_profile_source), 13f, muted = true))
        fun input(name: String, label: Int, text: String, max: Int, multiline: Boolean = false) {
            ui.add(content, ui.text(getString(label), 13f, muted = true), 18)
            val view = healthProfileInput(text, max, multiline).apply { tag = "health-background-$name" }; inputs[name] = view; ui.add(content, view, 4)
            view.addTextChangedListener(object : TextWatcher {
                override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
                override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) { main.removeCallbacks(persistPending); main.postDelayed(persistPending, 350) }
                override fun afterTextChanged(s: Editable?) {}
            })
        }
        input("name", R.string.health_profile_entry_name, value.entry.name, 160)
        if (kind == HealthBackgroundKind.MEDICATION) {
            input("dose", R.string.health_profile_dose, value.entry.dose, 200)
            input("timing", R.string.health_profile_timing, value.entry.timing, 300)
            ui.add(content, ui.text(getString(R.string.health_profile_medication_notice), 13f, muted = true), 12)
        }
        input("detail", if (kind == HealthBackgroundKind.ALLERGY) R.string.health_profile_reaction else R.string.health_note, value.entry.detail, 4000, true)
        ui.add(content, ui.command(R.string.health_profile_save_entry) { capture()?.let { next -> mutate {
            store.draft(next); store.saveEntry(next)
        } } }.apply { tag = "health-background-save" }, 24)
        ui.add(content, ui.profileRow(getString(R.string.health_profile_discard)) { capture()?.let { next -> mutate { store.discardEntry(next) } } }, 12)
        if (value.expected.isNotEmpty()) ui.add(content, ui.profileRow(getString(R.string.common_delete)) {
            dialog = AlertDialog.Builder(this).setTitle(R.string.common_delete).setMessage(R.string.health_profile_delete_entry)
                .setNegativeButton(R.string.common_cancel, null).setPositiveButton(R.string.common_delete) { _, _ -> mutate { store.deleteEntry(value.entry.id, value.expected, value.generation) } }.show()
        }, 16)
    }
    private fun capture(): HealthBackgroundDraft? = draft?.takeIf { inputs.isNotEmpty() }?.let { value -> value.copy(entry = value.entry.copy(
        name = inputs["name"]?.text?.toString().orEmpty(), detail = inputs["detail"]?.text?.toString().orEmpty(),
        dose = inputs["dose"]?.text?.toString().orEmpty(), timing = inputs["timing"]?.text?.toString().orEmpty())) }
    private fun persist() {
        main.removeCallbacks(persistPending); val next = capture() ?: return
        worker.execute { val result = runCatching { store.draft(next) }; main.post { if (active) result.exceptionOrNull()?.let(::error) } }
    }
    private fun mutate(action: () -> Any) {
        if (mutating) return; main.removeCallbacks(persistPending); mutating = true; inputs.values.forEach { it.isEnabled = false }
        worker.execute { val result = runCatching(action); main.post { mutating = false
            if (result.isSuccess) { route = "list"; draft = null; inputs.clear(); cursor = null; previous.clear(); generation++; if (active) load() }
            else if (active) { inputs.values.forEach { it.isEnabled = true }; error(requireNotNull(result.exceptionOrNull())) }
        } }
    }
    private fun error(failure: Throwable) {
        Toast.makeText(this, healthProfileError(failure), Toast.LENGTH_LONG).show()
        if (route == "list" || body.childCount == 0) {
            val content = healthProfileContent(body); content.addView(ui.text(healthProfileError(failure)))
            ui.add(content, ui.command(R.string.common_retry) { cursor = null; previous.clear(); load() }, 16)
        }
    }
    private data class Page(val page: HealthBackgroundPage? = null, val draft: HealthBackgroundDraft? = null)
}

package com.galaxyssi.chat

import android.app.Activity
import android.app.AlertDialog
import android.app.TimePickerDialog
import android.content.Intent
import android.database.ContentObserver
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.View
import android.widget.LinearLayout
import android.widget.Switch
import android.widget.TextView
import android.widget.Toast
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.concurrent.Executors

class HealthReminderActivity : Activity() {
    private val ui by lazy { HealthCenterViews(this) }
    private val main = Handler(Looper.getMainLooper())
    private val io = Executors.newSingleThreadExecutor()
    private val database by lazy {
        val name = intent.getStringExtra("health_reminder_test_db").orEmpty()
        if (BuildConfig.DEBUG && name.startsWith("health-reminder-test-") && name.endsWith(".db") &&
            HealthProfilePolicy.uuid(name.removePrefix("health-reminder-test-").removeSuffix(".db"))) name else HealthReminderStore.DEFAULT_DB
    }
    private val live get() = database == HealthReminderStore.DEFAULT_DB
    private val store by lazy { HealthReminderStore(applicationContext, database) }
    private lateinit var body: LinearLayout
    private lateinit var title: TextView
    private var active = false
    private var generation = 0
    private var busy = false
    private var settingsOpen = false
    private var draft: HealthReminderSettings? = null
    private var detail: LocalDate? = null
    private var filter = HealthReminderFilter.PENDING
    private var after: LocalDate? = null
    private val previous = arrayListOf<LocalDate?>()
    private var dialog: AlertDialog? = null
    private val observer = object : ContentObserver(main) {
        override fun onChange(selfChange: Boolean) { if (!busy && !settingsOpen) load() }
    }
    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        settingsOpen = state?.getBoolean("settings") ?: false
        detail = parse(if (state == null) intent.getStringExtra("health_reminder_day") else state.getString("day"))
        filter = state?.getString("filter")?.let(HealthReminderFilter::valueOf) ?: filter
        after = parse(state?.getString("after")); previous.addAll(state?.getStringArrayList("previous")?.map(::parse).orEmpty())
        body = healthProfileBody(R.string.health_reminder_title) { back() }
        val header = (body.parent as LinearLayout).getChildAt(0) as LinearLayout
        title = header.getChildAt(1) as TextView
    }
    private fun parse(value: String?) = value?.takeIf(String::isNotBlank)?.let { runCatching { LocalDate.parse(it) }.getOrNull() }
    override fun onSaveInstanceState(out: Bundle) {
        out.putBoolean("settings", settingsOpen); out.putString("day", detail?.toString()); out.putString("filter", filter.name)
        out.putString("after", after?.toString()); out.putStringArrayList("previous", ArrayList(previous.map { it?.toString().orEmpty() }))
        super.onSaveInstanceState(out)
    }
    override fun onStart() {
        super.onStart(); active = true
        contentResolver.registerContentObserver(HealthReminderStore.changes(this, database), false, observer)
        load(refresh = true)
    }
    override fun onStop() {
        active = false; generation++; contentResolver.unregisterContentObserver(observer)
        dialog?.dismiss(); dialog = null; body.removeAllViews(); super.onStop()
    }
    override fun onDestroy() { io.execute { store.close() }; io.shutdown(); super.onDestroy() }
    @Deprecated("Native back callback") override fun onBackPressed() = back()
    private fun back() {
        if (busy) return
        when {
            settingsOpen -> { settingsOpen = false; draft = null; load() }
            detail != null -> { detail = null; load() }
            else -> finish()
        }
    }
    private fun load(refresh: Boolean = false) {
        if (!active) return
        val token = ++generation; val day = detail; val cursor = after; val selected = filter
        val preferences = settingsOpen
        title.setText(when { preferences -> R.string.health_reminder_preferences; day != null -> R.string.health_reminder_detail; else -> R.string.health_reminder_title })
        io.execute {
            val result = runCatching {
                if (refresh) HealthReminderWork.refresh(applicationContext, store, live)
                Snapshot(store.settings(), if (!preferences && day == null) store.page(selected, cursor) else null, day?.let(store::occurrence))
            }
            main.post {
                if (!active || token != generation) return@post
                result.fold({ snapshot ->
                    if (preferences) { if (draft == null) draft = snapshot.settings; renderPreferences() }
                    else if (day != null) renderDetail(snapshot.event)
                    else renderCenter(snapshot.settings, requireNotNull(snapshot.page))
                }, { renderError() })
            }
        }
    }
    private data class Snapshot(val settings: HealthReminderSettings, val page: HealthReminderPage?, val event: HealthReminderOccurrence?)

    private fun button(label: Int, tag: String, primary: Boolean = false, action: () -> Unit) = ui.command(label, action).apply {
        this.tag = tag
        if (!primary) {
            background = ui.background(stroke = getColor(R.color.separator), radius = 8)
            setTextColor(getColor(R.color.text_primary))
        }
        setPadding(ui.dp(8), ui.dp(8), ui.dp(8), ui.dp(8))
    }
    private fun renderCenter(settings: HealthReminderSettings, page: HealthReminderPage) {
        val content = healthProfileContent(body)
        content.addView(ui.line().apply {
            HealthReminderFilter.entries.forEach { item ->
                val segment = ui.text(getString(item.titleResource()), 14f, bold = item == filter).apply {
                    tag = "health-reminder-filter-${item.name}"; gravity = Gravity.CENTER; minimumHeight = ui.dp(48)
                    isSelected = item == filter; isFocusable = true; setPadding(ui.dp(4), 0, ui.dp(4), 0)
                    background = ui.background(if (item == filter) getColor(R.color.surface_bg) else getColor(R.color.page_bg),
                        if (item == filter) getColor(R.color.separator) else null, radius = 8)
                    setOnClickListener { filter = item; after = null; previous.clear(); load() }
                }
                addView(segment, LinearLayout.LayoutParams(0, -2, 1f))
            }
        })
        ui.add(content, ui.text(getString(R.string.health_reminder_record_group), 18f, bold = true), 20)
        if (page.rows.isEmpty()) ui.add(content, ui.text(getString(R.string.health_reminder_empty), 15f, muted = true), 16)
        page.rows.forEach { event ->
            ui.add(content, ui.profileRow(getString(event.target.titleResource()),
                "${format(event.dueAt, event.zone)} \u00b7 ${getString(event.state.titleResource())}") {
                detail = event.day; load()
            }.apply { tag = "health-reminder-event" }, 4)
        }
        if (previous.isNotEmpty()) ui.add(content, button(R.string.health_previous_page, "health-reminder-previous") {
            after = previous.removeAt(previous.lastIndex); load()
        }, 8)
        page.next?.let { next -> ui.add(content, button(R.string.health_next_page, "health-reminder-next") { previous += after; after = next; load() }, 8) }
        val next = HealthReminderPolicy.nextDaily(settings, System.currentTimeMillis(), ZoneId.systemDefault())
        ui.add(content, ui.text(if (next == null) getString(R.string.health_reminder_plan_off)
            else getString(R.string.health_reminder_next_due, format(next, ZoneId.systemDefault().id)), 14f, muted = true), 20)
        ui.add(content, button(R.string.health_reminder_preferences, "health-reminder-settings") { settingsOpen = true; load() }, 12)
    }
    private fun renderDetail(event: HealthReminderOccurrence?) {
        val content = healthProfileContent(body)
        if (event == null) { content.addView(ui.text(getString(R.string.health_reminder_empty))); return }
        content.addView(ui.text(getString(event.target.titleResource()), 22f, bold = true))
        ui.add(content, ui.text(getString(R.string.health_reminder_due, format(event.dueAt, event.zone)), 15f, muted = true), 12)
        ui.add(content, ui.text(getString(event.state.titleResource()), 15f).apply { tag = "health-reminder-state-${event.state.name}" }, 8)
        ui.add(content, ui.text(getString(event.delivery.titleResource()), 14f, muted = true), 6)
        if (event.state == HealthReminderState.SNOOZED) ui.add(content, ui.text(getString(R.string.health_reminder_snoozed_until,
            format(event.resumeAt, ZoneId.systemDefault().id)), 14f, muted = true), 6)
        if (event.state == HealthReminderState.PENDING || event.state == HealthReminderState.SNOOZED) {
            ui.add(content, button(R.string.health_reminder_open_record, "health-reminder-open-record") {
                startActivity(Intent(this, HealthCenterActivity::class.java).putExtra("health_manual", true).apply {
                    if (event.target == HealthReminderTarget.SLEEP) putExtra("health_metric", HealthMetric.SLEEP_DURATION.name)
                })
            }, 16)
            ui.add(content, button(R.string.health_reminder_complete, "health-reminder-complete", true) { act(event, HealthReminderAction.COMPLETE) }, 12)
            ui.add(content, button(R.string.health_reminder_snooze, "health-reminder-snooze") { act(event, HealthReminderAction.SNOOZE) }, 8)
            ui.add(content, button(R.string.health_reminder_disable, "health-reminder-disable") {
                show(AlertDialog.Builder(this).setMessage(R.string.health_reminder_disable_confirm).setNegativeButton(android.R.string.cancel, null)
                    .setPositiveButton(R.string.health_reminder_disable) { _, _ -> act(event, HealthReminderAction.DISABLE) }.create())
            }, 8)
        }
    }
    private fun act(event: HealthReminderOccurrence, action: HealthReminderAction) = mutate {
        HealthReminderWork.act(applicationContext, store, event, action, live)
    }
    private fun renderPreferences() {
        val value = draft ?: return
        val content = healthProfileContent(body)
        content.addView(ui.text(getString(R.string.health_reminder_plan), 18f, bold = true))
        toggle(content, R.string.health_reminder_daily, "health-reminder-enabled", value.enabled) { draft = draft?.copy(enabled = it) }
        ui.add(content, ui.profileRow(getString(R.string.health_reminder_time), time(value.minute)) {
            pick(R.string.health_reminder_time, value.minute) { edit { copy(minute = it) } }
        }.apply { tag = "health-reminder-time" })
        ui.add(content, ui.profileRow(getString(R.string.health_reminder_target), getString(value.target.titleResource())) {
            val targets = HealthReminderTarget.entries
            show(AlertDialog.Builder(this).setTitle(R.string.health_reminder_target)
                .setSingleChoiceItems(targets.map { getString(it.titleResource()) }.toTypedArray(), value.target.ordinal) { d, index ->
                    d.dismiss(); edit { copy(target = targets[index]) }
                }.setNegativeButton(android.R.string.cancel, null).create())
        })
        val paused = value.pauseUntil > System.currentTimeMillis()
        ui.add(content, button(if (paused) R.string.health_reminder_resume_plan else R.string.health_reminder_pause,
            "health-reminder-pause") { edit { copy(pauseUntil = if (paused) 0 else System.currentTimeMillis() + HealthReminderPolicy.DAY) } }, 8)
        if (paused) ui.add(content, ui.text(getString(R.string.health_reminder_snoozed_until,
            format(value.pauseUntil, ZoneId.systemDefault().id)), 14f, muted = true), 6)
        ui.add(content, ui.text(getString(R.string.health_reminder_delivery), 18f, bold = true), 24)
        toggle(content, R.string.health_reminder_notifications, "health-reminder-notifications", value.notifications) { draft = draft?.copy(notifications = it) }
        ui.add(content, ui.profileRow(getString(R.string.health_reminder_system_settings),
            getString(if (HealthReminderWork.systemAllowed(this)) R.string.health_reminder_permission_allowed else R.string.health_reminder_permission_denied)) {
            HealthReminderWork.requestPermission(this)
        })
        toggle(content, R.string.health_reminder_quiet, "health-reminder-quiet", value.quiet) { draft = draft?.copy(quiet = it) }
        ui.add(content, ui.profileRow(getString(R.string.health_reminder_quiet_start), time(value.quietStart)) {
            pick(R.string.health_reminder_quiet_start, value.quietStart) { minute ->
                if (minute != draft?.quietEnd) edit { copy(quietStart = minute) } else sameTime()
            }
        })
        ui.add(content, ui.profileRow(getString(R.string.health_reminder_quiet_end), time(value.quietEnd)) {
            pick(R.string.health_reminder_quiet_end, value.quietEnd) { minute ->
                if (minute != draft?.quietStart) edit { copy(quietEnd = minute) } else sameTime()
            }
        })
        toggle(content, R.string.health_reminder_hide_lock, "health-reminder-hide-lock", value.hideOnLock) { draft = draft?.copy(hideOnLock = it) }
        ui.add(content, ui.text(getString(R.string.health_reminder_delivery_note), 13f, muted = true), 12)
        ui.add(content, button(R.string.health_reminder_save, "health-reminder-save", true) {
            val saved = draft ?: return@button
            mutate(exitSettings = true) { HealthReminderWork.save(applicationContext, store, saved, live) }
        }, 16)
    }
    private fun toggle(parent: LinearLayout, label: Int, key: String, checked: Boolean, onChanged: (Boolean) -> Unit) {
        ui.add(parent, Switch(this).apply {
            text = getString(label); textSize = 16f; minimumHeight = ui.dp(48); isChecked = checked; tag = key; isSaveEnabled = false
            setOnCheckedChangeListener { _, enabled -> onChanged(enabled) }
        }, 8)
    }
    private fun edit(change: HealthReminderSettings.() -> HealthReminderSettings) {
        val offset = (body.getChildAt(0) as? android.widget.ScrollView)?.scrollY ?: 0
        draft = draft?.change(); renderPreferences()
        (body.getChildAt(0) as? android.widget.ScrollView)?.let { scroll -> scroll.post { scroll.scrollTo(0, offset) } }
    }
    private fun pick(title: Int, minute: Int, select: (Int) -> Unit) = show(TimePickerDialog(this, { _, hour, min -> select(hour * 60 + min) },
        minute / 60, minute % 60, android.text.format.DateFormat.is24HourFormat(this)).apply { setTitle(title) })
    private fun show(value: AlertDialog) { dialog?.dismiss(); dialog = value; value.setOnDismissListener { if (dialog === value) dialog = null }; value.show() }
    private fun sameTime() { Toast.makeText(this, R.string.health_reminder_quiet_conflict, Toast.LENGTH_SHORT).show() }
    private fun time(minute: Int) = LocalTime.of(minute / 60, minute % 60).format(DateTimeFormatter.ofLocalizedTime(FormatStyle.SHORT))
    private fun format(ms: Long, zone: String) = Instant.ofEpochMilli(ms).atZone(ZoneId.of(zone)).format(DateTimeFormatter.ofLocalizedDateTime(FormatStyle.SHORT))
    private fun mutate(exitSettings: Boolean = false, work: () -> Unit) {
        if (busy) return
        busy = true
        io.execute {
            val result = runCatching(work)
            main.post {
                busy = false
                if (exitSettings && (result.isSuccess || result.exceptionOrNull() is HealthReminderConflict)) {
                    settingsOpen = false; draft = null
                }
                if (active) {
                    result.exceptionOrNull()?.let { Toast.makeText(this, if (it is HealthReminderConflict) R.string.health_reminder_conflict
                        else R.string.health_storage_error, Toast.LENGTH_LONG).show() }
                    load()
                }
            }
        }
    }
    private fun renderError() {
        val content = healthProfileContent(body)
        content.addView(ui.text(getString(R.string.health_storage_error)))
        ui.add(content, button(R.string.common_retry, "health-reminder-retry") { load(refresh = true) }, 12)
    }
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 60) load(refresh = true)
    }
}

internal fun HealthReminderTarget.titleResource() = when (this) {
    HealthReminderTarget.SLEEP -> R.string.health_reminder_sleep
    HealthReminderTarget.MEASUREMENTS -> R.string.health_reminder_measurements
}
private fun HealthReminderFilter.titleResource() = when (this) {
    HealthReminderFilter.PENDING -> R.string.health_reminder_pending
    HealthReminderFilter.HANDLED -> R.string.health_reminder_handled
    HealthReminderFilter.ALL -> R.string.health_reminder_all
}
private fun HealthReminderState.titleResource() = when (this) {
    HealthReminderState.PENDING -> R.string.health_reminder_pending
    HealthReminderState.SNOOZED -> R.string.health_reminder_snoozed
    HealthReminderState.COMPLETE -> R.string.health_reminder_done
    HealthReminderState.DISABLED -> R.string.health_reminder_disabled
}
private fun HealthReminderDelivery.titleResource() = when (this) {
    HealthReminderDelivery.WAITING -> R.string.health_reminder_not_posted
    HealthReminderDelivery.POSTED -> R.string.health_reminder_posted
    HealthReminderDelivery.IN_APP_ONLY -> R.string.health_reminder_in_app_only
}

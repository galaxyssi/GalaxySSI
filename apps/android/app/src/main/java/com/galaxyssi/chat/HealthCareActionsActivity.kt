package com.galaxyssi.chat

import android.app.Activity
import android.content.Intent
import android.database.ContentObserver
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.widget.HorizontalScrollView
import android.widget.LinearLayout
import android.widget.RadioButton
import android.widget.RadioGroup
import java.text.DateFormat
import java.time.ZoneId
import java.util.Date
import java.util.concurrent.Executors

class HealthCareActionsActivity : Activity() {
    private val ui by lazy { HealthCenterViews(this) }
    private val names by lazy { intent.healthNavigationDatabases() }
    private val store by lazy { HealthCareStore(applicationContext, names.care) }
    private val review by lazy { HealthCareActionReview(this, names) }
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private lateinit var body: LinearLayout
    private var active = false
    private var generation = 0
    private var loading = false
    private var dirty = false
    private var filter = HealthCareAgendaFilter.TODAY
    private var cursor: HealthCareAgendaCursor? = null
    private val previous = mutableListOf<HealthCareAgendaCursor?>()
    private var dayEnd = 0L
    private var refreshed = false
    private val observer = object : ContentObserver(main) {
        override fun onChange(selfChange: Boolean) { review.clear(); reset(); load() }
    }
    private val clock = object : Runnable {
        override fun run() {
            if (!active) return
            if (boundary() != dayEnd) { reset(); load() }
            main.postDelayed(this, minOf(60_000L, (dayEnd - System.currentTimeMillis()).coerceAtLeast(1000)))
        }
    }
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        filter = savedInstanceState?.getString("filter")?.let { runCatching { HealthCareAgendaFilter.valueOf(it) }.getOrNull() } ?: filter
        body = healthProfileBody(R.string.health_agenda_title) { finish() }
    }
    override fun onSaveInstanceState(outState: Bundle) { outState.putString("filter", filter.name); super.onSaveInstanceState(outState) }
    override fun onStart() {
        super.onStart(); active = true; dayEnd = boundary()
        listOf(HealthCareStore.changes(this, names.care), HealthRecordStore.changes(this, names.records),
            HealthPrivacyStore.changes(this, names.privacy), HealthProfileStore.changes(this, names.profile))
            .forEach { contentResolver.registerContentObserver(it, false, observer) }
        status(R.string.health_agenda_loading); load(); main.postDelayed(clock, 1000)
    }
    override fun onStop() {
        active = false; generation++; review.clear(); body.removeAllViews(); main.removeCallbacks(clock)
        contentResolver.unregisterContentObserver(observer); super.onStop()
    }
    override fun onDestroy() { review.destroy(); worker.execute { store.close() }; worker.shutdown(); super.onDestroy() }
    private fun boundary() = HealthCareAgenda.dayEnd(System.currentTimeMillis(), ZoneId.systemDefault())
    private fun reset() { generation++; refreshed = cursor != null; cursor = null; previous.clear(); dayEnd = boundary() }
    private data class Snapshot(val permitted: Boolean, val enabled: Boolean, val ready: Boolean, val page: HealthCareAgendaPage?)
    private fun load() {
        if (!active) return
        if (loading) { dirty = true; return }
        loading = true; dirty = false
        val token = generation; val after = cursor; val mode = filter; val end = dayEnd
        worker.execute {
            val result = runCatching {
                HealthCareEngine.evaluate(applicationContext, names)
                val privacy = HealthPrivacyStore(applicationContext, names.privacy).use { it.policy() }
                val allowed = privacy.metrics && privacy.profile
                val ready = allowed && store.prepareAgendaBatch()
                val snapshot = Snapshot(allowed, store.settings().enabled, ready, if (ready) store.agenda(mode, end, after) else null)
                if (HealthPrivacyStore(applicationContext, names.privacy).use { it.policy() } != privacy) throw HealthCareConflict()
                snapshot
            }
            main.post {
                loading = false
                if (active && token == generation) result.fold({ value ->
                    if (!value.permitted) {
                        val content = healthProfileContent(body)
                        content.addView(ui.profileRow(getString(R.string.health_overview_permission)) {
                            startActivity(Intent(this, HealthPrivacyActivity::class.java).putHealthNavigationFixture(names))
                        })
                    } else if (!value.ready) { status(R.string.health_agenda_loading); dirty = true }
                    else render(value)
                }, { error ->
                    if (error is HealthCareConflict && after != null) { reset(); dirty = true }
                    else {
                        status(R.string.health_care_partial)
                        body.addView(ui.command(R.string.health_agenda_retry) { reset(); load() })
                    }
                })
                if (active && (dirty || token != generation)) load()
            }
        }
    }
    private fun status(text: Int) { healthProfileContent(body).addView(ui.text(getString(text), 15f, muted = true)) }
    private fun render(value: Snapshot) {
        val content = healthProfileContent(body)
        val tabs = RadioGroup(this).apply { orientation = LinearLayout.HORIZONTAL }
        HealthCareAgendaFilter.entries.forEach { mode -> tabs.addView(RadioButton(this).apply {
            id = mode.ordinal + 1; text = getString(mode.label()); textSize = 14f
            minHeight = ui.dp(48); isChecked = mode == filter; tag = "health-agenda-filter-${mode.name}"
        }) }
        tabs.setOnCheckedChangeListener { _, id ->
            val mode = HealthCareAgendaFilter.entries.firstOrNull { it.ordinal + 1 == id } ?: return@setOnCheckedChangeListener
            if (mode != filter) { filter = mode; reset(); load() }
        }
        content.addView(HorizontalScrollView(this).apply { isHorizontalScrollBarEnabled = false; addView(tabs) })
        if (!value.enabled) ui.add(content, ui.text(getString(R.string.health_care_disabled), 14f, muted = true), 8)
        if (refreshed) ui.add(content, ui.text(getString(R.string.health_agenda_refreshed), 14f, muted = true), 8)
        val page = value.page!!
        if (page.items.isEmpty()) ui.add(content, ui.text(getString(R.string.health_agenda_empty), 15f, muted = true), 16)
        page.items.forEach { item ->
            val issue = item.concern; val action = item.action
            ui.add(content, ui.profileRow(action.description,
                "${getString(issue.metric.titleResource())} · ${getString(action.state.titleResource())}\n${timing(item)}") {
                review.show(issue.id, action.id)
            }.apply { tag = "health-agenda-action-${action.id}" }, 12)
            ui.add(content, ui.profileRow(getString(R.string.health_agenda_concern)) {
                startActivity(Intent(this, HealthCareActivity::class.java).putHealthNavigationFixture(names).putExtra("health_care_id", issue.id))
            }, 2)
        }
        if (previous.isNotEmpty()) ui.add(content, ui.command(R.string.health_agenda_previous) {
            cursor = previous.removeAt(previous.lastIndex); generation++; load()
        }.apply { tag = "health-agenda-previous" }, 12)
        page.next?.let { next -> ui.add(content, ui.command(R.string.health_agenda_next) {
            previous.add(cursor); cursor = next; generation++; load()
        }.apply { tag = "health-agenda-next" }, 12) }
    }
    private fun timing(item: HealthCareAgendaItem): String {
        if (item.bucket == 2) return getString(R.string.health_agenda_recorded_note)
        if (item.bucket == 1) return getString(R.string.health_agenda_review_note)
        item.reminder?.let { return getString(if (it.state == HealthCareReminderState.DELIVERED)
            R.string.health_agenda_reminded else R.string.health_agenda_reminder, date(it.dueAt)) }
        return if (item.action.dueFrom != null) getString(R.string.health_care_plan_window, date(item.action.dueFrom), date(item.action.dueUntil!!))
            else getString(R.string.health_agenda_unscheduled)
    }
    private fun date(time: Long) = DateFormat.getDateTimeInstance(DateFormat.SHORT, DateFormat.SHORT).format(Date(time))
    private fun HealthCareAgendaFilter.label() = when (this) {
        HealthCareAgendaFilter.TODAY -> R.string.health_agenda_today
        HealthCareAgendaFilter.LATER -> R.string.health_agenda_later
        HealthCareAgendaFilter.REVIEW -> R.string.health_agenda_review
        HealthCareAgendaFilter.RECORDED -> R.string.health_agenda_recorded
    }
}

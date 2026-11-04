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
import java.math.RoundingMode
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
    private val privacy by lazy { healthPrivacyDatabaseName() }
    private val recordsName by lazy {
        val name = intent.getStringExtra("health_sleep_test_records").orEmpty()
        if (live) "health_records_v1.db" else if (BuildConfig.DEBUG && name.startsWith("health-weekly-test-") && name.endsWith(".db") &&
            HealthProfilePolicy.uuid(name.removePrefix("health-weekly-test-").removeSuffix(".db"))) name else null
    }
    private val store by lazy { HealthReminderStore(applicationContext, database) }
    private val healthNames by lazy {
        if (live) HealthOverviewDatabases() else HealthOverviewDatabases(database.removePrefix("health-reminder-test-").removeSuffix(".db"))
    }
    private val reports by lazy { HealthReportReviewRepository(applicationContext, healthNames) }
    private lateinit var body: LinearLayout
    private lateinit var title: TextView
    private var active = false
    private var generation = 0
    private var busy = false
    private var settingsOpen = false
    private var draft: HealthReminderSettings? = null
    private var detail: LocalDate? = null
    private var sleepId: String? = null
    private var sleepAfter: HealthSleepCursor? = null
    private val sleepPrevious = arrayListOf<HealthSleepCursor?>()
    private var watchSleep = false
    private var sleepEvaluationOk = true
    private var filter = HealthReminderFilter.PENDING
    private var after: LocalDate? = null
    private val previous = arrayListOf<LocalDate?>()
    private var reportAfter: HealthReportReviewCursor? = null
    private val reportPrevious = arrayListOf<HealthReportReviewCursor?>()
    private var dialog: AlertDialog? = null
    private val observer = object : ContentObserver(main) {
        override fun onChange(selfChange: Boolean) { if (!busy && !settingsOpen) load() }
    }
    private val changes = object : ContentObserver(main) {
        override fun onChange(selfChange: Boolean) {
            if (active && watchSleep && !busy && !settingsOpen) {
                body.removeAllViews()
                load(refresh = true)
            }
        }
    }
    private val reloadReports = Runnable { if (active && !busy && !settingsOpen && detail == null && sleepId == null) load() }
    private val reportChanges = object : ContentObserver(main) {
        override fun onChange(selfChange: Boolean) {
            main.removeCallbacks(reloadReports)
            main.postDelayed(reloadReports, 200L)
        }
    }
    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        settingsOpen = state?.getBoolean("settings") ?: false
        detail = parse(if (state == null) intent.getStringExtra("health_reminder_day") else state.getString("day"))
        sleepId = (if (state == null) intent.getStringExtra("health_sleep_alert_id") else state.getString("sleep")).orEmpty()
            .takeIf(HealthProfilePolicy::uuid)
        filter = state?.getString("filter")?.let(HealthReminderFilter::valueOf) ?: filter
        after = parse(state?.getString("after")); previous.addAll(state?.getStringArrayList("previous")?.map(::parse).orEmpty())
        reportAfter = parseReportCursor(state?.getString("report_after"))
        reportPrevious.addAll(state?.getStringArrayList("report_previous")?.map(::parseReportCursor).orEmpty())
        body = healthProfileBody(R.string.health_reminder_title) { back() }
        val header = (body.parent as LinearLayout).getChildAt(0) as LinearLayout
        title = header.getChildAt(1) as TextView
    }
    private fun parse(value: String?) = value?.takeIf(String::isNotBlank)?.let { runCatching { LocalDate.parse(it) }.getOrNull() }
    private fun parseReportCursor(value: String?): HealthReportReviewCursor? {
        val time = value?.substringBefore('|')?.toLongOrNull() ?: return null
        val id = value.substringAfter('|')
        return if (HealthProfilePolicy.uuid(id)) HealthReportReviewCursor(time, id) else null
    }
    override fun onSaveInstanceState(out: Bundle) {
        out.putBoolean("settings", settingsOpen); out.putString("day", detail?.toString()); out.putString("filter", filter.name)
        out.putString("sleep", sleepId)
        out.putString("after", after?.toString()); out.putStringArrayList("previous", ArrayList(previous.map { it?.toString().orEmpty() }))
        fun encode(cursor: HealthReportReviewCursor?) = cursor?.let { "${it.createdAt}|${it.id}" }.orEmpty()
        out.putString("report_after", encode(reportAfter))
        out.putStringArrayList("report_previous", ArrayList(reportPrevious.map(::encode)))
        super.onSaveInstanceState(out)
    }
    override fun onStart() {
        super.onStart(); active = true
        contentResolver.registerContentObserver(HealthReminderStore.changes(this, database), false, observer)
        contentResolver.registerContentObserver(HealthPrivacyStore.changes(this, privacy), false, changes)
        recordsName?.let { contentResolver.registerContentObserver(HealthRecordStore.changes(this, it), false, changes) }
        contentResolver.registerContentObserver(HealthOriginalStore.reportChanges(this), false, reportChanges)
        contentResolver.registerContentObserver(HealthRecordStore.syncIncidentChanges(this, healthNames.records), false, reportChanges)
        load(refresh = true)
    }
    override fun onStop() {
        active = false; generation++; contentResolver.unregisterContentObserver(observer)
        contentResolver.unregisterContentObserver(changes)
        contentResolver.unregisterContentObserver(reportChanges); main.removeCallbacks(reloadReports)
        dialog?.dismiss(); dialog = null; body.removeAllViews(); super.onStop()
    }
    override fun onDestroy() { io.execute { store.close() }; io.shutdown(); super.onDestroy() }
    @Deprecated("Native back callback") override fun onBackPressed() = back()
    private fun back() {
        if (busy) return
        when {
            settingsOpen -> { settingsOpen = false; draft = null; load() }
            sleepId != null -> { sleepId = null; load() }
            detail != null -> { detail = null; load() }
            else -> finish()
        }
    }
    private fun load(refresh: Boolean = false) {
        if (!active) return
        val token = ++generation; val day = detail; val cursor = after; val selected = filter
        val preferences = settingsOpen; val selectedSleep = sleepId; val sleepCursor = sleepAfter
        val reportCursor = reportAfter
        title.setText(when { preferences -> R.string.health_reminder_preferences; day != null || selectedSleep != null -> R.string.health_reminder_detail; else -> R.string.health_reminder_title })
        io.execute {
            val result = runCatching {
                if (refresh) {
                    sleepEvaluationOk = if (live) HealthReminderWork.refresh(applicationContext, store, true)
                    else {
                        HealthReminderWork.refresh(applicationContext, store, false)
                        recordsName?.let { HealthSleepAlertEngine.evaluate(applicationContext, store, System.currentTimeMillis(), ZoneId.systemDefault(), it, privacy) } ?: true
                    }
                }
                val settings = store.settings()
                val hasSleep = settings.sleepChanges || store.hasSleepHistory()
                val center = !preferences && day == null && selectedSleep == null
                val sleep = if (!preferences && day == null && hasSleep) HealthPrivacyStore(applicationContext, privacy).use { access ->
                    val policy = access.policy()
                    val views = if (!policy.metrics) SleepViews(blocked = true) else if (!sleepEvaluationOk && settings.sleepChanges) SleepViews(unavailable = true) else SleepViews(
                        page = if (center) store.sleepPage(selected, sleepCursor) else null, alert = selectedSleep?.let(store::sleepAlert))
                    if (access.policy().version != policy.version) SleepViews(blocked = true) else views
                } else SleepViews()
                val reportPage = if (center && settings.reportReviews) runCatching {
                    reports.page(store, selected, reportCursor, System.currentTimeMillis())
                } else null
                val incidents = if (center) runCatching { syncIncidents(selected) } else null
                Snapshot(settings, if (center) store.page(selected, cursor) else null, day?.let(store::occurrence),
                    sleep, hasSleep, reportPage, incidents)
            }
            main.post {
                if (!active || token != generation) return@post
                result.fold({ snapshot ->
                    watchSleep = snapshot.hasSleep
                    if (preferences) { if (draft == null) draft = snapshot.settings; renderPreferences() }
                    else if (selectedSleep != null) renderSleepDetail(snapshot.sleep)
                    else if (day != null) renderDetail(snapshot.event)
                    else renderCenter(snapshot.settings, requireNotNull(snapshot.page), snapshot.sleep, snapshot.hasSleep, snapshot.reports,
                        snapshot.syncIncidents)
                }, { renderError() })
            }
        }
    }
    private data class SleepViews(val page: HealthSleepPage? = null, val alert: HealthSleepAlert? = null,
        val blocked: Boolean = false, val unavailable: Boolean = false)
    private data class Snapshot(val settings: HealthReminderSettings, val page: HealthReminderPage?, val event: HealthReminderOccurrence?,
        val sleep: SleepViews, val hasSleep: Boolean, val reports: Result<HealthReportReviewPage>?,
        val syncIncidents: Result<List<HealthSyncIncident>>?)

    private fun button(label: Int, tag: String, primary: Boolean = false, action: () -> Unit) = ui.command(label, action).apply {
        this.tag = tag
        if (!primary) {
            background = ui.background(stroke = getColor(R.color.separator), radius = 8)
            setTextColor(getColor(R.color.text_primary))
        }
        setPadding(ui.dp(8), ui.dp(8), ui.dp(8), ui.dp(8))
    }
    private fun renderCenter(settings: HealthReminderSettings, page: HealthReminderPage, sleep: SleepViews, hasSleep: Boolean,
        reportPage: Result<HealthReportReviewPage>?, syncIncidents: Result<List<HealthSyncIncident>>?) {
        val content = healthProfileContent(body)
        content.addView(ui.line().apply {
            HealthReminderFilter.entries.forEach { item ->
                val segment = ui.text(getString(item.titleResource()), 14f, bold = item == filter).apply {
                    tag = "health-reminder-filter-${item.name}"; gravity = Gravity.CENTER; minimumHeight = ui.dp(48)
                    isSelected = item == filter; isFocusable = true; setPadding(ui.dp(4), 0, ui.dp(4), 0)
                    background = ui.background(if (item == filter) getColor(R.color.surface_bg) else getColor(R.color.page_bg),
                        if (item == filter) getColor(R.color.separator) else null, radius = 8)
                    setOnClickListener {
                        filter = item; after = null; previous.clear(); sleepAfter = null; sleepPrevious.clear()
                        reportAfter = null; reportPrevious.clear(); load()
                    }
                }
                addView(segment, LinearLayout.LayoutParams(0, -2, 1f))
            }
        })
        if (hasSleep) {
            ui.add(content, ui.text(getString(R.string.health_sleep_alert_group), 18f, bold = true), 20)
            if (sleep.blocked) ui.add(content, ui.profileRow(getString(R.string.health_privacy_trend_blocked)) { startActivity(healthPrivacyIntent()) }, 8)
            else if (sleep.unavailable) ui.add(content, ui.profileRow(getString(R.string.health_storage_error)) { load(refresh = true) }, 8)
            else {
                if (sleep.page?.rows.isNullOrEmpty()) ui.add(content, ui.text(getString(R.string.health_sleep_alert_empty), 15f, muted = true), 10)
                sleep.page?.rows.orEmpty().forEach { alert ->
                    val detail = if (alert.actionable) getString(R.string.health_sleep_alert_decrease, minutes(alert.evidence.decrease))
                        else getString(alert.state.titleResource())
                    ui.add(content, ui.profileRow(getString(R.string.health_sleep_alert_title), detail) { sleepId = alert.id; load(refresh = true) }
                        .apply { tag = "health-sleep-alert" }, 4)
                }
                if (sleepPrevious.isNotEmpty()) ui.add(content, button(R.string.health_previous_page, "health-sleep-prev") {
                    sleepAfter = sleepPrevious.removeAt(sleepPrevious.lastIndex); load()
                }, 8)
                sleep.page?.next?.let { next -> ui.add(content, button(R.string.health_next_page, "health-sleep-next") {
                    sleepPrevious += sleepAfter; sleepAfter = next; load()
                }, 8) }
            }
        }
        reportPage?.let { renderReports(content, it) }
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
        syncIncidents?.let { renderSyncIncidents(content, it) }
        val next = HealthReminderPolicy.nextDaily(settings, System.currentTimeMillis(), ZoneId.systemDefault())
        ui.add(content, ui.text(if (next == null) getString(R.string.health_reminder_plan_off)
            else getString(R.string.health_reminder_next_due, format(next, ZoneId.systemDefault().id)), 14f, muted = true), 20)
        ui.add(content, button(R.string.health_reminder_preferences, "health-reminder-settings") { settingsOpen = true; load() }, 12)
    }
    private fun syncIncidents(selected: HealthReminderFilter): List<HealthSyncIncident> {
        val scopes = if (live) HealthConnectSettings.selection(applicationContext) else HealthConnectScope.entries.toSet()
        if (scopes.isEmpty() || !getDatabasePath(healthNames.records).exists()) return emptyList()
        return HealthRecordStore(applicationContext, healthNames.records).use { records ->
            scopes.mapNotNull(records::healthSyncIncident).filter { it.matches(selected) }
                .sortedWith(compareByDescending<HealthSyncIncident> { it.failedAt }.thenBy { it.scope.ordinal })
        }
    }

    private fun renderSyncIncidents(content: LinearLayout, result: Result<List<HealthSyncIncident>>) {
        val items = result.getOrNull()
        if (items?.isEmpty() == true) return
        ui.add(content, ui.text(getString(R.string.health_sync_reminder_group), 18f, bold = true), 20)
        if (items == null) {
            ui.add(content, ui.profileRow(getString(R.string.health_storage_error)) { load() }, 8)
            return
        }
        val zone = ZoneId.systemDefault().id
        items.forEach { incident ->
            val status = when {
                incident.resolvedAt > 0 -> getString(R.string.health_sync_reminder_resolved, format(incident.resolvedAt, zone))
                else -> getString(incident.outcome.statusResource())
            }
            ui.add(content, ui.card().apply {
                addView(ui.line().apply {
                    addView(ui.profileRow(getString(incident.scope.metric.titleResource()), status) {
                        startActivity(Intent(this@HealthReminderActivity, HealthSyncActivity::class.java)
                            .putExtra("health_sync_scope", incident.scope.name).putExtra("health_sync_test_id", healthNames.fixture))
                    }.apply { tag = "health-sync-reminder-${incident.scope.name}" }, LinearLayout.LayoutParams(0, -2, 1f))
                    if (!incident.handled) addView(ui.icon(R.drawable.ic_more_horizontal, R.string.health_report_review_actions) {
                        show(AlertDialog.Builder(this@HealthReminderActivity).setTitle(R.string.health_report_review_actions)
                            .setItems(arrayOf(getString(R.string.health_report_review_handle))) { _, _ ->
                                mutate {
                                    HealthRecordStore(applicationContext, healthNames.records).use {
                                        it.acknowledgeHealthSyncIncident(incident, System.currentTimeMillis())
                                    }
                                }
                            }.setNegativeButton(android.R.string.cancel, null).create())
                    }.apply { tag = "health-sync-reminder-actions-${incident.scope.name}" }, LinearLayout.LayoutParams(ui.dp(48), ui.dp(48)))
                })
                ui.add(this, ui.text(getString(R.string.health_sync_reminder_failed_at, format(incident.failedAt, zone)), 13f, muted = true), 4)
                if (incident.resolvedAt == 0L) ui.add(this, ui.text(
                    if (incident.lastSuccess == 0L) getString(R.string.health_sync_no_success)
                    else getString(R.string.health_sync_success_time, format(incident.lastSuccess, zone)), 13f, muted = true), 4)
            }, 8)
        }
        ui.add(content, ui.text(getString(R.string.health_sync_reminder_retention), 13f, muted = true), 6)
    }
    private fun renderReports(content: LinearLayout, result: Result<HealthReportReviewPage>) {
        val page = result.getOrNull()
        if (page?.rows?.isEmpty() == true && page.next == null && reportPrevious.isEmpty()) return
        ui.add(content, ui.text(getString(R.string.health_report_review_group), 18f, bold = true), 20)
        if (page == null) {
            ui.add(content, ui.profileRow(getString(R.string.health_storage_error)) { load() }, 8)
            return
        }
        val now = System.currentTimeMillis()
        val zone = ZoneId.systemDefault().id
        page.rows.forEach { report ->
            val state = report.state(now)
            val label = getString(if (report.kind == HealthOverviewReviewKind.OCR) R.string.health_report_review_document else R.string.health_report_review_table)
            val status = if (state == HealthReminderState.SNOOZED)
                getString(R.string.health_reminder_snoozed_until, format(report.disposition.resumeAt, zone))
            else getString(state.titleResource())
            ui.add(content, ui.line().apply {
                addView(ui.profileRow(report.name, "$label · $status") { openReport(report) }.apply {
                    tag = "health-report-review-${report.id}"
                }, LinearLayout.LayoutParams(0, -2, 1f))
                if (state != HealthReminderState.COMPLETE) addView(ui.icon(R.drawable.ic_more_horizontal, R.string.health_report_review_actions) {
                    show(AlertDialog.Builder(this@HealthReminderActivity).setTitle(R.string.health_report_review_actions)
                        .setItems(arrayOf(getString(R.string.health_report_review_snooze), getString(R.string.health_report_review_handle))) { _, which ->
                            mutate { reports.act(store, report, if (which == 0) HealthReminderAction.SNOOZE else HealthReminderAction.COMPLETE,
                                System.currentTimeMillis())
                                if (live) HealthReminderWork.reportSourceChanged(applicationContext)
                            }
                        }.setNegativeButton(android.R.string.cancel, null).create())
                }.apply { tag = "health-report-review-actions-${report.id}" }, LinearLayout.LayoutParams(ui.dp(48), ui.dp(48)))
            }, 4)
        }
        if (page.rows.isEmpty()) ui.add(content, ui.text(getString(R.string.health_reminder_empty), 14f, muted = true), 8)
        if (reportPrevious.isNotEmpty()) ui.add(content, button(R.string.health_previous_page, "health-report-review-previous") {
            reportAfter = reportPrevious.removeAt(reportPrevious.lastIndex); load()
        }, 8)
        page.next?.let { next -> ui.add(content, button(R.string.health_next_page, "health-report-review-next") {
            reportPrevious += reportAfter; reportAfter = next; load()
        }, 8) }
        main.removeCallbacks(reloadReports)
        page.rows.map { it.disposition.resumeAt }.filter { it > now }.minOrNull()?.let { main.postDelayed(reloadReports, it - now) }
    }
    private fun openReport(report: HealthReportReview) {
        startActivity(report.intent(this, healthNames.fixture))
    }
    private fun minutes(value: java.math.BigDecimal) = value.setScale(1, RoundingMode.HALF_UP).stripTrailingZeros().toPlainString()
    private fun renderSleepDetail(sleep: SleepViews) {
        val content = healthProfileContent(body)
        if (sleep.blocked) {
            content.addView(ui.text(getString(R.string.health_privacy_trend_blocked)))
            ui.add(content, button(R.string.health_privacy_title, "health-sleep-blocked") { startActivity(healthPrivacyIntent()) }, 12)
            return
        }
        if (sleep.unavailable) { renderError(); return }
        val alert = sleep.alert ?: run { content.addView(ui.text(getString(R.string.health_sleep_alert_empty))); return }
        val evidence = alert.evidence
        val zone = ZoneId.of(evidence.zone)
        ui.add(content, ui.column().apply {
            background = ui.background(stroke = getColor(R.color.separator), radius = 8)
            setPadding(ui.dp(14), ui.dp(12), ui.dp(14), ui.dp(12))
            addView(ui.text(getString(R.string.health_sleep_alert_tag), 13f, bold = true).apply { setTextColor(0xff9d660c.toInt()) })
            ui.add(this, ui.text(getString(R.string.health_sleep_alert_title), 22f, bold = true), 6)
            ui.add(this, ui.text(getString(R.string.health_sleep_alert_opened, format(alert.openedAt, alert.trigger.zone)), 13f, muted = true), 6)
            ui.add(this, ui.text(getString(alert.state.titleResource()), 14f, bold = true).apply { tag = "health-sleep-state-${alert.state.name}" }, 6)
        })
        ui.add(content, ui.text(getString(R.string.health_sleep_alert_basis), 18f, bold = true), 20)
        val spec = HealthTrendSpec(HealthMetric.SLEEP_DURATION, evidence.first, evidence.end, zone, "min")
        var prior = -2
        val points = evidence.daily.mapIndexedNotNull { i, value ->
            value?.let {
                val day = evidence.first.plusDays(i.toLong())
                HealthTrendPoint(i, "sleep_duration", day, day, it, 1, "", prior + 1 != i).also { prior = i }
            }
        }
        val chart = HealthTrendChart(this) { point -> openSleepRecords(evidence, point.first, point.last) }
        chart.bind(HealthTrendSummary(spec, evidence.records, evidence.records, 0, 0, evidence.recentDays, evidence.recentDays,
            points, null, evidence.metricVersion, evidence.computedAt))
        content.addView(chart.apply { tag = "health-sleep-chart" }, LinearLayout.LayoutParams(-1, ui.dp(168)).apply { topMargin = ui.dp(10) })
        ui.add(content, ui.text(getString(R.string.health_weekly_compare, minutes(evidence.recent), minutes(evidence.baseline), "-${minutes(evidence.decrease)}")), 8)
        ui.add(content, ui.text(getString(R.string.health_weekly_compare_coverage, evidence.recentDays, evidence.baselineDays), 14f, muted = true), 8)
        ui.add(content, ui.text(getString(R.string.health_weekly_baseline_range, evidence.baselineFirst, evidence.baselineLast), 13f, muted = true), 6)
        ui.add(content, ui.text(getString(R.string.health_sleep_alert_rule, evidence.rule, evidence.threshold), 13f, muted = true), 6)
        if (alert.trigger != evidence) ui.add(content, ui.text(getString(R.string.health_sleep_alert_trigger,
            alert.trigger.first, alert.trigger.end, minutes(alert.trigger.decrease)), 13f, muted = true), 8)
        ui.add(content, ui.profileRow(getString(R.string.health_sleep_alert_source)) { openSleepRecords(evidence, evidence.first, evidence.end) }, 6)
        ui.add(content, ui.profileRow(getString(R.string.health_weekly_baseline_records)) { openSleepRecords(evidence, evidence.baselineFirst, evidence.baselineLast) })
        ui.add(content, ui.text(getString(R.string.health_sleep_alert_record_note), 14f), 12)
        ui.add(content, ui.text(getString(R.string.health_not_diagnosis), 13f, muted = true), 8)
        ui.add(content, ui.text(getString(alert.delivery.titleResource()), 13f, muted = true), 8)
        if (alert.handledAt != 0L) ui.add(content, ui.text(getString(R.string.health_sleep_alert_handled,
            format(alert.handledAt, evidence.zone)), 13f, muted = true), 6)
        if (alert.actionable) {
            if (alert.state == HealthReminderState.SNOOZED) ui.add(content, ui.text(getString(R.string.health_reminder_snoozed_until,
                format(alert.resumeAt, ZoneId.systemDefault().id)), 13f, muted = true), 6)
            ui.add(content, button(R.string.health_reminder_open_record, "health-sleep-add-record") {
                startActivity(Intent(this, HealthCenterActivity::class.java).putExtra("health_manual", true).putExtra("health_metric", HealthMetric.SLEEP_DURATION.name))
            }, 12)
            ui.add(content, button(R.string.health_reminder_complete, "health-sleep-complete", true) { actSleep(alert, HealthReminderAction.COMPLETE) }, 10)
            ui.add(content, button(R.string.health_reminder_snooze, "health-sleep-snooze") { actSleep(alert, HealthReminderAction.SNOOZE) }, 8)
            ui.add(content, button(R.string.health_sleep_alert_disable, "health-sleep-disable") {
                show(AlertDialog.Builder(this).setMessage(R.string.health_sleep_alert_disable_confirm).setNegativeButton(android.R.string.cancel, null)
                    .setPositiveButton(R.string.health_sleep_alert_disable) { _, _ -> actSleep(alert, HealthReminderAction.DISABLE) }.create())
            }, 8)
        }
    }
    private fun openSleepRecords(evidence: HealthSleepAlertEvidence, first: LocalDate, last: LocalDate) {
        if (!live) return
        val spec = HealthTrendSpec(HealthMetric.SLEEP_DURATION, first, last, ZoneId.of(evidence.zone), "min")
        startActivity(Intent(this, HealthTrendRecordsActivity::class.java).putHealthTrend(spec)
            .putExtra("health_fixed_version", true).putExtra("health_version", evidence.metricVersion))
    }
    private fun actSleep(alert: HealthSleepAlert, action: HealthReminderAction) = mutate {
        HealthReminderWork.actSleep(applicationContext, store, alert, action, live)
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
        content.addView(ui.text(getString(R.string.health_sleep_alert_group), 18f, bold = true))
        toggle(content, R.string.health_sleep_alert_setting, "health-sleep-enabled", value.sleepChanges) { draft = draft?.copy(sleepChanges = it) }
        ui.add(content, ui.profileRow(getString(R.string.health_sleep_alert_threshold), getString(R.string.health_sleep_alert_threshold_value, value.sleepDecrease)) {
            val thresholds = HealthSleepAlertPolicy.thresholds
            show(AlertDialog.Builder(this).setTitle(R.string.health_sleep_alert_threshold)
                .setSingleChoiceItems(thresholds.map { getString(R.string.health_sleep_alert_threshold_value, it) }.toTypedArray(),
                    thresholds.indexOf(value.sleepDecrease)) { d, index -> d.dismiss(); edit { copy(sleepDecrease = thresholds[index]) } }
                .setNegativeButton(android.R.string.cancel, null).create())
        })
        toggle(content, R.string.health_sleep_alert_merge, "health-sleep-merge", value.mergeSleepChanges) { draft = draft?.copy(mergeSleepChanges = it) }
        ui.add(content, ui.text(getString(R.string.health_sleep_alert_note), 13f, muted = true), 8)
        ui.add(content, ui.text(getString(R.string.health_reminder_plan), 18f, bold = true), 24)
        toggle(content, R.string.health_reminder_daily, "health-reminder-enabled", value.enabled) { draft = draft?.copy(enabled = it) }
        toggle(content, R.string.health_report_review_setting, "health-report-review-enabled", value.reportReviews) { draft = draft?.copy(reportReviews = it) }
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
                    load(refresh = true)
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
    HealthReminderState.STALE -> R.string.health_sleep_alert_stale
}
private fun HealthReminderDelivery.titleResource() = when (this) {
    HealthReminderDelivery.WAITING -> R.string.health_reminder_not_posted
    HealthReminderDelivery.POSTED -> R.string.health_reminder_posted
    HealthReminderDelivery.IN_APP_ONLY -> R.string.health_reminder_in_app_only
}

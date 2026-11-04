package com.galaxyssi.chat

import android.app.Activity
import android.app.AlertDialog
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.View
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import java.text.DateFormat
import java.util.Date
import java.util.concurrent.Executors

/** A separate native page stack; health data never enters the chat transcript or generic agent memory. */
class HealthCenterActivity : Activity() {
    internal val ui by lazy { HealthCenterViews(this) }
    internal lateinit var body: LinearLayout
    private lateinit var title: TextView
    private lateinit var reminderIcon: View
    private lateinit var reminderSpacer: View
    private lateinit var root: LinearLayout
    private val worker = Executors.newSingleThreadExecutor()
    internal val main = Handler(Looper.getMainLooper())
    private val records by lazy { HealthRecordStore(applicationContext) }
    private var active = false
    private var generation = 0
    private var route = "overview"
    private var selected = HealthMetric.BLOOD_PRESSURE
    private var recordId = ""
    private var reviewKey = ""
    private val backStack = ArrayDeque<Triple<String, HealthMetric, String>>()
    internal var editor: HealthManualEditor? = null
    internal var saving = false
    private val sensitiveDialogs = mutableSetOf<android.app.Dialog>()
    private var nextPage: HealthPageCursor? = null
    private var pageAfter: HealthPageCursor? = null
    private val pageHistory = mutableListOf<HealthPageCursor?>()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.statusBarColor = getColor(R.color.surface_bg)
        window.navigationBarColor = getColor(R.color.page_bg)
        if (android.os.Build.VERSION.SDK_INT >= 33) setRecentsScreenshotEnabled(false)
        reviewKey = savedInstanceState?.getString("review").orEmpty().ifBlank { intent.getStringExtra("review_draft").orEmpty() }
        intent.getStringExtra("health_metric")?.let { name -> HealthMetric.entries.firstOrNull { it.name == name }?.let { selected = it } }
        if (reviewKey.isNotBlank()) {
            require(reviewKey.matches(Regex("ocr:[0-9a-f-]{36}:[1-9][0-9]*:[a-zA-Z0-9_-]{1,80}")))
            route = "review"
        } else if (savedInstanceState == null && intent.getBooleanExtra("health_functions", false)) {
            route = "functions"
        } else if (savedInstanceState == null && intent.getBooleanExtra("health_manual", false)) {
            route = "manual"
        } else if (savedInstanceState == null && intent.getBooleanExtra("health_metric_records", false)) {
            route = "metric_records"
        } else if (savedInstanceState == null && !intent.getStringExtra("health_record").isNullOrBlank()) {
            recordId = intent.getStringExtra("health_record").orEmpty()
            require(runCatching { java.util.UUID.fromString(recordId).toString() == recordId }.getOrDefault(false))
            route = if (intent.getBooleanExtra("health_history", false)) "history" else "detail"
        }
        savedInstanceState?.let { state ->
            route = state.getString("route", "overview").orEmpty().ifBlank { "overview" }
            selected = HealthMetric.entries.getOrElse(state.getInt("metric")) { HealthMetric.BLOOD_PRESSURE }
            recordId = state.getString("record", "").orEmpty()
            state.getStringArrayList("stack")?.forEach { encoded ->
                val parts = encoded.split('|')
                if (parts.size == 3) backStack.addLast(Triple(parts[0], HealthMetric.valueOf(parts[1]), parts[2]))
            }
        }
        root = ui.column().apply { setBackgroundColor(getColor(R.color.page_bg)) }
        root.addView(ui.line().apply {
            addView(ui.icon(R.drawable.ic_navigation_back, R.string.health_back) { back() })
            reminderSpacer = View(this@HealthCenterActivity)
            addView(reminderSpacer, LinearLayout.LayoutParams(ui.dp(48), ui.dp(48)))
            title = ui.text(getString(R.string.health_title), 19f, bold = true).apply { gravity = Gravity.CENTER }
            addView(title, LinearLayout.LayoutParams(0, -2, 1f))
            reminderIcon = ui.icon(R.drawable.ic_settings_notification, R.string.health_reminder_title) { openReminders() }.apply { tag = "health-reminders" }
            addView(reminderIcon)
            addView(ui.icon(R.drawable.ic_health_grid, R.string.health_functions) { open("functions") }.apply { tag = "health-functions" })
        }, LinearLayout.LayoutParams(-1, ui.dp(56)))
        body = ui.column()
        root.addView(body, LinearLayout.LayoutParams(-1, 0, 1f))
        setContentView(root)
    }
    override fun onStart() { super.onStart(); active = true; render() }
    override fun onStop() {
        saveDraft()
        active = false; generation++
        main.removeCallbacks(savePendingDraft)
        editor = null; body.removeAllViews()
        sensitiveDialogs.toList().forEach { it.dismiss() }; sensitiveDialogs.clear()
        super.onStop()
    }
    override fun onDestroy() {
        worker.execute { records.close() }; worker.shutdown()
        super.onDestroy()
    }
    override fun onSaveInstanceState(out: Bundle) {
        saveDraft()
        out.putString("route", route); out.putInt("metric", selected.ordinal); out.putString("record", recordId)
        out.putString("review", reviewKey)
        out.putStringArrayList("stack", ArrayList(backStack.map { "${it.first}|${it.second.name}|${it.third}" }))
        super.onSaveInstanceState(out)
    }
    @Deprecated("Android activity back callback") override fun onBackPressed() = back()

    private fun back() {
        if (saving) return
        saveDraft()
        if (backStack.isEmpty()) { finish(); return }
        val previous = backStack.removeLast()
        route = previous.first; selected = previous.second; recordId = previous.third
        render()
    }
    internal fun open(destination: String, metric: HealthMetric = selected, id: String = "") {
        if (saving) return
        saveDraft()
        if (destination in listOf("records", "metric_records") && (route != destination || selected != metric)) {
            pageAfter = null; nextPage = null; pageHistory.clear()
        }
        if (route != destination || selected != metric || recordId != id) backStack.addLast(Triple(route, selected, recordId))
        route = destination; selected = metric; recordId = id
        render()
    }
    internal fun changeMetric(metric: HealthMetric) {
        if (saving) return
        saveDraft(); selected = metric; recordId = ""; render()
    }
    internal fun saveDraft() {
        if (saving) return
        editor?.snapshot()?.let { draft -> worker.execute {
            if (runCatching { records.saveDraft(draft) }.isFailure) main.post {
                if (active && !isDestroyed) Toast.makeText(this, R.string.health_draft_error, Toast.LENGTH_LONG).show()
            }
        } }
    }
    internal fun draftChanged() {
        main.removeCallbacks(savePendingDraft)
        main.postDelayed(savePendingDraft, 350)
    }
    internal fun showHealthDialog(dialog: android.app.Dialog) {
        sensitiveDialogs += dialog
        dialog.setOnDismissListener { sensitiveDialogs -= dialog }
        dialog.show()
    }
    private val savePendingDraft = Runnable { saveDraft() }

    internal fun <T> query(work: (HealthRecordStore) -> T, done: (T) -> Unit) {
        val token = generation
        worker.execute {
            val result = runCatching { work(records) }
            main.post {
                if (!active || token != generation || isDestroyed) return@post
                result.fold(done) {
                    Toast.makeText(this, getString(R.string.health_storage_error), Toast.LENGTH_LONG).show()
                    body.addView(ui.row(getString(R.string.common_retry)) { render() })
                }
            }
        }
    }
    private fun render() {
        generation++; main.removeCallbacks(savePendingDraft); editor = null; body.removeAllViews()
        val reminderVisibility = if (route == "overview") View.VISIBLE else View.GONE
        reminderIcon.visibility = reminderVisibility; reminderSpacer.visibility = reminderVisibility
        title.text = getString(when (route) {
            "manual" -> R.string.health_manual
            "review" -> R.string.health_review_title
            "records" -> R.string.health_records
            "metric_records" -> selected.titleResource()
            "detail" -> selected.titleResource()
            "history" -> R.string.health_revision_history
            "functions" -> R.string.health_functions
            else -> R.string.health_title
        })
        when (route) {
            "manual", "review" -> renderManual()
            "records", "metric_records" -> renderRecords()
            "detail" -> renderDetail()
            "history" -> renderHistory()
            "functions" -> renderFunctions()
            else -> renderOverview()
        }
    }
    internal fun scrolling(): LinearLayout {
        val content = ui.column().apply { setPadding(ui.dp(16), ui.dp(20), ui.dp(16), ui.dp(24)) }
        body.addView(ScrollView(this).apply { isFillViewport = true; addView(content) }, LinearLayout.LayoutParams(-1, 0, 1f))
        return content
    }
    internal fun date(time: Long): String = DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT).format(Date(time))
    private fun renderOverview() {
        val content = scrolling()
        val loading = ui.text(getString(R.string.health_loading), 14f, muted = true)
        content.addView(loading)
        val overviewMetrics = listOf(HealthMetric.BLOOD_PRESSURE, HealthMetric.GLUCOSE, HealthMetric.WEIGHT, HealthMetric.HEART_RATE,
            HealthMetric.SLEEP_DURATION, HealthMetric.STEPS)
        query({ store -> store.count() to overviewMetrics.associateWith { metric ->
            store.page(metric = metric, limit = 1).records.firstOrNull()
        } }) { (count, latest) ->
            content.removeAllViews()
            if (count == 0L) {
                val hero = ui.column().apply { gravity = Gravity.CENTER; setPadding(0, ui.dp(25), 0, ui.dp(25)) }
                hero.addView(android.widget.ImageView(this).apply {
                    setImageResource(R.drawable.ic_health_heart); imageTintList = android.content.res.ColorStateList.valueOf(0xff15975e.toInt())
                    setPadding(ui.dp(20), ui.dp(20), ui.dp(20), ui.dp(20)); background = ui.background(0xffe8f6ee.toInt(), radius = 28)
                }, LinearLayout.LayoutParams(ui.dp(80), ui.dp(80)))
                ui.add(hero, ui.text(getString(R.string.health_first_title), 23f, bold = true).apply { gravity = Gravity.CENTER }, 22)
                ui.add(hero, ui.text(getString(R.string.health_first_description), 15f, muted = true).apply { gravity = Gravity.CENTER }, 12)
                content.addView(hero)
                ui.add(content, ui.card().apply {
                    addView(ui.row(getString(R.string.health_photo_record), getString(R.string.health_photo_description)) { openCapture() })
                    addView(ui.row(getString(R.string.health_manual), getString(R.string.health_measurement_context)) { open("manual") })
                    addView(ui.row(getString(R.string.health_records)) { open("records") })
                }, 18)
                ui.add(content, ui.text(getString(R.string.health_no_analysis), 13f, muted = true), 20)
                ui.add(content, ui.command(R.string.health_add_first) { open("manual") }, 20)
                ui.add(content, ui.row(getString(R.string.health_export_data_files)) { startActivity(android.content.Intent(this, HealthDataFilesActivity::class.java)) }, 12)
            } else {
                content.addView(ui.text(getString(R.string.health_your_records), 26f, bold = true))
                ui.add(content, ui.row(getString(R.string.health_export_data_files)) { startActivity(android.content.Intent(this, HealthDataFilesActivity::class.java)) }, 8)
                ui.add(content, ui.text(getString(R.string.health_record_count, count), 14f, muted = true), 6)
                ui.add(content, ui.command(R.string.health_add_measurement) { open("manual") }, 18)
                ui.add(content, ui.row(getString(R.string.health_photo_record), getString(R.string.health_photo_description)) { openCapture() }, 10)
                ui.add(content, ui.row(getString(R.string.health_key_metrics), getString(R.string.health_catalog_title)) { openCatalog() }, 20)
                overviewMetrics.chunked(2).forEach { metrics ->
                    val line = ui.line().apply { gravity = Gravity.TOP }
                    metrics.forEachIndexed { index, metric ->
                        val record = latest[metric]
                        val card = ui.card().apply {
                            minimumHeight = ui.dp(142)
                            addView(ui.text(getString(metric.titleResource()), 14f, muted = true))
                            ui.add(this, ui.text(record?.let(::value) ?: getString(R.string.health_no_measurement),
                                if (record == null) 16f else 23f, bold = record != null), 12)
                            if (record != null) ui.add(this, ui.text(date(record.draft.measuredAt), 12f, muted = true), 8)
                            setOnClickListener {
                                startActivity(android.content.Intent(this@HealthCenterActivity, HealthTrendActivity::class.java).putExtra("health_metric", metric.name))
                            }
                            isFocusable = true
                        }
                        line.addView(card, LinearLayout.LayoutParams(0, -2, 1f).apply {
                            if (index == 0) marginEnd = ui.dp(5) else marginStart = ui.dp(5)
                        })
                    }
                    ui.add(content, line, 12)
                }
                ui.add(content, ui.text(getString(R.string.health_not_diagnosis), 12f, muted = true), 18)
            }
        }
    }
    private fun renderFunctions() {
        scrolling().apply {
            addView(ui.text(getString(R.string.health_management), 20f, bold = true))
            ui.add(this, ui.card().apply {
                addView(ui.row(getString(R.string.health_title)) { open("overview") })
                addView(ui.row(getString(R.string.health_photo_record), getString(R.string.health_photo_description)) { openCapture() })
                addView(ui.row(getString(R.string.health_original_library)) {
                    startActivity(android.content.Intent(this@HealthCenterActivity, HealthOriginalLibraryActivity::class.java))
                })
                addView(ui.row(getString(R.string.health_manual), getString(R.string.health_measurement_context)) { open("manual") })
                addView(ui.row(getString(R.string.health_records), getString(R.string.health_record_sources)) { open("records") })
                addView(ui.row(getString(R.string.health_catalog_title)) { openCatalog() })
                addView(ui.row(getString(R.string.health_weekly_title)) { openWeekly() }.apply { tag = "health-weekly-entry" })
                addView(ui.row(getString(R.string.health_export_data_files)) { startActivity(android.content.Intent(this@HealthCenterActivity, HealthDataFilesActivity::class.java)) })
            }, 14)
            ui.add(this, ui.text(getString(R.string.health_profile_preferences), 18f, bold = true), 24)
            ui.add(this, ui.profileRow(getString(R.string.health_profile_title), getString(R.string.health_profile_source)) {
                startActivity(android.content.Intent(this@HealthCenterActivity, HealthProfileActivity::class.java))
            }.apply { tag = "health-profile-entry" }, 8)
            ui.add(this, ui.profileRow(getString(R.string.health_privacy_title)) { startActivity(healthPrivacyIntent()) }.apply { tag = "health-privacy-entry" }, 8)
            ui.add(this, ui.profileRow(getString(R.string.health_reminder_title)) { openReminders() }, 8)
        }
    }
    private fun openReminders() = startActivity(android.content.Intent(this, HealthReminderActivity::class.java))
    private fun openWeekly() = startActivity(android.content.Intent(this, HealthWeeklyActivity::class.java))
    private fun recordRow(record: HealthObservation) = ui.card().apply {
        addView(ui.text(getString(record.draft.metric.titleResource()), 14f, muted = true))
        ui.add(this, ui.text(value(record), if (value(record).length > 24) 18f else 25f, bold = true), 6)
        ui.add(this, ui.text("${date(record.draft.measuredAt)} \u00b7 ${source(record)}", 12f, muted = true), 8)
        setOnClickListener { open("detail", record.draft.metric, record.id) }; isFocusable = true
    }
    internal fun value(record: HealthObservation): String {
        return healthDisplayValue(record.draft)
    }
    private fun renderRecords() {
        val content = scrolling()
        nextPage = null
        val after = pageAfter
        val metric = selected.takeIf { route == "metric_records" }
        query({ it.page(after, metric) }) { page ->
            nextPage = page.next
            page.records.forEach { ui.add(content, recordRow(it), 10) }
            if (content.childCount == 0) content.addView(ui.text(getString(R.string.health_no_records), 15f, muted = true))
            if (pageHistory.isNotEmpty()) ui.add(content, ui.command(R.string.health_previous_page) {
                pageAfter = pageHistory.removeAt(pageHistory.lastIndex); render()
            }, 16)
            if (nextPage != null) ui.add(content, ui.command(R.string.health_next_page) {
                pageHistory += pageAfter; pageAfter = nextPage; render()
            }, 16)
            if (metric != null) ui.add(content, ui.command(R.string.health_add_measurement) { open("manual", metric) }, 16)
        }
    }
    private fun renderDetail() {
        val content = scrolling()
        val id = recordId
        query({ it.record(id) }) { record ->
            if (record == null) { content.addView(ui.text(getString(R.string.health_record_missing))); return@query }
            title.text = getString(record.draft.metric.titleResource())
            content.addView(recordRow(record))
            ui.add(content, ui.card().apply {
                addView(ui.text(getString(R.string.health_measured_at), 13f, muted = true)); addView(ui.text(date(record.draft.measuredAt)))
                ui.add(this, ui.text(source(record), 14f, muted = true), 14)
                record.draft.evidence?.let { evidence ->
                    val location = if (evidence.tableSheet.isNotBlank()) getString(R.string.health_xlsx_source_row, evidence.tableSheet, evidence.tableRow)
                        else getString(if (evidence.kind == "table") R.string.health_table_source_row else R.string.health_source_page,
                            if (evidence.kind == "table") evidence.tableRow else evidence.page.toLong())
                    ui.add(this, ui.row(getString(R.string.health_view_original), location) {
                        startActivity(android.content.Intent(this@HealthCenterActivity, HealthCaptureActivity::class.java).putExtra("original", evidence.originalId))
                    }, 12)
                    ui.add(this, ui.text(evidence.rawText, 13f, muted = true), 8)
                }
                addView(ui.text(getString(healthContextResource(record.draft.condition))))
                if (record.draft.metric == HealthMetric.BLOOD_PRESSURE) {
                    addView(ui.text(getString(healthContextResource(record.draft.side))))
                    record.draft.values["pulse"]?.let { addView(ui.text("${getString(R.string.health_pulse)}: $it bpm")) }
                }
                if (record.draft.note.isNotBlank()) ui.add(this, ui.text(record.draft.note), 12)
                if (record.draft.reference.isNotBlank()) {
                    ui.add(this, ui.text(getString(R.string.health_report_reference), 13f, muted = true), 12)
                    addView(ui.text(record.draft.reference))
                }
                ui.add(this, ui.text(getString(R.string.health_revision, record.revision), 12f, muted = true), 12)
            }, 16)
            ui.add(content, ui.row(getString(R.string.common_edit)) { open("manual", record.draft.metric, record.id) }, 14)
            ui.add(content, ui.row(getString(R.string.health_revision_history)) { open("history", record.draft.metric, record.id) })
            ui.add(content, ui.row(getString(R.string.common_delete)) {
                AlertDialog.Builder(this).setTitle(R.string.health_delete_title).setMessage(R.string.health_delete_description)
                    .setNegativeButton(R.string.common_cancel, null).setPositiveButton(R.string.common_delete) { _, _ ->
                        query({ it.delete(record.id, record.revision) }) { removed ->
                            if (removed) back() else Toast.makeText(this, R.string.health_conflict, Toast.LENGTH_LONG).show()
                        }
                    }.show()
            })
        }
    }
    private fun renderHistory(beforeRevision: Int = Int.MAX_VALUE) {
        body.removeAllViews()
        val content = scrolling()
        val id = recordId
        query({ it.history(id, beforeRevision) }) { history ->
            history.forEach { record ->
            ui.add(content, ui.card().apply {
                addView(ui.text(getString(R.string.health_revision, record.revision), bold = true))
                addView(ui.text(value(record))); addView(ui.text(date(record.receivedAt), 13f, muted = true))
            }, 12)
            }
            if (beforeRevision != Int.MAX_VALUE) ui.add(content, ui.command(R.string.health_latest_revisions) { renderHistory() }, 16)
            if (history.size == 50) ui.add(content, ui.command(R.string.health_older_revisions) { renderHistory(history.last().revision) }, 16)
        }
    }
    private fun renderManual() {
        val id = recordId
        val metric = selected
        val key = if (route == "review") reviewKey else if (id.isBlank()) "new:${metric.name}" else "edit:$id"
        val reviewing = route == "review"
        query({ store -> if (reviewing) store.draft(key) else if (id.isBlank()) store.draft(key) ?: HealthDraft(metric)
            else store.record(id)?.let { store.draft(key) ?: it.editable() } }) { draft ->
            if (draft == null) { body.addView(ui.text(getString(R.string.health_record_missing))); return@query }
            selected = draft.metric
            editor = HealthManualEditor(this, draft).also { it.render() }
        }
    }
    internal fun saveMeasurement(draft: HealthDraft) {
        if (saving) return
        HealthObservationPolicy.validate(draft)?.let { error -> editor?.showError(error); return }
        saving = true
        editor?.setSaving(true)
        main.removeCallbacks(savePendingDraft)
        worker.execute {
            val result = runCatching { records.save(draft) }
            main.post {
                saving = false
                if (isDestroyed) return@post
                result.fold({ saved ->
                    when (saved) {
                    is HealthSaveResult.Saved -> {
                        editor = null
                        if (active) {
                            Toast.makeText(this, R.string.health_saved, Toast.LENGTH_SHORT).show()
                            back()
                        } else {
                            val previous = if (backStack.isEmpty()) Triple("overview", selected, "") else backStack.removeLast()
                            route = previous.first; selected = previous.second; recordId = previous.third
                        }
                    }
                    is HealthSaveResult.Duplicate -> if (active) {
                        editor?.setSaving(false)
                        AlertDialog.Builder(this).setMessage(R.string.health_duplicate).setNegativeButton(R.string.common_cancel, null)
                            .setPositiveButton(R.string.health_view_existing) { _, _ -> open("detail", draft.metric, saved.id) }.show()
                    }
                    HealthSaveResult.Conflict -> if (active) { editor?.setSaving(false); Toast.makeText(this, R.string.health_conflict, Toast.LENGTH_LONG).show() }
                    }
                    Unit
                }, {
                    if (active) { editor?.setSaving(false); Toast.makeText(this, R.string.health_storage_error, Toast.LENGTH_LONG).show() }
                    Unit
                })
            }
        }
    }
    private fun openCapture() { startActivity(android.content.Intent(this, HealthCaptureActivity::class.java)) }
    private fun openCatalog() { startActivity(android.content.Intent(this, HealthCatalogActivity::class.java)) }
    private fun source(record: HealthObservation) = getString(healthRecordSourceResource(record.source))
}

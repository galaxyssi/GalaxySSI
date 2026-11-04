package com.galaxyssi.chat

import android.app.Activity
import android.app.AlertDialog
import android.app.DatePickerDialog
import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.View
import android.widget.CheckBox
import android.widget.LinearLayout
import android.widget.RadioButton
import android.widget.RadioGroup
import android.widget.ScrollView
import android.widget.Toast
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.concurrent.Executors

class HealthRecordExportActivity : Activity() {
    private val ui by lazy { HealthCenterViews(this) }; private val worker = Executors.newSingleThreadExecutor(); private val main = Handler(Looper.getMainLooper())
    private val fixture by lazy {
        intent.getStringExtra("health_record_export_test_id").orEmpty().takeIf { BuildConfig.DEBUG && HealthProfilePolicy.uuid(it) }
    }
    private val database get() = fixture?.let { "health-record-export-test-$it.db" } ?: "health_record_exports_v1.db"
    private fun openStore() = fixture?.let {
        HealthRecordExportStore(applicationContext, database, java.io.File(cacheDir, "health-record-export-test-$it"))
    } ?: HealthRecordExportStore(applicationContext)
    private lateinit var body: LinearLayout; private var mode = "configure"; private var sessionBack = "configure"; private var id = ""; private var active = false; private var generation = 0
    private var scope = HealthRecordExportScope(); private var dialog: AlertDialog? = null; private var saving = false; private var starting = false; private var mutating = false
    private var querying = false; private var dirty = false; private var itemCursor = 0L; private val itemPrevious = arrayListOf<Long>()
    private var showAttachments = false
    private var historyCursor: Pair<Long, String>? = null; private val historyPrevious = arrayListOf<Pair<Long, String>?>()
    private var workName = ""; private var workUpdates: androidx.lifecycle.LiveData<List<androidx.work.WorkInfo>>? = null
    private val workObserver = androidx.lifecycle.Observer<List<androidx.work.WorkInfo>> { load() }
    private val observer = object : android.database.ContentObserver(main) { override fun onChange(selfChange: Boolean) { if (mode != "configure") load() } }
    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        scope = state?.getString("scope")?.let { runCatching { HealthRecordExportScope.from(org.json.JSONObject(it)) }.getOrNull() } ?: HealthRecordExportScope(
            originalId = intent.getStringExtra("health_original").orEmpty(), metrics = intent.getStringExtra("health_metric")?.let { setOf(HealthMetric.valueOf(it)) } ?: HealthMetric.entries.toSet())
        id = state?.getString("id") ?: intent.getStringExtra("record_export").orEmpty()
        mode = state?.getString("mode") ?: if (id.isNotBlank()) "session" else if (intent.getBooleanExtra("export_history", false)) "history" else "configure"
        sessionBack = state?.getString("session_back") ?: if (id.isNotBlank()) "finish" else "configure"
        itemCursor = state?.getLong("item_cursor") ?: 0; itemPrevious.addAll(state?.getLongArray("item_previous")?.toList().orEmpty())
        showAttachments = state?.getBoolean("show_attachments") ?: false
        fun cursor(raw: String?) = raw?.takeIf { it.isNotEmpty() }?.split('|', limit = 2)?.let { it[0].toLong() to it[1] }
        historyCursor = cursor(state?.getString("history_cursor")); historyPrevious.addAll(state?.getStringArrayList("history_previous")?.map(::cursor).orEmpty())
        window.statusBarColor = getColor(R.color.page_bg); window.navigationBarColor = getColor(R.color.page_bg)
        if (android.os.Build.VERSION.SDK_INT >= 33) setRecentsScreenshotEnabled(false)
        val root = ui.column().apply { setBackgroundColor(getColor(R.color.page_bg)) }
        root.addView(ui.line().apply {
            addView(ui.icon(R.drawable.ic_navigation_back, R.string.health_back) { back() })
            addView(ui.text(getString(R.string.health_export_records), 19f, bold = true).apply {
                gravity = Gravity.CENTER; maxLines = 1; setAutoSizeTextTypeUniformWithConfiguration(12, 19, 1, android.util.TypedValue.COMPLEX_UNIT_SP)
            }, LinearLayout.LayoutParams(0, -1, 1f))
            addView(ui.icon(R.drawable.ic_health_grid, R.string.health_functions) { startActivity(Intent(this@HealthRecordExportActivity, HealthCenterActivity::class.java).putExtra("health_functions", true)) })
        }, LinearLayout.LayoutParams(-1, ui.dp(56)))
        body = ui.column(); root.addView(body, LinearLayout.LayoutParams(-1, 0, 1f)); setContentView(root)
    }
    override fun onStart() { super.onStart(); active = true; contentResolver.registerContentObserver(HealthRecordExportStore.changes(this, database), false, observer); show() }
    override fun onStop() {
        active = false; generation++; contentResolver.unregisterContentObserver(observer); watch(""); dialog?.dismiss(); dialog = null; body.removeAllViews(); super.onStop()
    }
    override fun onDestroy() { worker.shutdown(); super.onDestroy() }
    override fun onSaveInstanceState(out: Bundle) {
        out.putString("scope", scope.json().toString()); out.putString("mode", mode); out.putString("session_back", sessionBack); out.putString("id", id); out.putLong("item_cursor", itemCursor)
        fun cursor(value: Pair<Long, String>?) = value?.let { "${it.first}|${it.second}" }.orEmpty()
        out.putString("history_cursor", cursor(historyCursor)); out.putStringArrayList("history_previous", ArrayList(historyPrevious.map(::cursor)))
        out.putLongArray("item_previous", itemPrevious.toLongArray())
        out.putBoolean("show_attachments", showAttachments)
        super.onSaveInstanceState(out)
    }
    @Deprecated("Native back callback") override fun onBackPressed() = back()
    private fun back() { if (mode == "session" && sessionBack != "finish") { mode = sessionBack; generation++; show() } else finish() }
    private fun show() { watch(""); if (mode == "configure") configure() else load() }
    private fun content(): LinearLayout {
        body.removeAllViews(); val content = ui.column().apply { setPadding(ui.dp(16), ui.dp(16), ui.dp(16), ui.dp(24)) }
        body.addView(ScrollView(this).apply { addView(content) }, LinearLayout.LayoutParams(-1, 0, 1f)); return content
    }
    private fun configure() {
        val content = content()
        content.addView(ui.text(getString(R.string.health_export_self), 15f, muted = true))
        ui.add(content, ui.row(getString(R.string.health_export_period), period(scope)) { dates() }, 8)
        ui.add(content, ui.row(getString(R.string.health_export_metrics), if (scope.metrics.size == HealthMetric.entries.size) getString(R.string.health_export_all_metrics) else scope.metrics.sortedBy { it.ordinal }.joinToString(" / ") { getString(it.titleResource()) }) { metrics() })
        if (scope.originalId.isNotEmpty()) ui.add(content, ui.row(getString(R.string.health_export_current_original), scope.originalId.take(8)) {
            dialog = AlertDialog.Builder(this).setItems(arrayOf(getString(R.string.health_export_all_sources), getString(R.string.common_cancel))) { _, which -> if (which == 0) { scope = scope.copy(originalId = ""); configure() } }.show()
        })
        ui.add(content, ui.text(getString(R.string.health_export_format), 13f, muted = true), 12)
        ui.add(content, RadioGroup(this).apply {
            orientation = RadioGroup.HORIZONTAL; background = ui.background(getColor(R.color.button_soft), radius = 8)
            HealthRecordExportFormat.entries.forEach { format -> addView(RadioButton(this@HealthRecordExportActivity).apply {
                id = View.generateViewId(); text = format.name; gravity = Gravity.CENTER; buttonDrawable = null; minimumHeight = ui.dp(48); isChecked = scope.format == format; tag = "health-export-format-${format.name}"
                background = android.graphics.drawable.StateListDrawable().apply {
                    addState(intArrayOf(android.R.attr.state_checked), ui.background(getColor(R.color.surface_bg), radius = 6)); addState(intArrayOf(), ui.background(android.graphics.Color.TRANSPARENT, radius = 6))
                }
                setOnClickListener { scope = scope.copy(format = format) }
            }, RadioGroup.LayoutParams(0, -2, 1f)) }
        }, 8)
        ui.add(content, CheckBox(this).apply { text = getString(R.string.health_export_annotations); textSize = 14f; isChecked = scope.annotations; tag = "health-export-annotations"; setOnCheckedChangeListener { _, checked -> scope = scope.copy(annotations = checked) } }, 16)
        val packageHint = ui.text("", 13f, muted = true).apply { tag = "health-export-packaging" }
        fun packaging() = packageHint.setText(if (scope.bundlesOriginals) R.string.health_export_bundle_packaging else R.string.health_export_no_originals)
        ui.add(content, CheckBox(this).apply {
            text = getString(R.string.health_export_camera_originals); textSize = 14f; isChecked = scope.cameraOriginals
            tag = "health-export-camera-originals"
            setOnCheckedChangeListener { _, checked -> scope = scope.copy(cameraOriginals = checked); packaging() }
        })
        ui.add(content, CheckBox(this).apply {
            text = getString(R.string.health_export_uploaded_originals); textSize = 14f; isChecked = scope.uploadedOriginals
            tag = "health-export-uploaded-originals"
            setOnCheckedChangeListener { _, checked -> scope = scope.copy(uploadedOriginals = checked); packaging() }
        })
        packaging()
        ui.add(content, packageHint, 12)
        ui.add(content, ui.row(getString(R.string.health_library_export)) { startActivity(Intent(this, HealthOriginalLibraryActivity::class.java)) })
        ui.add(content, ui.command(R.string.health_export_preview) { prepare() }.apply { tag = "health-export-preview" }, 20)
        ui.add(content, ui.row(getString(R.string.health_export_history)) { mode = "history"; historyCursor = null; historyPrevious.clear(); load() }, 16)
    }
    private fun prepare() {
        if (starting) return; starting = true
        val requested = scope; val token = generation
        worker.execute {
            val result = runCatching { openStore().use { exports -> exports.create(requested).also { HealthRecordExportScheduler.enqueue(applicationContext, it) } } }
            main.post { starting = false; if (active && token == generation) result.fold({ session -> id = session.id; sessionBack = "configure"; mode = "session"; resetPreview(); load() }, { error() }) }
        }
    }
    private fun load() {
        if (!active || mode == "configure" || saving) return
        if (querying) { dirty = true; return }; querying = true
        val token = generation; val selected = id; val currentMode = mode; val after = itemCursor; val historyAfter = historyCursor
        val attachmentPage = showAttachments
        worker.execute {
            val result = runCatching { openStore().use { exports ->
                if (currentMode == "history") Snapshot(history = exports.history(historyAfter)) else {
                    var session = requireNotNull(exports.session(selected))
                    if (session.state in listOf(HealthRecordExportState.PREPARING, HealthRecordExportState.QUEUED, HealthRecordExportState.GENERATING)) {
                        val states = androidx.work.WorkManager.getInstance(applicationContext).getWorkInfosForUniqueWork(HealthRecordExportScheduler.workName(session)).get().map { it.state }
                        if (HealthOriginalExportScheduler.terminal(states)) { exports.externalFailure(selected, session.dispatch, "worker_failed"); session = requireNotNull(exports.session(selected)) }
                    }
                    val review = session.state == HealthRecordExportState.REVIEW
                    Snapshot(session = session, items = if (review && !attachmentPage) exports.items(selected, after) else emptyList(),
                        attachments = if (review && attachmentPage && session.scope.bundlesOriginals) exports.attachments(selected, after) else emptyList())
                }
            } }
            main.post { querying = false
                if (active && token == generation && currentMode == mode) result.fold({
                    if (currentMode == "history") history(it.history) else session(requireNotNull(it.session), it.items, it.attachments)
                }, { error() })
                if (active && (dirty || token != generation)) { dirty = false; load() }
            }
        }
    }
    private fun history(values: List<HealthRecordExportSession>) {
        watch(""); val content = content()
        content.addView(ui.text(getString(R.string.health_export_history), 20f, bold = true))
        if (values.isEmpty()) ui.add(content, ui.text(getString(R.string.health_export_no_history), 15f, muted = true), 16)
        values.take(30).forEach { s -> ui.add(content, ui.row("${formatLabel(s.scope)} \u00b7 ${getString(stateTitle(s))}", "${Instant.ofEpochMilli(s.createdAt).atZone(ZoneId.of(s.scope.zone)).toLocalDate()} \u00b7 ${getString(R.string.health_record_count, s.count)}") {
            id = s.id; resetPreview(); sessionBack = "history"; mode = "session"; generation++; load()
        }, 8) }
        if (historyPrevious.isNotEmpty()) ui.add(content, ui.command(R.string.health_previous_page) { historyCursor = historyPrevious.removeAt(historyPrevious.lastIndex); load() }, 16)
        if (values.size > 30) ui.add(content, ui.command(R.string.health_next_page) { historyPrevious += historyCursor; historyCursor = values[29].let { it.createdAt to it.id }; load() }, 16)
        ui.add(content, ui.command(R.string.health_export_new) { mode = "configure"; configure() }, 20)
    }
    private fun session(s: HealthRecordExportSession, items: List<HealthRecordExportItem>, attachments: List<HealthRecordExportAttachment>) {
        watch(if (s.state in listOf(HealthRecordExportState.PREPARING, HealthRecordExportState.QUEUED, HealthRecordExportState.GENERATING)) HealthRecordExportScheduler.workName(s) else "")
        val content = content(); content.addView(ui.text(getString(stateTitle(s)), 20f, bold = true).apply { tag = "health-record-export-state" })
        ui.add(content, ui.text("${formatLabel(s.scope)} \u00b7 ${period(s.scope)}", 13f, muted = true), 8)
        ui.add(content, ui.text(getString(R.string.health_export_summary, s.count, s.rows), 15f), 12)
        val packaging = if (s.scope.bundlesOriginals) R.string.health_export_bundle_packaging else R.string.health_export_no_originals
        ui.add(content, ui.text(getString(packaging), 13f, muted = true), 8)
        if (s.scope.bundlesOriginals && s.state in listOf(HealthRecordExportState.REVIEW, HealthRecordExportState.GENERATED, HealthRecordExportState.SAVED)) {
            ui.add(content, ui.text(getString(R.string.health_export_bundle_count, s.attachmentAvailable), 14f), 8)
            if (s.attachmentWarnings > 0)
                ui.add(content, ui.text(getString(R.string.health_export_bundle_missing, s.attachmentWarnings), 14f), 8)
        }
        when (s.state) {
            HealthRecordExportState.PREPARING, HealthRecordExportState.QUEUED, HealthRecordExportState.GENERATING -> {
                ui.add(content, ui.text(getString(if (s.phase == "prepare") R.string.health_export_scan_progress else R.string.health_export_write_progress, if (s.phase == "prepare") s.scanned else s.completed), 14f), 16)
                ui.add(content, ui.command(R.string.common_cancel) { mutate { it.cancel(s.id) } }, 16)
            }
            HealthRecordExportState.REVIEW -> {
                val estimate = s.attachmentBytes + s.estimatedBytes * (if (s.scope.format == HealthRecordExportFormat.CSV) 2 else 1) +
                    s.attachmentCount * 512 + 16_384
                ui.add(content, ui.text(getString(R.string.health_export_estimate, android.text.format.Formatter.formatShortFileSize(this, estimate)), 13f, muted = true), 12)
                ui.add(content, ui.text(getString(R.string.health_export_snapshot_time, Instant.ofEpochMilli(s.preparedAt).atZone(ZoneId.of(s.scope.zone)).toLocalDateTime().toString()), 12f, muted = true), 6)
                if (!s.scope.bundlesOriginals && s.sourceWarnings > 0) ui.add(content, ui.text(getString(R.string.health_export_source_warnings, s.sourceWarnings), 14f), 12)
                if (s.scope.bundlesOriginals) ui.add(content, ui.row(getString(if (showAttachments) R.string.health_export_records else R.string.health_export_bundle_manifest)) {
                    showAttachments = !showAttachments; itemCursor = 0; itemPrevious.clear(); generation++; load()
                }.apply { tag = "health-export-manifest" }, 8)
                if (showAttachments) attachments.take(30).forEach { item ->
                    val name = item.original?.name ?: item.originalId.take(8)
                    val detail = item.original?.let { android.text.format.Formatter.formatShortFileSize(this, it.size) }
                        ?: getString(when (item.status) {
                            HealthExportSourceStatus.NOT_SELECTED -> R.string.health_export_attachment_not_selected
                            HealthExportSourceStatus.MISSING -> R.string.health_export_attachment_missing
                            else -> R.string.health_export_attachment_unreadable
                        })
                    ui.add(content, ui.text("$name \u00b7 $detail", 14f), 6)
                } else items.take(30).forEach { item -> ui.add(content, ui.row(getString(item.record.draft.metric.titleResource()), healthDisplayValue(item.record.draft)) {
                    startActivity(Intent(this, HealthRecordRevisionActivity::class.java).putExtra("health_record", item.record.id).putExtra("health_revision", item.record.revision))
                }, 6) }
                if (itemPrevious.isNotEmpty()) ui.add(content, ui.command(R.string.health_previous_page) { itemCursor = itemPrevious.removeAt(itemPrevious.lastIndex); load() }, 12)
                val next = if (showAttachments) attachments.takeIf { it.size > 30 }?.get(29)?.sequence else items.takeIf { it.size > 30 }?.get(29)?.sequence
                if (next != null) ui.add(content, ui.command(R.string.health_next_page) { itemPrevious += itemCursor; itemCursor = next; load() }, 12)
                consent(content, s)
            }
            HealthRecordExportState.GENERATED, HealthRecordExportState.SAVED -> {
                ui.add(content, ui.text(android.text.format.Formatter.formatShortFileSize(this, s.artifactBytes), 16f), 16)
                ui.add(content, ui.text(s.sha256, 11f, muted = true).apply { setTextIsSelectable(true) }, 8)
                ui.add(content, ui.text(getString(R.string.health_export_plain_warning), 14f, muted = true), 12)
                ui.add(content, ui.command(R.string.health_export_save) {
                    startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE).setType(s.scope.mime)
                        .putExtra(Intent.EXTRA_TITLE, "GalaxySSI-records-${s.createdAt}.${s.scope.extension}"), SAVE)
                }, 16)
            }
            else -> {
                ui.add(content, ui.text(getString(when (s.error) {
                    "records_changed" -> R.string.health_export_records_changed
                    "no_records" -> R.string.health_export_no_records
                    "background_unavailable" -> R.string.health_library_background_failed
                    "originals_changed" -> R.string.health_export_bundle_changed
                    else -> R.string.health_export_failed
                }), 14f), 16)
                if (s.state == HealthRecordExportState.FAILED && s.phase == "generate" && s.error != "originals_changed") consent(content, s)
                ui.add(content, ui.command(R.string.health_export_repreview) {
                    resetPreview()
                    mutate { exports -> val next = exports.retryPreparation(s.id); HealthRecordExportScheduler.enqueue(applicationContext, next) }
                }, 16)
            }
        }
        ui.add(content, ui.row(getString(R.string.health_export_history)) { mode = "history"; generation++; show() }, 20)
    }
    private fun formatLabel(s: HealthRecordExportScope) = if (s.bundlesOriginals) getString(R.string.health_export_bundle_format, s.format.name) else s.format.name
    private fun resetPreview() { itemCursor = 0; itemPrevious.clear(); showAttachments = false }
    private fun consent(content: LinearLayout, s: HealthRecordExportSession) {
        val check = CheckBox(this).apply { text = getString(R.string.health_export_plain_consent); textSize = 14f; isSaveEnabled = false; tag = "health-record-export-consent" }
        ui.add(content, check, 16)
        ui.add(content, ui.command(R.string.health_export_generate) {
            if (!check.isChecked) Toast.makeText(this, R.string.health_library_consent_required, Toast.LENGTH_LONG).show()
            else mutate { exports -> HealthRecordExportScheduler.enqueue(applicationContext, exports.queue(s.id)) }
        }.apply { tag = "health-record-export-generate" }, 12)
    }
    private fun stateTitle(s: HealthRecordExportSession): Int = when (s.state) {
        HealthRecordExportState.PREPARING -> R.string.health_export_preparing; HealthRecordExportState.REVIEW -> R.string.health_export_confirm
        HealthRecordExportState.QUEUED, HealthRecordExportState.GENERATING -> R.string.health_export_generating
        HealthRecordExportState.GENERATED -> R.string.health_library_generated; HealthRecordExportState.SAVED -> R.string.health_library_saved
        HealthRecordExportState.CANCELLED -> R.string.health_import_cancelled; else -> R.string.health_export_failed
    }
    private fun mutate(action: (HealthRecordExportStore) -> Any) { if (mutating) return; mutating = true; worker.execute {
        val result = runCatching { openStore().use(action) }
        main.post { mutating = false; if (active) { if (result.isFailure) Toast.makeText(this, R.string.health_storage_error, Toast.LENGTH_LONG).show(); load() } }
    } }
    private fun watch(name: String) {
        if (name == workName) return; workUpdates?.removeObserver(workObserver); workUpdates = null; workName = name
        if (name.isNotEmpty() && active) workUpdates = androidx.work.WorkManager.getInstance(applicationContext).getWorkInfosForUniqueWorkLiveData(name).also { it.observeForever(workObserver) }
    }
    private fun error() { val content = content(); content.addView(ui.text(getString(R.string.health_storage_error))); ui.add(content, ui.command(R.string.common_retry) { show() }, 12) }
    private fun period(s: HealthRecordExportScope) = if (s.from == 0L && s.until == Long.MAX_VALUE) getString(R.string.health_library_all_dates) else {
        val zone = ZoneId.of(s.zone); "${Instant.ofEpochMilli(s.from).atZone(zone).toLocalDate()} - ${Instant.ofEpochMilli(s.until - 1).atZone(zone).toLocalDate()} \u00b7 ${s.zone}"
    }
    private fun dates() {
        dialog = AlertDialog.Builder(this).setTitle(R.string.health_export_period).setItems(arrayOf(getString(R.string.health_library_all_dates), getString(R.string.health_trend_custom))) { _, which ->
            if (which == 0) { scope = scope.copy(from = 0, until = Long.MAX_VALUE); configure() } else {
                val zone = ZoneId.of(scope.zone); val today = LocalDate.now(zone)
                fun pick(initial: LocalDate, title: Int, chosen: (LocalDate) -> Unit) {
                    dialog = DatePickerDialog(this, { _, y, m, d -> chosen(LocalDate.of(y, m + 1, d)) }, initial.year, initial.monthValue - 1, initial.dayOfMonth).apply { setTitle(title); datePicker.minDate = 0; datePicker.maxDate = System.currentTimeMillis(); show() }
                }
                pick(today.minusDays(29), R.string.health_trend_from) { first -> pick(today, R.string.health_trend_until) { last ->
                    if (last.isBefore(first)) Toast.makeText(this, R.string.health_trend_invalid_dates, Toast.LENGTH_LONG).show()
                    else { val times = HealthRecordExportScope.dates(first, last, zone); scope = scope.copy(from = times.first, until = times.second); configure() }
                } }
            }
        }.setNegativeButton(R.string.common_cancel, null).show()
    }
    private fun metrics() {
        val definitions = HealthMetric.entries; val selected = scope.metrics.toMutableSet()
        dialog = AlertDialog.Builder(this).setTitle(R.string.health_export_metrics).setMultiChoiceItems(definitions.map { getString(it.titleResource()) }.toTypedArray(), definitions.map { it in selected }.toBooleanArray()) { _, index, checked ->
            if (checked) selected += definitions[index] else selected -= definitions[index]
        }.setPositiveButton(android.R.string.ok, null).setNegativeButton(R.string.common_cancel, null).create().also { choice ->
            choice.setOnShowListener { choice.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener {
                if (selected.isEmpty()) Toast.makeText(this, R.string.health_export_choose_metric, Toast.LENGTH_LONG).show()
                else { scope = scope.copy(metrics = selected.toSet()); choice.dismiss(); configure() }
            } }; choice.show()
        }
    }
    @Deprecated("Native document result") override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != SAVE || resultCode != RESULT_OK) return; val uri = data?.data ?: return
        val selected = id; saving = true; content().addView(ui.text(getString(R.string.health_export_saving)))
        worker.execute {
            val result = runCatching { openStore().use { exports ->
                val session = requireNotNull(exports.session(selected))
                HealthPrivacyStore.track(applicationContext, HealthAccessScope.records(session)) {
                    HealthRecordExportPipeline.saveVerified(exports, session,
                        { contentResolver.openOutputStream(uri, "wt") ?: error("Export destination unavailable") },
                        { contentResolver.openInputStream(uri) ?: error("Export read-back unavailable") },
                        { android.provider.DocumentsContract.deleteDocument(contentResolver, uri) })
                }
            } }
            main.post { saving = false; if (active) { if (result.isFailure) Toast.makeText(this, R.string.health_import_save_failed, Toast.LENGTH_LONG).show(); load() } }
        }
    }
    private data class Snapshot(val history: List<HealthRecordExportSession> = emptyList(), val session: HealthRecordExportSession? = null,
        val items: List<HealthRecordExportItem> = emptyList(), val attachments: List<HealthRecordExportAttachment> = emptyList())
    companion object { private const val SAVE = 92 }
}

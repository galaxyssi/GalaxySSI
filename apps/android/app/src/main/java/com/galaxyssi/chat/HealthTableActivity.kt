package com.galaxyssi.chat

import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.database.ContentObserver
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.widget.CheckBox
import android.widget.EditText
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import java.util.UUID
import java.util.concurrent.Executors

/** Native column mapping and paged source review, with no health values in saved instance state. */
class HealthTableActivity : Activity() {
    private val ui by lazy { HealthCenterViews(this) }
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private lateinit var body: LinearLayout
    private var id = ""
    private var active = false
    private var querying = false
    private var dirty = false
    private var generation = 0
    private var after = 0L
    private var renderedAfter = -1L
    private val previous = arrayListOf<Long>()
    private var dialog: AlertDialog? = null
    private var operationKey = ""
    private var operationProgress: TextView? = null
    private val observer = object : ContentObserver(main) {
        override fun onChange(selfChange: Boolean) = refresh()
        override fun onChange(selfChange: Boolean, uri: Uri?) = refresh()
    }
    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        id = state?.getString("id") ?: intent.getStringExtra("health_table").orEmpty()
        if (runCatching { UUID.fromString(id).toString() == id }.getOrDefault(false).not()) { finish(); return }
        after = state?.getLong("after") ?: 0
        previous.addAll(state?.getLongArray("previous")?.toList().orEmpty())
        window.statusBarColor = getColor(R.color.page_bg); window.navigationBarColor = getColor(R.color.page_bg)
        if (android.os.Build.VERSION.SDK_INT >= 33) setRecentsScreenshotEnabled(false)
        val root = ui.column().apply { setBackgroundColor(getColor(R.color.page_bg)) }
        root.addView(ui.line().apply {
            addView(ui.icon(R.drawable.ic_navigation_back, R.string.health_back) { finish() })
            addView(ui.text(getString(R.string.health_table_title), 19f, bold = true).apply { gravity = Gravity.CENTER }, LinearLayout.LayoutParams(0, -2, 1f))
            addView(ui.icon(R.drawable.ic_health_grid, R.string.health_functions) {
                startActivity(Intent(this@HealthTableActivity, HealthCenterActivity::class.java).putExtra("health_functions", true))
            })
        }, LinearLayout.LayoutParams(-1, ui.dp(56)))
        body = ui.column(); root.addView(body, LinearLayout.LayoutParams(-1, 0, 1f)); setContentView(root)
    }
    override fun onStart() {
        super.onStart(); if (!::body.isInitialized) return
        active = true; contentResolver.registerContentObserver(HealthTableScheduler.changes(this), false, observer); refresh()
    }
    override fun onStop() {
        active = false; generation++; dialog?.dismiss(); dialog = null
        operationKey = ""; operationProgress = null
        if (::body.isInitialized) { contentResolver.unregisterContentObserver(observer); body.removeAllViews() }
        super.onStop()
    }
    override fun onDestroy() { worker.shutdown(); super.onDestroy() }
    override fun onSaveInstanceState(out: Bundle) {
        out.putString("id", id); out.putLong("after", after); out.putLongArray("previous", previous.toLongArray())
        super.onSaveInstanceState(out)
    }
    private fun refresh() {
        if (!active) return
        if (querying) { dirty = true; return }
        querying = true; val token = generation; val cursor = after
        worker.execute {
            val result = runCatching { HealthTableStore(applicationContext).use { store ->
                val batch = requireNotNull(store.batch(id))
                Triple(batch, if (batch.state.working) emptyList() else store.page(id, cursor),
                    if (batch.state.working || batch.state in listOf(HealthTableState.MAPPING, HealthTableState.SHEET_SELECTION)) HealthTableCounts(emptyMap()) else store.counts(id))
            } }
            main.post {
                querying = false
                if (active && token == generation) result.fold({ render(it.first, it.second, it.third) }, { failure() })
                if (active && (dirty || token != generation)) { dirty = false; refresh() }
            }
        }
    }
    private fun change(action: (HealthTableStore) -> Unit, enqueue: Boolean = false, retry: Boolean = false) {
        worker.execute {
            val result = runCatching {
                HealthTableStore(applicationContext).use(action)
                if (enqueue) HealthTableScheduler.enqueue(applicationContext, id, retry)
                HealthTableScheduler.notify(applicationContext)
            }
            main.post { if (active) { if (result.isFailure) failure(); refresh() } }
        }
    }
    private fun mapping(batch: HealthTableBatch, value: HealthTableMapping) = change({ it.mapping(id, batch.mappingRevision, value, false) })
    private fun choose(title: Int, values: List<String>, selected: String, apply: (Int) -> Unit) {
        dialog?.dismiss()
        dialog = AlertDialog.Builder(this).setTitle(title).setSingleChoiceItems(values.toTypedArray(), values.indexOf(selected)) { value, index ->
            value.dismiss(); dialog = null; apply(index)
        }.setNegativeButton(R.string.common_cancel, null).show()
    }
    private fun column(batch: HealthTableBatch, current: String, apply: (String) -> HealthTableMapping) {
        val values = listOf(getString(R.string.health_table_unmapped)) + batch.headers
        choose(R.string.health_table_column, values, current.ifBlank { values.first() }) { index ->
            mapping(batch, apply(if (index == 0) "" else batch.headers[index - 1]))
        }
    }
    private fun render(batch: HealthTableBatch, rows: List<HealthTablePreview>, counts: HealthTableCounts) {
        val nextOperation = if (batch.state.working) "${batch.state}|${batch.mappingRevision}|${batch.error}" else ""
        if (nextOperation.isNotBlank() && nextOperation == operationKey && operationProgress != null) {
            operationProgress?.text = healthTableTaskLabel(this, batch.copy(error = "")); return
        }
        operationKey = nextOperation; operationProgress = null
        val oldScroll = if (renderedAfter == after) (body.getChildAt(0) as? ScrollView)?.scrollY ?: 0 else 0
        renderedAfter = after
        body.removeAllViews()
        val content = ui.column().apply { setPadding(ui.dp(16), ui.dp(16), ui.dp(16), ui.dp(24)) }
        val scroll = ScrollView(this).apply { addView(content) }; body.addView(scroll, LinearLayout.LayoutParams(-1, 0, 1f))
        val footer = ui.column().apply { setPadding(ui.dp(16), ui.dp(8), ui.dp(16), ui.dp(16)); setBackgroundColor(getColor(R.color.surface_bg)) }
        ui.add(content, ui.card().apply {
            addView(ui.line().apply {
                addView(ImageView(this@HealthTableActivity).apply {
                    setImageResource(R.drawable.ic_rich_file); imageTintList = android.content.res.ColorStateList.valueOf(0xff169d70.toInt())
                    background = ui.background(0xffe5f6ef.toInt(), radius = 12); setPadding(ui.dp(12), ui.dp(12), ui.dp(12), ui.dp(12))
                    importantForAccessibility = android.view.View.IMPORTANT_FOR_ACCESSIBILITY_NO
                }, LinearLayout.LayoutParams(ui.dp(48), ui.dp(48)))
                addView(ui.column().apply {
                    addView(ui.text(batch.name, 18f, bold = true))
                    addView(ui.text(getString(R.string.health_table_file_summary, batch.format.uppercase(java.util.Locale.ROOT), batch.rows), 13f, muted = true))
                }, LinearLayout.LayoutParams(0, -2, 1f).apply { marginStart = ui.dp(12) })
            })
            addView(ui.row(getString(R.string.health_view_original)) {
                startActivity(Intent(this@HealthTableActivity, HealthCaptureActivity::class.java).putExtra("original", batch.originalId))
            })
            if (batch.format == "xlsx") {
                val selected = batch.sheets.singleOrNull { it.index == batch.sheetIndex }
                val editableSheet = batch.state in listOf(HealthTableState.SHEET_SELECTION, HealthTableState.MAPPING, HealthTableState.READY)
                addView(ui.row(getString(R.string.health_xlsx_sheet), selected?.name ?: getString(R.string.health_xlsx_choose_sheet)) {
                    if (editableSheet) choose(R.string.health_xlsx_sheet, batch.sheets.map { sheetLabel(it) }, selected?.let(::sheetLabel).orEmpty()) { index ->
                        configureSheet(batch, batch.sheets[index].index, batch.headerRow)
                    }
                }.apply { isEnabled = editableSheet })
                addView(ui.row(getString(R.string.health_xlsx_header_row), batch.headerRow.toString()) {
                    if (editableSheet) {
                        val edit = EditText(this@HealthTableActivity).apply { inputType = android.text.InputType.TYPE_CLASS_NUMBER; setText(batch.headerRow.toString()) }
                        dialog = AlertDialog.Builder(this@HealthTableActivity).setTitle(R.string.health_xlsx_header_row).setView(edit)
                            .setNegativeButton(R.string.common_cancel, null).setPositiveButton(R.string.health_table_apply) { _, _ ->
                                val row = edit.text.toString().toIntOrNull()
                                if (row != null && row in 1..1_048_576) configureSheet(batch, batch.sheetIndex, row)
                                else Toast.makeText(this@HealthTableActivity, R.string.health_xlsx_header_error, Toast.LENGTH_LONG).show()
                            }.show()
                    }
                }.apply { isEnabled = editableSheet })
                addView(ui.text(getString(R.string.health_xlsx_epoch, if (batch.date1904) 1904 else 1900), 12f, muted = true))
            }
        })
        if (batch.state == HealthTableState.SHEET_SELECTION) {
            ui.add(content, ui.text(getString(R.string.health_xlsx_selection_notice), 14f, muted = true), 16)
            ui.add(footer, ui.command(R.string.health_xlsx_load_sheet) {
                change({ it.configureSheet(id, batch.mappingRevision, batch.sheetIndex, batch.headerRow, true) }, true)
            }.apply { isEnabled = batch.sheetIndex >= 0; alpha = if (isEnabled) 1f else .45f })
            body.addView(footer, LinearLayout.LayoutParams(-1, -2)); return
        }
        if (batch.state == HealthTableState.READING && batch.format == "xlsx") {
            ui.add(content, ui.row(getString(R.string.common_cancel)) { change({
                it.cancelReading(id, batch.mappingRevision); HealthTableScheduler.cancelReading(applicationContext, id, batch.mappingRevision)
            }) })
        }
        val editable = batch.state in listOf(HealthTableState.MAPPING, HealthTableState.READY)
        if (editable) renderMapping(content, batch)
        if (batch.state.working) {
            operationProgress = ui.text(healthTableTaskLabel(this, batch.copy(error = "")), 15f, bold = true)
            ui.add(content, requireNotNull(operationProgress), 16)
            if (batch.state == HealthTableState.VALIDATING) ui.add(content, ui.row(getString(R.string.common_cancel)) { change({ it.pause(id) }) })
        }
        if (batch.error.isNotBlank()) {
            ui.add(content, ui.text(getString(healthXlsxErrorResource(batch.error)), 14f), 16)
            ui.add(content, ui.command(R.string.common_retry) { change({}, true, true) }, 12)
        }
        if (batch.state.working) return
        ui.add(content, ui.text(getString(R.string.health_table_preview), 19f, bold = true), 20)
        if (batch.state != HealthTableState.MAPPING) {
            ui.add(content, ui.text(getString(R.string.health_table_counts, counts[HealthTableRowState.VALID], counts[HealthTableRowState.DUPLICATE],
                counts[HealthTableRowState.MISSING], counts[HealthTableRowState.INVALID]), 13f, muted = true), 8)
        }
        ui.add(content, ui.card().apply {
            addView(previewLine(getString(R.string.health_table_time), getString(R.string.health_table_values), getString(R.string.health_table_status), true))
            rows.forEach { preview ->
                addView(android.view.View(this@HealthTableActivity).apply { setBackgroundColor(getColor(R.color.separator)) }, LinearLayout.LayoutParams(-1, ui.dp(1)))
                val draft = HealthTablePolicy.evaluate(batch, preview.row).draft
                val values = batch.mapping.metric.fields.mapNotNull { field ->
                    val column = batch.mapping.columns[field].orEmpty()
                    if (column.isBlank()) null else (draft?.values?.get(field) ?: preview.row.cells[column]).orEmpty().ifBlank { "\u2014" }
                }.joinToString(" / ")
                val time = draft?.let { interpretedTime(it, batch) } ?: preview.row.cells[batch.mapping.timeColumn].orEmpty().ifBlank { "\u2014" }
                addView(previewLine(time, values,
                    getString(rowState(preview.state)), state = preview.state).apply {
                    isFocusable = true; contentDescription = getString(R.string.health_table_row_status, preview.row.number, getString(rowState(preview.state)))
                    setOnClickListener { showRow(preview, batch) }
                })
            }
        }, 10)
        if (previous.isNotEmpty()) ui.add(content, ui.command(R.string.health_previous_page) {
            after = previous.removeAt(previous.lastIndex); generation++; refresh()
        }, 14)
        if (rows.lastOrNull()?.row?.number?.let { it < batch.rows } == true) ui.add(content, ui.command(R.string.health_next_page) {
            previous += after; after = rows.last().row.number; generation++; refresh()
        }, 14)
        when (batch.state) {
            HealthTableState.MAPPING -> ui.add(footer, ui.command(R.string.health_table_validate) {
                if (!batch.mapping.valid(batch.headers)) Toast.makeText(this, R.string.health_table_mapping_required, Toast.LENGTH_LONG).show()
                else change({ it.mapping(id, batch.mappingRevision, batch.mapping, true) }, true)
            }, 20)
            HealthTableState.READY -> {
                ui.add(content, ui.text(getString(R.string.health_table_skip_notice), 13f, muted = true), 16)
                val confirmed = CheckBox(this).apply { text = getString(R.string.health_confirm_source); setTextColor(getColor(R.color.text_primary)); textSize = 13f }
                ui.add(footer, confirmed)
                ui.add(footer, ui.command(R.string.health_table_save) {
                    if (!confirmed.isChecked) Toast.makeText(this, R.string.health_confirm_source_required, Toast.LENGTH_LONG).show()
                    else change({ it.confirmSave(id, batch.mappingRevision) }, true)
                }.apply { text = getString(R.string.health_table_save_count, counts[HealthTableRowState.VALID]); isEnabled = counts[HealthTableRowState.VALID] > 0; alpha = if (isEnabled) 1f else .45f }, 8)
            }
            HealthTableState.SAVED -> {
                ui.add(content, ui.text(getString(R.string.health_table_saved, counts[HealthTableRowState.SAVED]), 16f, bold = true), 20)
                ui.add(content, ui.row(getString(R.string.health_table_undo)) {
                    dialog = AlertDialog.Builder(this).setTitle(R.string.health_table_undo).setMessage(R.string.health_table_undo_notice)
                        .setNegativeButton(R.string.common_cancel, null).setPositiveButton(R.string.health_table_undo) { _, _ -> change({ it.undo(id) }, true) }.show()
                }, 10)
            }
            HealthTableState.UNDONE -> ui.add(content, ui.text(getString(R.string.health_table_undone,
                counts[HealthTableRowState.UNDONE], counts[HealthTableRowState.EDITED]), 16f, bold = true), 20)
            else -> Unit
        }
        if (footer.childCount > 0) body.addView(footer, LinearLayout.LayoutParams(-1, -2))
        scroll.post { if (active) scroll.scrollTo(0, oldScroll) }
    }
    private fun previewLine(time: String, values: String, status: String, heading: Boolean = false, state: HealthTableRowState? = null) = ui.line().apply {
        minimumHeight = ui.dp(if (heading) 40 else 58)
        fun cell(value: String, weight: Float) = addView(ui.text(value, if (heading) 12f else 13f, muted = heading).apply {
            maxLines = 2; ellipsize = android.text.TextUtils.TruncateAt.END; setPadding(0, ui.dp(6), ui.dp(8), ui.dp(6))
        }, LinearLayout.LayoutParams(0, -2, weight))
        cell(time, 1.1f); cell(values, 1f)
        addView(ui.text(status, 12f, muted = heading).apply {
            setPadding(ui.dp(6), ui.dp(5), ui.dp(6), ui.dp(5)); gravity = Gravity.CENTER; maxLines = 2
            if (!heading) background = ui.background(when (state) {
                HealthTableRowState.VALID, HealthTableRowState.SAVED -> 0xffe6f5ed.toInt()
                HealthTableRowState.MISSING, HealthTableRowState.INVALID -> 0xfffff1d9.toInt()
                else -> 0xfff0f3f3.toInt()
            }, radius = 6)
        }, LinearLayout.LayoutParams(0, -2, .85f))
    }
    private fun interpretedTime(draft: HealthDraft, batch: HealthTableBatch) = java.time.Instant.ofEpochMilli(draft.measuredAt)
        .atZone(java.time.ZoneId.of(batch.mapping.zone)).format(java.time.format.DateTimeFormatter.ofPattern("uuuu-MM-dd HH:mm", java.util.Locale.getDefault()))
    private fun showRow(preview: HealthTablePreview, batch: HealthTableBatch) {
        val content = ui.column().apply { setPadding(ui.dp(16), ui.dp(16), ui.dp(16), ui.dp(16)) }
        if (preview.issue.isNotBlank()) ui.add(content, ui.text(getString(rowIssue(preview.issue)), 14f), 8)
        HealthTablePolicy.evaluate(batch, preview.row).draft?.let { draft ->
            ui.add(content, ui.text(getString(R.string.health_table_interpreted_time, interpretedTime(draft, batch), batch.mapping.zone), 14f, bold = true), 8)
        }
        preview.row.cells.forEach { (key, value) ->
            val label = preview.row.addresses[key]?.let { "$it \u00b7 $key" } ?: key
            ui.add(content, ui.text("$label: $value", 14f).apply { setTextIsSelectable(true) }, 8)
        }
        preview.row.formulas.forEach { (key, formula) ->
            ui.add(content, ui.text(getString(R.string.health_xlsx_formula_detail, preview.row.addresses[key].orEmpty(), formula,
                preview.row.cells[key].orEmpty().ifBlank { getString(R.string.health_xlsx_no_cache) }), 13f, muted = true).apply { setTextIsSelectable(true) }, 10)
        }
        dialog = AlertDialog.Builder(this).setTitle(getString(R.string.health_table_source_row, preview.row.sourceRow))
            .setView(ScrollView(this).apply { addView(content) }).setNegativeButton(R.string.common_close, null).apply {
                if (preview.recordId.isNotBlank()) setPositiveButton(R.string.health_already_confirmed) { _, _ ->
                    startActivity(Intent(this@HealthTableActivity, HealthCenterActivity::class.java).putExtra("health_record", preview.recordId))
                }
            }.show()
    }
    private fun renderMapping(content: LinearLayout, batch: HealthTableBatch) {
        val m = batch.mapping
        ui.add(content, ui.text(getString(R.string.health_table_mapping), 19f, bold = true), 20)
        ui.add(content, ui.card().apply {
            addView(ui.row(getString(R.string.health_choose_metric), getString(m.metric.titleResource())) {
                choose(R.string.health_choose_metric, HealthMetric.entries.map { getString(it.titleResource()) }, getString(m.metric.titleResource())) { index ->
                    mapping(batch, HealthTablePolicy.suggest(batch.headers, HealthMetric.entries[index]).copy(date = m.date, zone = m.zone))
                }
            })
            addView(ui.line().apply {
                addView(ui.text(getString(R.string.health_table_columns_source), 12f, muted = true), LinearLayout.LayoutParams(0, -2, 1f))
                addView(ui.text(getString(R.string.health_table_columns_target), 12f, muted = true), LinearLayout.LayoutParams(0, -2, 1f))
            })
            ui.add(this, mappingLine(getString(R.string.health_table_time), m.timeColumn) {
                column(batch, m.timeColumn) { m.copy(timeColumn = it) }
            }, 10)
            m.metric.fields.forEach { field -> ui.add(this, mappingLine(getString(healthFieldResource(field)), m.columns[field].orEmpty()) {
                column(batch, m.columns[field].orEmpty()) { m.copy(columns = m.columns + (field to it)) }
            }, 10) }
            addView(ui.row(getString(R.string.health_table_unit), m.unitColumn.ifBlank { m.unit }.ifBlank {
                getString(if (m.metric.form in listOf(HealthResultForm.QUALITATIVE, HealthResultForm.LABORATORY)) R.string.health_unit_not_applicable else R.string.health_choose_unit)
            }) {
                val units = m.metric.selectableUnits
                val values = units.map { it.ifBlank { getString(R.string.health_unit_not_applicable) } } + getString(R.string.health_table_unit_column)
                choose(R.string.health_choose_unit, values, m.unit) { index ->
                    if (index == units.size) column(batch, m.unitColumn) { m.copy(unitColumn = it, unit = "") }
                    else mapping(batch, m.copy(unit = units[index], unitColumn = ""))
                }
            })
            addView(ui.row(getString(R.string.health_table_date), if (m.date == HealthTableDate.EXCEL) getString(R.string.health_xlsx_date_format) else m.date.pattern.replace("uuuu", "yyyy")) {
                val dates = HealthTableDate.entries.filter { it != HealthTableDate.EXCEL || batch.format == "xlsx" }
                fun label(value: HealthTableDate) = if (value == HealthTableDate.EXCEL) getString(R.string.health_xlsx_date_format) else value.pattern.replace("uuuu", "yyyy")
                choose(R.string.health_table_date, dates.map(::label), label(m.date)) { mapping(batch, m.copy(date = dates[it])) }
            })
            if (m.date == HealthTableDate.EXCEL || batch.format == "xlsx" && m.date == HealthTableDate.ISO) addView(ui.row(getString(R.string.health_xlsx_date_only), m.dateOnlyTime.ifBlank { getString(R.string.health_xlsx_time_required) }) {
                val initial = m.dateOnlyTime.split(':').mapNotNull(String::toIntOrNull)
                dialog = android.app.TimePickerDialog(this@HealthTableActivity, { _, hour, minute ->
                    mapping(batch, m.copy(dateOnlyTime = String.format(java.util.Locale.ROOT, "%02d:%02d", hour, minute)))
                }, initial.getOrElse(0) { 0 }, initial.getOrElse(1) { 0 }, true).apply {
                    setButton(android.app.AlertDialog.BUTTON_NEUTRAL, getString(R.string.health_xlsx_clear_time)) { _, _ -> mapping(batch, m.copy(dateOnlyTime = "")) }
                    show()
                }
            })
            if (batch.format == "xlsx") addView(CheckBox(this@HealthTableActivity).apply {
                text = getString(R.string.health_xlsx_allow_cache); textSize = 13f; setTextColor(getColor(R.color.text_primary))
                isChecked = m.allowFormulaCache
                setOnCheckedChangeListener { _, checked -> mapping(batch, m.copy(allowFormulaCache = checked)) }
            })
            addView(ui.row(getString(R.string.health_table_zone), m.zone) {
                val editor = EditText(this@HealthTableActivity).apply { setText(m.zone); isSingleLine = true }
                dialog = AlertDialog.Builder(this@HealthTableActivity).setTitle(R.string.health_table_zone).setView(editor)
                    .setNegativeButton(R.string.common_cancel, null).setPositiveButton(R.string.health_table_apply) { _, _ ->
                        val zone = editor.text.toString().trim()
                        if (runCatching { java.time.ZoneId.of(zone) }.isSuccess) mapping(batch, m.copy(zone = zone))
                        else Toast.makeText(this@HealthTableActivity, R.string.health_table_time_error, Toast.LENGTH_LONG).show()
                    }.show()
            })
            addView(ui.row(getString(R.string.health_note), m.noteColumn.ifBlank { getString(R.string.health_table_unmapped) }) {
                column(batch, m.noteColumn) { m.copy(noteColumn = it) }
            })
            addView(ui.row(getString(R.string.health_report_reference), m.referenceColumn.ifBlank { getString(R.string.health_table_unmapped) }) {
                column(batch, m.referenceColumn) { m.copy(referenceColumn = it) }
            })
        }, 10)
    }
    private fun mappingLine(field: String, column: String, action: () -> Unit) = ui.line().apply {
        fun tile(value: String) = ui.text(value, 14f).apply {
            minimumHeight = ui.dp(44); gravity = Gravity.CENTER_VERTICAL; setPadding(ui.dp(10), ui.dp(8), ui.dp(10), ui.dp(8))
            background = ui.background(0xfff4f7f5.toInt(), getColor(R.color.separator), 8)
            maxLines = 3; ellipsize = android.text.TextUtils.TruncateAt.END; setOnClickListener { action() }; isFocusable = true
        }
        addView(tile(column.ifBlank { getString(R.string.health_table_unmapped) }), LinearLayout.LayoutParams(0, -2, 1f))
        addView(ui.text("\u203a", 22f, muted = true).apply { gravity = Gravity.CENTER }, LinearLayout.LayoutParams(ui.dp(24), ui.dp(44)))
        addView(tile(field), LinearLayout.LayoutParams(0, -2, 1f))
    }
    private fun rowState(state: HealthTableRowState): Int = when (state) {
        HealthTableRowState.PENDING -> R.string.health_table_pending
        HealthTableRowState.VALID -> R.string.health_table_valid
        HealthTableRowState.DUPLICATE -> R.string.health_table_duplicate
        HealthTableRowState.MISSING -> R.string.health_table_missing
        HealthTableRowState.INVALID -> R.string.health_table_invalid
        HealthTableRowState.SAVED -> R.string.health_table_row_saved
        HealthTableRowState.UNDONE -> R.string.health_table_row_undone
        HealthTableRowState.EDITED -> R.string.health_table_row_edited
    }
    private fun rowIssue(issue: String) = when (issue) {
        "missing" -> R.string.health_table_missing_error
        "unit" -> R.string.health_table_unit_error
        "time" -> R.string.health_table_time_error
        "number" -> R.string.health_table_number_error
        "formula_ack" -> R.string.health_xlsx_formula_ack
        "formula_cache" -> R.string.health_xlsx_no_cache
        "excel_error" -> R.string.health_xlsx_cell_error
        else -> R.string.health_table_value_error
    }
    private fun failure() { Toast.makeText(this, R.string.health_storage_error, Toast.LENGTH_LONG).show() }
    private fun sheetLabel(sheet: HealthXlsxSheet) = sheet.name + if (sheet.visibility == "VISIBLE") "" else " \u00b7 " + getString(R.string.health_xlsx_hidden)
    private fun configureSheet(batch: HealthTableBatch, index: Int, row: Int) {
        fun apply() { after = 0; previous.clear(); generation++; change({ it.configureSheet(id, batch.mappingRevision, index, row) }) }
        if (batch.rows > 0) dialog = AlertDialog.Builder(this).setTitle(R.string.health_xlsx_sheet).setMessage(R.string.health_xlsx_change_notice)
            .setNegativeButton(R.string.common_cancel, null).setPositiveButton(R.string.health_table_apply) { _, _ -> apply() }.show()
        else apply()
    }
}

internal fun healthXlsxErrorResource(code: String): Int = when (code) {
    "xlsx_format" -> R.string.health_xlsx_format_error
    "xlsx_package", "xlsx_address" -> R.string.health_xlsx_package_error
    "xlsx_xml" -> R.string.health_xlsx_xml_error
    "xlsx_macro" -> R.string.health_xlsx_macro_error
    "xlsx_cell_type" -> R.string.health_xlsx_cell_type_error
    "xlsx_expansion", "xlsx_metadata" -> R.string.health_xlsx_expansion_error
    "xlsx_headers", "xlsx_sheet", "xlsx_sheets" -> R.string.health_xlsx_header_error
    "table_columns", "table_headers" -> R.string.health_table_headers_error
    "table_cell" -> R.string.health_table_cell_error
    "table_row" -> R.string.health_table_row_error
    "memory_pressure" -> R.string.health_import_memory_pressure
    "original_missing" -> R.string.health_original_missing
    else -> R.string.health_table_resume_error
}

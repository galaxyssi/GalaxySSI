package com.galaxyssi.chat

import android.app.DatePickerDialog
import android.app.TimePickerDialog
import android.text.Editable
import android.text.InputFilter
import android.text.InputType
import android.text.TextWatcher
import android.view.Gravity
import android.view.View
import android.widget.AdapterView
import android.widget.ArrayAdapter
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.Spinner
import android.widget.TextView
import android.widget.CheckBox
import java.util.Calendar

internal class HealthManualEditor(private val activity: HealthCenterActivity, private val draft: HealthDraft) {
    private val ui get() = activity.ui
    private val fields = linkedMapOf<String, EditText>()
    private val unitLabels = linkedMapOf<String, TextView>()
    private lateinit var unit: Spinner
    private lateinit var condition: Spinner
    private var side: Spinner? = null
    private lateinit var note: EditText
    private lateinit var time: TextView
    private lateinit var error: TextView
    private lateinit var save: TextView
    private var confirmation: CheckBox? = null
    private var unitOptions = draft.metric.units
    private var measuredAt = draft.measuredAt
    private var ready = false
    private val conditions = listOf("unspecified", "resting", "after_exercise", "fasting", "after_meal", "other")
    private val sides = listOf("unspecified", "left", "right")

    fun render() {
        val content = activity.scrolling()
        draft.evidence?.let { evidence ->
            ui.add(content, ui.card().apply {
                addView(ui.text(activity.getString(R.string.health_review_source), 17f, bold = true))
                ui.add(this, ui.text(evidence.rawText, 14f).apply { setTextIsSelectable(true) }, 8)
                val location = if (evidence.tableSheet.isNotBlank()) activity.getString(R.string.health_xlsx_source_row, evidence.tableSheet, evidence.tableRow)
                    else activity.getString(when {
                    evidence.kind == "table" -> R.string.health_table_source_row
                    evidence.documentPage > 0 -> R.string.health_photo_page
                    else -> R.string.health_source_page
                }, when { evidence.kind == "table" -> evidence.tableRow; evidence.documentPage > 0 -> evidence.documentPage.toLong(); else -> evidence.page.toLong() })
                ui.add(this, ui.row(activity.getString(R.string.health_view_original), location) {
                    activity.startActivity(android.content.Intent(activity, HealthCaptureActivity::class.java)
                        .putExtra("original", evidence.originalId))
                }, 8)
            })
        }
        if (draft.recordId.isBlank() && draft.evidence == null) {
            val metrics = ui.line().apply { background = ui.background(activity.getColor(R.color.button_soft), radius = 10) }
            HealthMetric.entries.take(3).forEach { metric ->
                metrics.addView(ui.text(activity.getString(metric.titleResource()), 13f).apply {
                    tag = "health-metric-${metric.name}"; minimumHeight = ui.dp(44); gravity = Gravity.CENTER
                    if (draft.metric == metric) background = ui.background(radius = 8)
                    setOnClickListener { activity.changeMetric(metric) }; isFocusable = true
                }, LinearLayout.LayoutParams(0, -2, 1f))
            }
            metrics.addView(ui.text(activity.getString(if (draft.metric.ordinal >= 3) draft.metric.titleResource() else R.string.health_more_metrics), 13f).apply {
                minimumHeight = ui.dp(44); gravity = Gravity.CENTER; tag = "health-metric-MORE"
                if (draft.metric.ordinal >= 3) background = ui.background(radius = 8)
                setOnClickListener {
                    val other = HealthMetric.entries.drop(3)
                    activity.showHealthDialog(android.app.AlertDialog.Builder(activity).setTitle(R.string.health_choose_metric)
                        .setItems(other.map { activity.getString(it.titleResource()) }.toTypedArray()) { _, index -> activity.changeMetric(other[index]) }.create())
                }
            }, LinearLayout.LayoutParams(0, -2, 1f))
            content.addView(metrics)
        }
        val card = ui.card()
        ui.add(content, card, 16)
        card.addView(ui.text(activity.getString(R.string.health_record_metric, activity.getString(draft.metric.titleResource())), 20f, bold = true))
        ui.add(card, ui.text(activity.getString(R.string.health_enter_measured_values), 13f, muted = true), 8)
        val pair = ui.line()
        if (draft.metric == HealthMetric.BLOOD_PRESSURE) {
            draft.metric.requiredFields.forEach { field -> pair.addView(valueField(field, 29f), LinearLayout.LayoutParams(0, -2, 1f).apply {
                if (field == "systolic") marginEnd = ui.dp(10)
            }) }
            ui.add(card, pair, 20)
            ui.add(card, valueField("pulse", 18f), 18)
        } else ui.add(card, valueField(draft.metric.fields.first(), 29f), 20)
        unitOptions = if (draft.unit.isBlank()) listOf("") + draft.metric.units else draft.metric.units
        unit = spinner(unitOptions.map { it.ifBlank { activity.getString(R.string.health_choose_unit) } }, unitOptions.indexOf(draft.unit))
        if (unitOptions.size > 1) {
            ui.add(card, ui.text(activity.getString(R.string.health_unit), 13f, muted = true), 16)
            card.addView(unit)
        }
        ui.add(card, ui.text(activity.getString(R.string.health_measured_at), 13f, muted = true), 16)
        time = ui.text(if (measuredAt > 0) activity.date(measuredAt) else activity.getString(R.string.health_choose_time)).apply {
            tag = "health-measured-at"; minimumHeight = ui.dp(48); gravity = Gravity.CENTER_VERTICAL
            background = ui.background(stroke = activity.getColor(R.color.separator), radius = 10)
            setPadding(ui.dp(12), 0, ui.dp(12), 0); setOnClickListener { chooseTime() }; isFocusable = true
        }
        card.addView(time)
        ui.add(card, ui.text(activity.getString(R.string.health_condition), 13f, muted = true), 16)
        condition = spinner(conditions.map { activity.getString(healthContextResource(it)) }, conditions.indexOf(draft.condition))
        card.addView(condition)
        if (draft.metric == HealthMetric.BLOOD_PRESSURE) {
            ui.add(card, ui.text(activity.getString(R.string.health_side), 13f, muted = true), 16)
            side = spinner(sides.map { activity.getString(healthContextResource(it)) }, sides.indexOf(draft.side)).also(card::addView)
        }
        ui.add(card, ui.text(activity.getString(R.string.health_note), 13f, muted = true), 16)
        note = EditText(activity).apply {
            tag = "health-note"; isSaveEnabled = false; textSize = 16f; setTextColor(activity.getColor(R.color.text_primary))
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_MULTI_LINE or InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS
            minLines = 2; maxLines = 4; filters = arrayOf(InputFilter.LengthFilter(2000))
            setText(draft.note); addTextChangedListener(watcher())
        }
        card.addView(note)
        draft.evidence?.let { evidence ->
            confirmation = CheckBox(activity).apply {
                tag = "health-confirm-source"; text = activity.getString(R.string.health_confirm_source)
                setTextColor(activity.getColor(R.color.text_primary)); textSize = 14f; isChecked = evidence.confirmed
                setOnCheckedChangeListener { _, _ -> if (ready) activity.draftChanged() }
            }.also { ui.add(content, it, 16) }
        }
        error = ui.text("", 14f).apply { setTextColor(0xffad342f.toInt()); visibility = View.GONE; tag = "health-validation" }
        ui.add(content, error, 12)
        ui.add(content, ui.text(activity.getString(R.string.health_local_storage), 12f, muted = true), 16)
        save = ui.command(R.string.health_save) { activity.saveMeasurement(snapshot()) }.apply { tag = "health-save" }
        activity.body.addView(ui.column().apply {
            setPadding(ui.dp(16), ui.dp(10), ui.dp(16), ui.dp(12)); addView(save)
        }, LinearLayout.LayoutParams(-1, -2))
        ready = true
    }
    private fun valueField(field: String, size: Float) = ui.column().apply {
        val label = activity.getString(healthFieldResource(field)) + if (field !in draft.metric.requiredFields) activity.getString(R.string.health_optional) else ""
        addView(ui.text(label, 13f, muted = true))
        val input = EditText(activity).apply {
            tag = "health-field-$field"; isSaveEnabled = false; contentDescription = label
            textSize = size; setSingleLine(true); minimumHeight = ui.dp(62)
            setTextColor(activity.getColor(R.color.text_primary)); setPadding(ui.dp(12), ui.dp(8), ui.dp(12), ui.dp(8))
            background = ui.background(stroke = activity.getColor(R.color.separator), radius = 10)
            inputType = InputType.TYPE_CLASS_NUMBER or InputType.TYPE_NUMBER_FLAG_DECIMAL
            filters = arrayOf(InputFilter.LengthFilter(20)); setText(draft.values[field].orEmpty()); addTextChangedListener(watcher())
        }
        fields[field] = input
        ui.add(this, input, 8)
        if (draft.metric.units.size == 1 || draft.metric == HealthMetric.BLOOD_PRESSURE) ui.add(this, ui.text(draft.unitFor(field), 12f, muted = true).apply {
            tag = "health-unit-$field"; unitLabels[field] = this
        }, 5)
    }
    private fun spinner(labels: List<String>, selected: Int) = Spinner(activity).apply {
        var previous = selected.coerceAtLeast(0)
        minimumHeight = ui.dp(48)
        adapter = ArrayAdapter(activity, android.R.layout.simple_spinner_dropdown_item, labels)
        setSelection(selected.coerceAtLeast(0), false)
        onItemSelectedListener = object : AdapterView.OnItemSelectedListener {
            override fun onNothingSelected(parent: AdapterView<*>?) = Unit
            override fun onItemSelected(parent: AdapterView<*>?, view: View?, position: Int, id: Long) {
                if (position != previous && ready) { confirmation?.isChecked = false; activity.draftChanged() }
                previous = position
                if (::unit.isInitialized && this@apply === unit && position in unitOptions.indices) unitLabels.forEach { (field, label) ->
                    label.text = if (draft.metric == HealthMetric.BLOOD_PRESSURE && field == "pulse") "bpm" else unitOptions[position]
                }
            }
        }
    }
    private fun watcher() = object : TextWatcher {
        override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) = Unit
        override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) { if (ready) { confirmation?.isChecked = false; activity.draftChanged() } }
        override fun afterTextChanged(s: Editable?) = Unit
    }
    fun snapshot() = draft.copy(values = fields.mapValues { it.value.text.toString() }, unit = unitOptions[unit.selectedItemPosition.coerceAtLeast(0)],
        measuredAt = measuredAt, condition = conditions[condition.selectedItemPosition.coerceAtLeast(0)],
        side = side?.selectedItemPosition?.let { sides[it.coerceAtLeast(0)] } ?: "unspecified", note = note.text.toString(),
        evidence = draft.evidence?.copy(confirmed = confirmation?.isChecked == true))
    fun setSaving(value: Boolean) { save.isEnabled = !value; save.alpha = if (value) .5f else 1f }
    fun showError(value: HealthValidationError) {
        val label = if (value.field.isBlank()) "" else activity.getString(healthFieldResource(value.field))
        error.text = activity.getString(when (value.issue) {
            HealthValidationIssue.MISSING_VALUE -> R.string.health_missing_value
            HealthValidationIssue.INVALID_NUMBER -> R.string.health_invalid_number
            HealthValidationIssue.INVALID_UNIT -> R.string.health_invalid_unit
            HealthValidationIssue.INVALID_TIME -> R.string.health_invalid_time
            HealthValidationIssue.INVALID_CONTEXT -> R.string.health_invalid_context
            HealthValidationIssue.UNCONFIRMED_SOURCE -> R.string.health_confirm_source_required
        }, label)
        error.visibility = View.VISIBLE
        fields[value.field]?.apply { this.error = this@HealthManualEditor.error.text; requestFocus() }
    }
    private fun chooseTime() {
        val calendar = Calendar.getInstance().apply { if (measuredAt > 0) timeInMillis = measuredAt }
        DatePickerDialog(activity, { _, year, month, day ->
            activity.showHealthDialog(TimePickerDialog(activity, { _, hour, minute ->
                calendar.set(year, month, day, hour, minute, 0); calendar.set(Calendar.MILLISECOND, 0)
                measuredAt = calendar.timeInMillis; time.text = activity.date(measuredAt); confirmation?.isChecked = false; activity.draftChanged()
            }, calendar.get(Calendar.HOUR_OF_DAY), calendar.get(Calendar.MINUTE), android.text.format.DateFormat.is24HourFormat(activity)))
        }, calendar.get(Calendar.YEAR), calendar.get(Calendar.MONTH), calendar.get(Calendar.DAY_OF_MONTH)).let(activity::showHealthDialog)
    }
}

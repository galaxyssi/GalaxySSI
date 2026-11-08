package com.galaxyssi.chat

import android.app.Activity
import android.app.AlertDialog
import android.text.Editable
import android.text.TextWatcher
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.RadioButton
import android.widget.RadioGroup
import android.widget.ScrollView

internal fun HealthCareInstructionKind.label() = when (this) {
    HealthCareInstructionKind.MEDICATION -> R.string.health_instruction_medication
    HealthCareInstructionKind.TEST -> R.string.health_instruction_test
    HealthCareInstructionKind.FOLLOW_UP -> R.string.health_instruction_follow_up
    HealthCareInstructionKind.REHABILITATION -> R.string.health_instruction_rehabilitation
    HealthCareInstructionKind.LIFESTYLE -> R.string.health_instruction_lifestyle
    HealthCareInstructionKind.OTHER -> R.string.health_instruction_other
}
internal fun HealthCareInstructionField.label() = when (this) {
    HealthCareInstructionField.NAME -> R.string.health_instruction_name
    HealthCareInstructionField.DOSE -> R.string.health_instruction_dose
    HealthCareInstructionField.UNIT -> R.string.health_instruction_unit
    HealthCareInstructionField.ROUTE -> R.string.health_instruction_route
    HealthCareInstructionField.FREQUENCY -> R.string.health_instruction_frequency
    HealthCareInstructionField.START -> R.string.health_instruction_start
    HealthCareInstructionField.END -> R.string.health_instruction_end
    HealthCareInstructionField.DETAILS -> R.string.health_instruction_details
}
internal fun HealthCareInstructionDraft.label() = when {
    !reviewed -> R.string.health_instruction_pending
    missing.isNotEmpty() -> R.string.health_instruction_omitted
    else -> R.string.health_instruction_reviewed
}

internal class HealthCareInstructionEditor(private val activity: Activity) {
    private val ui = HealthCenterViews(activity)
    private var dialog: AlertDialog? = null
    private var picker: AlertDialog? = null
    private var root: LinearLayout? = null
    private val inputs = mutableMapOf<HealthCareInstructionField, EditText>()
    private val statuses = mutableMapOf<HealthCareInstructionField, HealthCareFieldReview>()
    private val retained = mutableMapOf<HealthCareInstructionField, HealthCareInstructionValue>()
    fun clear() {
        picker?.dismiss(); picker = null
        dialog?.setOnDismissListener(null); dialog?.dismiss(); dialog = null
        inputs.values.forEach { it.setText("") }; inputs.clear(); statuses.clear(); retained.clear()
        root?.removeAllViews(); root = null
    }
    fun show(value: HealthCareInstruction, save: (HealthCareInstructionDraft) -> Unit) {
        clear(); retained.putAll(value.draft.fields)
        var kind = value.draft.kind
        val content = ui.column().apply { setPadding(ui.dp(20), ui.dp(8), ui.dp(20), ui.dp(8)) }
        root = content
        val error = ui.text("", 13f)
        fun collect() = inputs.mapValues { (field, input) -> HealthCareInstructionValue(input.text.toString().trim(), statuses[field]!!) }
        fun render() {
            content.removeAllViews(); inputs.clear(); statuses.clear()
            content.addView(ui.text(value.source.quote, 14f, muted = true))
            ui.add(content, ui.profileRow(activity.getString(R.string.health_instruction_kind), activity.getString(kind.label())) {
                val values = runCatching(::collect).getOrElse { error.text = activity.getString(R.string.health_instruction_invalid); return@profileRow }
                retained.putAll(values)
                picker = AlertDialog.Builder(activity).setTitle(R.string.health_instruction_kind)
                    .setItems(HealthCareInstructionKind.entries.map { activity.getString(it.label()) }.toTypedArray()) { _, index ->
                        kind = HealthCareInstructionKind.entries[index]; render()
                    }.show()
            }.apply { tag = "instruction-kind" }, 12)
            HealthCareInstructionDraft(kind).required.forEach { field ->
                val initial = retained[field] ?: HealthCareInstructionValue()
                ui.add(content, ui.text(activity.getString(field.label()), 14f, bold = true), 16)
                val input = activity.healthProfileInput(initial.text, 1000, multiline = true).apply { minLines = 1; maxLines = 4; tag = "instruction-field-${field.name}" }
                val group = RadioGroup(activity).apply { orientation = RadioGroup.VERTICAL }
                val checked = RadioButton(activity).apply { id = android.view.View.generateViewId(); text = activity.getString(R.string.health_instruction_transcribed); tag = "instruction-checked-${field.name}" }
                val missing = RadioButton(activity).apply { id = android.view.View.generateViewId(); text = activity.getString(R.string.health_instruction_not_stated); tag = "instruction-missing-${field.name}" }
                group.addView(checked); group.addView(missing)
                inputs[field] = input; statuses[field] = initial.review
                when (initial.review) { HealthCareFieldReview.TRANSCRIBED -> checked.isChecked = true
                    HealthCareFieldReview.NOT_STATED -> missing.isChecked = true; else -> Unit }
                var changing = false
                input.addTextChangedListener(object : TextWatcher {
                    override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) = Unit
                    override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {
                        if (!changing) { changing = true; group.clearCheck(); statuses[field] = HealthCareFieldReview.UNREVIEWED; changing = false }
                    }
                    override fun afterTextChanged(s: Editable?) = Unit
                })
                group.setOnCheckedChangeListener { _, id -> if (!changing) {
                    changing = true
                    statuses[field] = when (id) {
                        checked.id -> HealthCareFieldReview.TRANSCRIBED
                        missing.id -> { input.setText(""); HealthCareFieldReview.NOT_STATED }
                        else -> HealthCareFieldReview.UNREVIEWED
                    }
                    changing = false
                } }
                ui.add(content, input, 4); content.addView(group)
            }
            content.addView(error)
        }
        render()
        dialog = AlertDialog.Builder(activity).setTitle(R.string.health_instruction_edit).setView(ScrollView(activity).apply { addView(content) })
            .setNegativeButton(R.string.common_cancel, null).setPositiveButton(R.string.health_instruction_save, null).show().also { popup ->
                popup.setOnDismissListener { clear() }
                popup.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener {
                    val draft = runCatching { HealthCareInstructionDraft(kind, collect()) }.getOrElse {
                        error.text = activity.getString(R.string.health_instruction_invalid); return@setOnClickListener
                    }
                    clear(); save(draft)
                }
            }
    }
}

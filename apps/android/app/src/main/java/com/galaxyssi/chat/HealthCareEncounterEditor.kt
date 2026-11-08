package com.galaxyssi.chat

import android.app.Activity
import android.app.AlertDialog
import android.app.DatePickerDialog
import android.app.Dialog
import android.app.TimePickerDialog
import android.view.View
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.RadioButton
import android.widget.RadioGroup
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle

internal class HealthCareEncounterEditor(private val activity: Activity) {
    private val ui = HealthCenterViews(activity)
    private var dialog: AlertDialog? = null
    private var picker: Dialog? = null
    private val inputs = mutableListOf<EditText>()
    private var generation = 0
    fun clear() {
        generation++; picker?.dismiss(); picker = null
        inputs.forEach { it.text?.clear() }; inputs.clear(); dialog?.dismiss(); dialog = null
    }
    fun show(value: HealthCareEncounter?, save: (HealthCareEncounterDraft) -> Unit) {
        clear(); val token = generation
        val zone = value?.details?.zone?.let(ZoneId::of) ?: ZoneId.systemDefault()
        var planned = value?.details?.plannedAt; var attended = value?.details?.attendedAt
        var state = value?.details?.state ?: HealthCareEncounterState.PLANNED
        val body = ui.column().apply { setPadding(ui.dp(20), 0, ui.dp(20), ui.dp(16)); isSaveEnabled = false }
        ui.add(body, ui.text(activity.getString(R.string.health_encounter_notice), 13f, muted = true), 8)
        fun field(title: Int, text: String, max: Int, tag: String, multiline: Boolean = false): EditText {
            ui.add(body, ui.text(activity.getString(title), 14f, bold = true), 12)
            return activity.healthProfileInput(text, max, multiline).also { input ->
                input.tag = tag; inputs += input; ui.add(body, input, 4)
            }
        }
        val purpose = field(R.string.health_encounter_purpose, value?.details?.purpose.orEmpty(), 500, "encounter-purpose")
        val facility = field(R.string.health_encounter_facility, value?.details?.facility.orEmpty(), 500, "encounter-facility")
        val choices = RadioGroup(activity).apply { orientation = LinearLayout.VERTICAL; isSaveEnabled = false }
        HealthCareEncounterState.entries.forEach { option -> choices.addView(RadioButton(activity).apply {
            id = View.generateViewId(); tag = "encounter-state-${option.name}"; text = activity.getString(option.label())
            minHeight = ui.dp(48); isSaveEnabled = false; isChecked = option == state
        }) }
        ui.add(body, choices, 12)
        fun timeRow(title: Int, tag: String, value: () -> Long?, changed: (Long?) -> Unit): TextView {
            val row = ui.profileRow(activity.getString(title), encounterTime(activity, value(), zone.id)) {}.apply { this.tag = tag }
            val label = (row.getChildAt(0) as LinearLayout).getChildAt(1) as TextView
            row.setOnClickListener { choose(value(), zone, token) { at -> changed(at); label.text = encounterTime(activity, at, zone.id) } }
            ui.add(body, row, 8)
            ui.add(body, ui.profileRow(activity.getString(R.string.health_encounter_clear_time)) {
                changed(null); label.text = encounterTime(activity, null, zone.id)
            }.apply { this.tag = "$tag-clear" }, 2)
            return label
        }
        timeRow(R.string.health_encounter_planned, "encounter-planned", { planned }) { planned = it }
        val actualGroup = ui.column()
        val before = body.childCount
        timeRow(R.string.health_encounter_attended, "encounter-attended", { attended }) { attended = it }
        while (body.childCount > before) body.getChildAt(before).let { body.removeView(it); actualGroup.addView(it) }
        body.addView(actualGroup)
        actualGroup.visibility = if (state == HealthCareEncounterState.ATTENDED) View.VISIBLE else View.GONE
        choices.setOnCheckedChangeListener { group, id ->
            state = HealthCareEncounterState.entries.first { group.findViewById<View>(id).tag == "encounter-state-${it.name}" }
            actualGroup.visibility = if (state == HealthCareEncounterState.ATTENDED) View.VISIBLE else View.GONE
        }
        val note = field(R.string.health_encounter_note, value?.details?.note.orEmpty(), 4000, "encounter-note", true)
        val next = AlertDialog.Builder(activity).setTitle(if (value == null) R.string.health_encounter_add else R.string.health_encounter_edit)
            .setView(ScrollView(activity).apply { addView(body); isSaveEnabled = false })
            .setNegativeButton(R.string.common_cancel, null).setPositiveButton(R.string.health_question_save, null).create()
        dialog = next
        next.setOnDismissListener { inputs.forEach { it.text?.clear() }; inputs.clear(); body.removeAllViews(); if (dialog === next) dialog = null }
        next.show()
        next.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener {
            val details = runCatching { HealthCareEncounterDraft(purpose.text.toString().trim(), facility.text.toString().trim(), state,
                planned, attended.takeIf { state == HealthCareEncounterState.ATTENDED }, zone.id, note.text.toString().trim()) }.getOrNull()
            if (details == null || (details.attendedAt != null && details.attendedAt > System.currentTimeMillis())) {
                Toast.makeText(activity, R.string.health_encounter_invalid, Toast.LENGTH_LONG).show()
            } else if (generation == token) {
                next.getButton(AlertDialog.BUTTON_POSITIVE).isEnabled = false; save(details)
            }
        }
    }
    private fun choose(at: Long?, zone: ZoneId, token: Int, done: (Long) -> Unit) {
        val current = Instant.ofEpochMilli(at ?: System.currentTimeMillis()).atZone(zone)
        fun active() = generation == token && dialog?.isShowing == true && !activity.isFinishing
        picker = DatePickerDialog(activity, { _, year, month, day ->
            if (active()) {
                picker = TimePickerDialog(activity, { _, hour, minute ->
                    if (active()) {
                        val local = LocalDateTime.of(year, month + 1, day, hour, minute)
                        val options = zone.rules.getValidOffsets(local)
                        when (options.size) {
                            0 -> Toast.makeText(activity, R.string.health_encounter_invalid_time, Toast.LENGTH_LONG).show()
                            1 -> done(local.toInstant(options.single()).toEpochMilli())
                            else -> {
                                picker = AlertDialog.Builder(activity).setTitle(R.string.health_encounter_choose_offset)
                                    .setItems(options.map { "UTC$it" }.toTypedArray()) { _, index ->
                                        if (active()) done(local.toInstant(options[index]).toEpochMilli())
                                    }.setNegativeButton(R.string.common_cancel, null).create().also { it.show() }
                            }
                        }
                    }
                }, current.hour, current.minute, android.text.format.DateFormat.is24HourFormat(activity)).also { it.show() }
            }
        }, current.year, current.monthValue - 1, current.dayOfMonth).also { it.show() }
    }
}

internal fun HealthCareEncounterState.label() = when (this) {
    HealthCareEncounterState.PLANNED -> R.string.health_encounter_state_planned
    HealthCareEncounterState.BOOKING_RECORDED -> R.string.health_encounter_state_booked
    HealthCareEncounterState.ATTENDED -> R.string.health_encounter_state_attended
    HealthCareEncounterState.CANCELLED -> R.string.health_encounter_state_cancelled
}
internal fun encounterTime(context: android.content.Context, at: Long?, zone: String): String {
    if (at == null) return context.getString(R.string.health_encounter_unspecified)
    val value = Instant.ofEpochMilli(at).atZone(ZoneId.of(zone))
    val offset = value.offset.id.takeUnless { it == "Z" } ?: "+00:00"
    return "${DateTimeFormatter.ofLocalizedDateTime(FormatStyle.MEDIUM, FormatStyle.SHORT).format(value)} ($zone, UTC$offset)"
}

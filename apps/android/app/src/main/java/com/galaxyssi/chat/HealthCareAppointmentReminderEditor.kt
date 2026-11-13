package com.galaxyssi.chat

import android.app.Activity
import android.app.AlertDialog
import android.app.DatePickerDialog
import android.app.TimePickerDialog
import android.widget.Toast
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneId

internal class HealthCareAppointmentReminderEditor(private val activity: Activity) {
    private var dialog: AlertDialog? = null
    private var generation = 0
    fun clear() { generation++; dialog?.dismiss(); dialog = null }

    fun show(visit: HealthCareEncounter, reminder: HealthCareReminder?, save: (Long) -> Unit) {
        clear()
        val token = generation
        val now = System.currentTimeMillis()
        if (!HealthCareAppointmentPolicy.available(visit, now)) return invalid()
        val planned = requireNotNull(visit.details.plannedAt)
        val zone = ZoneId.of(visit.details.zone)
        val initial = reminder?.dueAt?.takeIf { it > now && it < planned }
            ?: maxOf((now / 60_000L + 1) * 60_000L, planned - 3_600_000L)
        val date = Instant.ofEpochMilli(initial).atZone(zone)
        fun active() = generation == token && !activity.isFinishing && !activity.isDestroyed
        fun confirm(at: Long) {
            if (!active()) return
            if (at <= System.currentTimeMillis() || at >= planned) return invalid()
            dialog = AlertDialog.Builder(activity).setTitle(R.string.health_appointment_reminder)
                .setMessage(activity.getString(R.string.health_appointment_confirm, encounterTime(activity, at, zone.id),
                    encounterTime(activity, planned, zone.id)))
                .setNegativeButton(R.string.common_cancel, null).setPositiveButton(android.R.string.ok) { _, _ ->
                    if (active()) { clear(); save(at) }
                }.show()
        }
        dialog = DatePickerDialog(activity, { _, year, month, day ->
            if (!active()) return@DatePickerDialog
            dialog = TimePickerDialog(activity, { _, hour, minute ->
                if (!active()) return@TimePickerDialog
                val local = LocalDateTime.of(year, month + 1, day, hour, minute)
                val offsets = zone.rules.getValidOffsets(local)
                when (offsets.size) {
                    0 -> Toast.makeText(activity, R.string.health_encounter_invalid_time, Toast.LENGTH_LONG).show()
                    1 -> confirm(local.toInstant(offsets.single()).toEpochMilli())
                    else -> dialog = AlertDialog.Builder(activity).setTitle(R.string.health_encounter_choose_offset)
                        .setItems(offsets.map { "UTC$it" }.toTypedArray()) { _, index -> confirm(local.toInstant(offsets[index]).toEpochMilli()) }
                        .setNegativeButton(R.string.common_cancel, null).show()
                }
            }, date.hour, date.minute, android.text.format.DateFormat.is24HourFormat(activity)).also {
                it.setTitle(R.string.health_appointment_reminder); it.show()
            }
        }, date.year, date.monthValue - 1, date.dayOfMonth).also { it.setTitle(R.string.health_appointment_reminder); it.show() }
    }

    private fun invalid() { Toast.makeText(activity, R.string.health_appointment_invalid_time, Toast.LENGTH_LONG).show() }
}

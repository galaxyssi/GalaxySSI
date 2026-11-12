package com.galaxyssi.chat

import android.app.Activity
import android.app.AlertDialog
import android.app.DatePickerDialog
import android.app.TimePickerDialog
import android.widget.Toast
import java.util.Calendar

internal class HealthCareVisitReviewEditor(private val activity: Activity) {
    private var dialog: AlertDialog? = null
    private var generation = 0
    fun clear() { generation++; dialog?.dismiss(); dialog = null }
    fun show(snapshot: HealthCareVisitFollowUpSnapshot, save: (Long) -> Unit) {
        clear(); val token = generation
        val calendar = Calendar.getInstance().apply {
            timeInMillis = maxOf(System.currentTimeMillis() + 3_600_000L, snapshot.reminder?.dueAt ?: 0L)
        }
        dialog = DatePickerDialog(activity, { _, year, month, day ->
            if (token != generation) return@DatePickerDialog
            calendar.set(Calendar.YEAR, year); calendar.set(Calendar.MONTH, month); calendar.set(Calendar.DAY_OF_MONTH, day)
            dialog = TimePickerDialog(activity, { _, hour, minute ->
                if (token != generation) return@TimePickerDialog
                calendar.set(Calendar.HOUR_OF_DAY, hour); calendar.set(Calendar.MINUTE, minute)
                calendar.set(Calendar.SECOND, 0); calendar.set(Calendar.MILLISECOND, 0)
                val at = calendar.timeInMillis
                if (at <= System.currentTimeMillis()) {
                    Toast.makeText(activity, R.string.health_care_followup_future_time, Toast.LENGTH_LONG).show()
                    return@TimePickerDialog
                }
                val time = encounterTime(activity, at, java.time.ZoneId.systemDefault().id)
                dialog = AlertDialog.Builder(activity).setTitle(R.string.health_visit_review_schedule)
                    .setMessage(activity.getString(R.string.health_visit_review_confirm, time) + "\n\n" +
                        activity.getString(R.string.health_visit_review_notice))
                    .setNegativeButton(R.string.common_cancel, null).setPositiveButton(android.R.string.ok) { _, _ ->
                        if (token == generation) { clear(); save(at) }
                    }.show()
            }, calendar.get(Calendar.HOUR_OF_DAY), calendar.get(Calendar.MINUTE), android.text.format.DateFormat.is24HourFormat(activity))
                .also { it.setTitle(R.string.health_visit_review_schedule); it.show() }
        }, calendar.get(Calendar.YEAR), calendar.get(Calendar.MONTH), calendar.get(Calendar.DAY_OF_MONTH)).also { it.show() }
    }
}

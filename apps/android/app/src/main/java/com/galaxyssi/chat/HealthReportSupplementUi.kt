package com.galaxyssi.chat

import android.app.Activity
import android.app.AlertDialog
import android.app.DatePickerDialog
import android.app.TimePickerDialog
import android.text.format.DateFormat
import android.view.View
import android.widget.ArrayAdapter
import android.widget.ScrollView
import android.widget.Spinner
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId

internal class HealthReportSupplementUi(private val activity: Activity) {
    private val ui = HealthCenterViews(activity)
    private var dialog: AlertDialog? = null
    private var picker: AlertDialog? = null
    fun clear() { picker?.dismiss(); picker = null; dialog?.dismiss(); dialog = null }

    fun show(scope: HealthReportSupplementScope, count: Int, submit: (HealthReportSupplement) -> Unit, later: () -> Unit) {
        clear()
        val zone = ZoneId.systemDefault()
        var date: LocalDate? = null
        var time: LocalTime? = null
        val fields = ui.column().apply { setPadding(ui.dp(24), ui.dp(8), ui.dp(24), ui.dp(8)) }
        fields.addView(ui.text(activity.getString(R.string.health_report_confirm_note, count), 14f, muted = true))
        val selection = ui.text("", 13f, muted = true)
        fun changed() {
            val checked = time?.let { t -> date?.let { healthReportSupplementTime(it, t, zone, System.currentTimeMillis()) } }
            selection.text = when {
                time == null -> ""
                !scope.needsDate -> java.time.format.DateTimeFormatter.ofLocalizedTime(java.time.format.FormatStyle.SHORT).format(time)
                checked == null -> activity.getString(R.string.health_report_invalid_time)
                else -> java.text.DateFormat.getDateTimeInstance().format(java.util.Date(checked))
            }
            dialog?.getButton(AlertDialog.BUTTON_POSITIVE)?.isEnabled =
                !scope.needsTime || time != null && (!scope.needsDate || checked != null)
        }
        fun pickTime() {
            val initial = time ?: LocalTime.now(zone)
            picker = TimePickerDialog(activity, { _, h, m -> time = LocalTime.of(h, m); changed() },
                initial.hour, initial.minute, DateFormat.is24HourFormat(activity)).also { it.show() }
        }
        if (scope.needsTime) {
            ui.add(fields, ui.row(activity.getString(if (scope.needsDate) R.string.health_report_pick_date_time else R.string.health_report_pick_time)) {
                if (!scope.needsDate) pickTime() else {
                    val initial = date ?: LocalDate.now(zone)
                    picker = DatePickerDialog(activity, { _, y, m, d -> date = LocalDate.of(y, m + 1, d); pickTime() },
                        initial.year, initial.monthValue - 1, initial.dayOfMonth).also {
                        it.datePicker.maxDate = System.currentTimeMillis()
                        it.show()
                    }
                }
            }.apply { tag = "health-report-pick-time" }, 10)
            fields.addView(selection)
        }
        val options = listOf("unspecified") + healthGlucoseConditions.filterNot { it == "unspecified" }
        val condition = if (!scope.needsCondition) null else Spinner(activity).apply {
            tag = "health-report-condition"
            adapter = ArrayAdapter(activity, android.R.layout.simple_spinner_dropdown_item,
                options.map { activity.getString(healthContextResource(it)) })
            minimumHeight = ui.dp(48)
            isSaveEnabled = false
        }.also {
            ui.add(fields, ui.text(activity.getString(R.string.health_report_glucose_condition), 15f, bold = true), 12)
            fields.addView(it)
        }
        dialog = AlertDialog.Builder(activity).setTitle(R.string.health_report_confirm_title)
            .setView(ScrollView(activity).apply { addView(fields) })
            .setNegativeButton(R.string.health_report_confirm_later) { _, _ -> later() }
            .setOnCancelListener { later() }
            .setPositiveButton(R.string.health_report_confirm_save) { _, _ ->
                submit(HealthReportSupplement(date, time, options[condition?.selectedItemPosition?.coerceAtLeast(0) ?: 0]))
            }.show()
        changed()
    }
}

package com.galaxyssi.chat

import android.app.Activity
import android.app.AlertDialog
import android.app.DatePickerDialog
import android.app.TimePickerDialog
import android.text.format.DateFormat
import android.view.View
import android.widget.RadioButton
import android.widget.RadioGroup
import android.widget.ScrollView
import android.widget.Toast
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId

internal class HealthReportSupplementUi(private val activity: Activity) {
    private val views = HealthCenterViews(activity)
    private var dialog: AlertDialog? = null
    private var picker: AlertDialog? = null

    fun clear() { picker?.dismiss(); picker = null; dialog?.dismiss(); dialog = null }

    fun show(plan: HealthReportImportPlan, save: (HealthReportSupplement) -> Unit) {
        clear()
        val zone = ZoneId.systemDefault()
        val pickedDate = plan.collectedDate.takeIf(String::isNotEmpty)?.let(LocalDate::parse)
        var time = 0L
        var fasting = ""
        val fields = views.column().apply { setPadding(views.dp(24), views.dp(8), views.dp(24), views.dp(8)) }
        fun update() {
            dialog?.getButton(AlertDialog.BUTTON_POSITIVE)?.isEnabled =
                (!plan.needsDate || time > 0) && (!plan.needsFasting || fasting.isNotEmpty())
        }
        if (plan.needsDate) {
            val dateCaption = if (pickedDate == null) activity.getString(R.string.health_report_pick_time)
                else activity.getString(R.string.health_report_pick_time_for_date, pickedDate)
            val selection = views.text("", 14f, muted = true).apply { visibility = View.GONE }
            views.add(fields, views.row(dateCaption) {
                fun pickTime(day: LocalDate) {
                    picker = TimePickerDialog(activity, { _, hour, minute ->
                        val local = LocalDateTime.of(day.year, day.monthValue, day.dayOfMonth, hour, minute)
                        time = zone.rules.getValidOffsets(local).singleOrNull()?.let { local.toInstant(it).toEpochMilli() }
                            ?.takeIf { it in 1..System.currentTimeMillis() } ?: 0L
                        selection.visibility = if (time > 0) View.VISIBLE else View.GONE
                        if (time > 0) selection.text = java.text.DateFormat.getDateTimeInstance().format(java.util.Date(time))
                        else Toast.makeText(activity, R.string.health_report_invalid_time, Toast.LENGTH_SHORT).show()
                        update()
                    }, 8, 0, DateFormat.is24HourFormat(activity)).apply { show() }
                }
                if (pickedDate != null) pickTime(pickedDate) else {
                    val today = LocalDate.now(zone)
                    picker = DatePickerDialog(activity, { _, y, m, d -> pickTime(LocalDate.of(y, m + 1, d)) },
                        today.year, today.monthValue - 1, today.dayOfMonth).apply {
                        datePicker.maxDate = System.currentTimeMillis(); show()
                    }
                }
            }.apply { tag = "health-report-pick-time" }, 8)
            fields.addView(selection)
        }
        if (plan.needsFasting) {
            views.add(fields, views.text(activity.getString(R.string.health_report_fasting_prompt), bold = true), 12)
            fields.addView(RadioGroup(activity).apply {
                listOf("fasting" to R.string.health_fasting, "non_fasting" to R.string.health_report_non_fasting,
                    "unspecified" to R.string.health_report_fasting_unknown).forEach { (value, title) ->
                    addView(RadioButton(activity).apply {
                        id = View.generateViewId(); tag = "health-report-$value"
                        setText(title); setOnClickListener { fasting = value; update() }
                    })
                }
            })
        }
        dialog = AlertDialog.Builder(activity).setTitle(R.string.health_report_supplement)
            .setView(ScrollView(activity).apply { addView(fields) })
            .setNegativeButton(android.R.string.cancel, null)
            .setPositiveButton(R.string.health_report_save_all) { _, _ -> save(HealthReportSupplement(time, fasting)) }.show()
        update()
    }
}

package com.galaxyssi.chat

import android.app.Activity
import android.app.AlertDialog
import java.time.LocalDate

internal fun HealthMeasurementPeriod.label(activity: Activity): String = if (kind == HealthMeasurementPeriodKind.MONTH)
    activity.getString(R.string.health_period_month_label, first.year, first.monthValue)
else activity.getString(R.string.health_period_week_label, first.toString(), end.minusDays(1).toString())

internal fun showHealthPeriodPicker(activity: Activity, title: Int, show: (android.app.Dialog) -> Unit,
    fetch: (LocalDate?, (HealthMeasurementPeriodPage) -> Unit) -> Unit, select: (HealthMeasurementPeriod) -> Unit,
    before: LocalDate? = null, history: List<LocalDate?> = emptyList()) {
    fetch(before) { page ->
        val builder = AlertDialog.Builder(activity).setTitle(title)
        if (page.periods.isEmpty()) builder.setMessage(R.string.health_no_records)
        else builder.setItems(page.periods.map { it.label(activity) }.toTypedArray()) { _, index -> select(page.periods[index]) }
        page.next?.let { next -> builder.setPositiveButton(R.string.health_next_page) { _, _ ->
            showHealthPeriodPicker(activity, title, show, fetch, select, next, history + before)
        } }
        if (history.isNotEmpty()) builder.setNeutralButton(R.string.health_previous_page) { _, _ ->
            showHealthPeriodPicker(activity, title, show, fetch, select, history.last(), history.dropLast(1))
        }
        builder.setNegativeButton(android.R.string.cancel, null)
        show(builder.create())
    }
}

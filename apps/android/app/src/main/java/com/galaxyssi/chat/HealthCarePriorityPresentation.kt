package com.galaxyssi.chat

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.widget.LinearLayout
import android.widget.Toast
import java.text.DateFormat
import java.util.Date

internal object HealthCarePriorityPresentation {
    fun add(activity: Activity, parent: LinearLayout, value: HealthCareConcern, compact: Boolean = false,
        open: () -> Unit = {}) {
        if (HealthCarePriority.rank(value.assessment) == 0) return
        val ui = HealthCenterViews(activity)
        val text = if (compact) listOf(R.string.health_care_bp_emergency) else listOf(R.string.health_care_bp_emergency,
            R.string.health_care_bp_recheck, R.string.health_care_bp_scope, R.string.health_care_bp_history)
        ui.add(parent, ui.column().apply {
            tag = "health-care-priority-notice"
            ui.add(this, ui.text(activity.getString(R.string.health_care_bp_title), 17f, bold = true))
            ui.add(this, ui.text(activity.getString(R.string.health_care_bp_record,
                DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT).format(Date(value.assessment.measuredAt)),
                value.assessment.value, value.assessment.unit), 13f, muted = true), 6)
            text.forEach { ui.add(this, ui.text(activity.getString(it), 14f), 8) }
            ui.add(this, ui.profileRow(activity.getString(if (compact) R.string.health_care_bp_details else R.string.health_care_bp_source)) {
                if (compact) open() else runCatching { activity.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(HealthCarePriority.SOURCE))) }
                    .onFailure { Toast.makeText(activity, R.string.health_storage_error, Toast.LENGTH_LONG).show() }
            }.apply { tag = "health-care-priority-details" }, 4)
        }, 8)
    }
}

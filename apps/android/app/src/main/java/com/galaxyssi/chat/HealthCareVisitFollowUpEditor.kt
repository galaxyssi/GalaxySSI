package com.galaxyssi.chat

import android.app.Activity
import android.app.AlertDialog
import android.widget.CheckBox
import android.widget.EditText
import android.widget.RadioButton
import android.widget.RadioGroup
import android.widget.ScrollView

internal fun HealthCareVisitFollowUpState.label() = when (this) {
    HealthCareVisitFollowUpState.ACTIVE -> R.string.health_visit_followup_active
    HealthCareVisitFollowUpState.REVIEW -> R.string.health_visit_followup_review_needed
    HealthCareVisitFollowUpState.PAUSED -> R.string.health_visit_followup_paused
    HealthCareVisitFollowUpState.ARCHIVED -> R.string.health_visit_followup_archived
}
internal fun HealthCareVisitFollowUpKind.label() = when (this) {
    HealthCareVisitFollowUpKind.START -> R.string.health_visit_followup_start
    HealthCareVisitFollowUpKind.CHECK_IN -> R.string.health_visit_followup_checkin
    HealthCareVisitFollowUpKind.REVIEW -> R.string.health_visit_followup_review
    HealthCareVisitFollowUpKind.PAUSE -> R.string.health_visit_followup_pause
    HealthCareVisitFollowUpKind.RESUME -> R.string.health_visit_followup_resume
    HealthCareVisitFollowUpKind.ARCHIVE -> R.string.health_visit_followup_archive
    HealthCareVisitFollowUpKind.REOPEN -> R.string.health_visit_followup_reopen
}
internal fun HealthCareVisitReviewDecision.label() = when (this) {
    HealthCareVisitReviewDecision.CONTINUE -> R.string.health_visit_followup_continue
    HealthCareVisitReviewDecision.DISCUSS_CHANGE -> R.string.health_visit_followup_discuss_change
    HealthCareVisitReviewDecision.DISCUSS_MAINTENANCE -> R.string.health_visit_followup_discuss_maintenance
}

internal class HealthCareVisitFollowUpEditor(private val activity: Activity) {
    private val ui = HealthCenterViews(activity)
    private var dialog: AlertDialog? = null
    private val inputs = mutableListOf<EditText>()
    fun clear() {
        dialog?.setOnDismissListener(null); dialog?.dismiss(); dialog = null
        inputs.forEach { it.setText("") }; inputs.clear()
    }
    fun show(kind: HealthCareVisitFollowUpKind, current: HealthCareVisitFollowUp?, save: (HealthCareVisitFollowUpInput) -> Unit) {
        clear()
        val content = ui.column().apply { setPadding(ui.dp(20), ui.dp(8), ui.dp(20), ui.dp(12)) }
        content.addView(ui.text(activity.getString(R.string.health_visit_followup_notice), 14f))
        fun field(label: Int, tag: String, value: String = "", max: Int = 2000): EditText {
            ui.add(content, ui.text(activity.getString(label), 14f, bold = true), 16)
            val input = activity.healthProfileInput(value, max, multiline = true).apply { minLines = 1; maxLines = 4; this.tag = tag }
            inputs += input; ui.add(content, input, 4); return input
        }
        val goal = if (kind in setOf(HealthCareVisitFollowUpKind.START, HealthCareVisitFollowUpKind.REVIEW))
            field(R.string.health_visit_followup_goal, "visit-followup-goal", current?.goal.orEmpty(), 1000) else null
        var feelings: EditText? = null; var function: EditText? = null; var sleep: EditText? = null; var barriers: EditText? = null
        val needsReview = CheckBox(activity).apply { text = activity.getString(R.string.health_visit_followup_needs_review); tag = "visit-followup-needs-review" }
        if (kind == HealthCareVisitFollowUpKind.CHECK_IN) {
            feelings = field(R.string.health_visit_followup_feelings, "visit-followup-feelings")
            function = field(R.string.health_visit_followup_function, "visit-followup-function")
            sleep = field(R.string.health_visit_followup_sleep, "visit-followup-sleep")
            barriers = field(R.string.health_visit_followup_barriers, "visit-followup-barriers")
            ui.add(content, needsReview, 12)
        }
        var decision: HealthCareVisitReviewDecision? = null
        if (kind == HealthCareVisitFollowUpKind.REVIEW) {
            ui.add(content, ui.text(activity.getString(R.string.health_visit_followup_review_notice), 14f), 12)
            val choices = RadioGroup(activity)
            HealthCareVisitReviewDecision.entries.forEach { entry -> choices.addView(RadioButton(activity).apply {
                id = android.view.View.generateViewId(); text = activity.getString(entry.label()); tag = "visit-followup-decision-${entry.name}"
                setOnClickListener { decision = entry }
            }) }
            ui.add(content, choices, 8)
        }
        val note = field(if (kind in setOf(HealthCareVisitFollowUpKind.CHECK_IN, HealthCareVisitFollowUpKind.START))
            R.string.health_visit_followup_note else R.string.health_visit_followup_reason, "visit-followup-note")
        val acknowledge = CheckBox(activity).apply {
            text = activity.getString(R.string.health_visit_followup_archive_notice); tag = "visit-followup-acknowledge"
        }
        if (kind == HealthCareVisitFollowUpKind.ARCHIVE) ui.add(content, acknowledge, 12)
        val error = ui.text("", 13f); ui.add(content, error, 8)
        dialog = AlertDialog.Builder(activity).setTitle(kind.label()).setView(ScrollView(activity).apply { addView(content) })
            .setNegativeButton(R.string.common_cancel, null).setPositiveButton(R.string.health_visit_followup_save, null).show().also { popup ->
                popup.setOnDismissListener { clear() }
                popup.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener {
                    if (kind == HealthCareVisitFollowUpKind.ARCHIVE && !acknowledge.isChecked) {
                        error.setText(R.string.health_visit_followup_archive_notice); return@setOnClickListener
                    }
                    val input = runCatching { HealthCareVisitFollowUpInput(kind, goal?.text?.toString()?.trim().orEmpty(),
                        feelings?.text?.toString()?.trim().orEmpty(), function?.text?.toString()?.trim().orEmpty(), sleep?.text?.toString()?.trim().orEmpty(),
                        barriers?.text?.toString()?.trim().orEmpty(), note.text.toString().trim(), needsReview.isChecked, decision) }.getOrElse {
                        error.setText(R.string.health_visit_followup_invalid); return@setOnClickListener
                    }
                    clear(); save(input)
                }
            }
    }
}

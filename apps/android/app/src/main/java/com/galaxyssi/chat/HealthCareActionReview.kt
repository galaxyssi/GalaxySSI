package com.galaxyssi.chat

import android.app.Activity
import android.app.AlertDialog
import android.app.DatePickerDialog
import android.app.TimePickerDialog
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.text.InputFilter
import android.text.InputType
import android.view.View
import android.view.inputmethod.EditorInfo
import android.widget.EditText
import android.widget.RadioButton
import android.widget.RadioGroup
import android.widget.ScrollView
import android.widget.Toast
import java.text.DateFormat
import java.util.Calendar
import java.util.Date
import java.util.UUID
import java.util.concurrent.Executors

/** Explicit local actions shared by the Agent page and the durable health concern. */
internal class HealthCareActionReview(private val activity: Activity, private val names: HealthOverviewDatabases) {
    private val ui = HealthCenterViews(activity)
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private var generation = 0
    private var dialog: AlertDialog? = null
    private var busy = false
    fun clear() { generation++; dialog?.dismiss(); dialog = null }
    fun destroy() { clear(); worker.shutdown() }
    private data class Snapshot(val issue: HealthCareConcern, val action: HealthCareAction, val reminder: HealthCareReminder?,
        val notifications: Boolean, val eligible: Boolean, val evidence: HealthCareEvidence?, val instruction: HealthCareInstruction?)

    fun show(concernId: String, actionId: String) {
        if (busy) return
        clear(); val token = generation
        worker.execute {
            val result = runCatching {
                HealthCareEngine.evaluate(activity, names)
                val permission = HealthPrivacyStore(activity, names.privacy).use { it.policy() }
                check(permission.metrics && permission.profile)
                HealthCareStore(activity, names.care).use { store ->
                    val issue = store.concern(concernId) ?: throw HealthCareConflict()
                    val action = issue.actions.firstOrNull { it.id == actionId } ?: throw HealthCareConflict()
                    val settings = store.settings()
                    val source = HealthRecordStore(activity, names.records).use {
                        HealthCareEngine.inputVersion(settings.version, permission.version, it.metricVersion(issue.metric))
                    }
                    Snapshot(issue, action, store.reminder(actionId),
                        HealthReminderStore(activity, names.reminders).use { it.settings().notifications } && HealthReminderWork.systemAllowed(activity),
                        HealthCareFollowUpPolicy.eligible(issue, action, settings, permission, source) &&
                            HealthCareInstructionAccess.current(activity, names, store, issue, action),
                        action.evidenceId.takeIf(String::isNotBlank)?.let(store::evidence)?.takeIf { it.grant.concernId == issue.id },
                        action.instruction?.let { ref -> store.instructionHistory(issue.id, ref.instructionId, ref.revision + 1, 1)
                            .items.singleOrNull()?.takeIf { it.revision == ref.revision } })
                }
            }
            main.post { if (token == generation && !activity.isFinishing && !activity.isDestroyed) result.fold(::render, { error() }) }
        }
    }
    private fun render(value: Snapshot) {
        val content = ui.column().apply { setPadding(ui.dp(20), ui.dp(8), ui.dp(20), ui.dp(16)) }
        content.addView(ui.text(value.action.description, 18f, bold = true))
        ui.add(content, ui.text(value.action.rationale, 14f), 8)
        value.action.visitReview?.let { ref ->
            ui.add(content, ui.text(activity.getString(R.string.health_visit_review_notice), 14f, muted = true), 8)
            ui.add(content, ui.profileRow(activity.getString(R.string.health_visit_followup_title)) {
                activity.startActivity(Intent(activity, HealthCareVisitFollowUpActivity::class.java).putHealthNavigationFixture(names)
                    .putExtra("health_care_id", value.issue.id).putExtra("health_encounter_id", ref.encounter))
            }.apply { tag = "health-visit-review-source" }, 8)
        }
        value.action.instruction?.let { ref ->
            ui.add(content, ui.text(activity.getString(R.string.health_instruction_action_notice), 14f, muted = true), 8)
            ui.add(content, ui.text(activity.getString(R.string.health_revision, ref.revision) + " · " +
                activity.getString(R.string.health_document_page, ref.original.page, ref.original.pageCount), 13f, muted = true), 8)
            value.instruction?.let { instruction ->
                instruction.draft.required.forEach { field ->
                    val item = instruction.draft.fields[field]
                    ui.add(content, ui.text(activity.getString(field.label()) + ": " +
                        (item?.text?.takeIf(String::isNotBlank) ?: activity.getString(R.string.health_instruction_not_stated)), 14f), 4)
                }
            }
            ui.add(content, ui.profileRow(activity.getString(R.string.health_instruction_action_source)) {
                activity.startActivity(Intent(activity, HealthCareInstructionsActivity::class.java).putHealthNavigationFixture(names)
                    .putExtra("health_care_id", value.issue.id).putExtra("health_encounter_id", ref.encounterId))
            }, 8)
        }
        value.evidence?.let { evidence ->
            ui.add(content, ui.profileRow(evidence.title, evidence.url) {
                runCatching { activity.startActivity(Intent(Intent.ACTION_VIEW, android.net.Uri.parse(evidence.url))) }.onFailure { error() }
            }, 8)
            ui.add(content, ui.text(value.action.supportingQuote, 14f), 4)
            ui.add(content, ui.text(activity.getString(R.string.health_care_evidence_read, date(evidence.retrievedAt),
                date(evidence.observedAt)), 13f, muted = true), 4)
            ui.add(content, ui.text(activity.getString(R.string.health_care_evidence_scope), 13f, muted = true), 4)
        }
        value.action.dueFrom?.let { ui.add(content, ui.text(activity.getString(R.string.health_care_plan_window,
            date(it), date(value.action.dueUntil!!)), 14f, muted = true), 8) }
        ui.add(content, ui.text(activity.getString(R.string.health_care_followup_time_notice), 14f, muted = true), 8)
        val reminder = value.reminder
        if (reminder != null) ui.add(content, ui.text(activity.getString(reminder.state.label(),
            date(if (reminder.state == HealthCareReminderState.DELIVERED) reminder.updatedAt else reminder.dueAt)), 14f)
            .apply { tag = "health-care-reminder-status" }, 8)
        if (!value.notifications) ui.add(content, ui.profileRow(activity.getString(R.string.health_care_followup_in_app)) {
            if (names.fixture == null) activity.startActivity(Intent(activity, HealthReminderActivity::class.java))
        }, 8)
        if (value.eligible) {
            ui.add(content, ui.command(R.string.health_care_followup_schedule) { pickTime(value) }
                .apply { tag = "health-care-followup-schedule" }, 12)
        } else ui.add(content, ui.text(activity.getString(R.string.health_care_followup_stale), 14f), 8)
        if (reminder != null && reminder.state != HealthCareReminderState.CANCELLED) {
            ui.add(content, ui.profileRow(activity.getString(R.string.health_care_followup_cancel)) {
                change { it.cancelReminder(reminder.actionId, reminder.token, System.currentTimeMillis()) }
            }.apply { tag = "health-care-followup-cancel" }, 8)
        }
        if (value.action.state == HealthCareActionState.CONFIRMED && value.issue.open) {
            ui.add(content, ui.command(R.string.health_care_followup_complete) { outcome(value) }
                .apply { tag = "health-care-followup-complete" }, 12)
        }
        if (value.action.outcome.isNotBlank()) ui.add(content, ui.text(value.action.outcome, 15f), 8)
        value.action.feedback?.let { feedback ->
            ui.add(content, ui.text(activity.getString(R.string.health_feedback_latest,
                activity.getString(feedback.kind.label()), date(feedback.recordedAt)), 14f, muted = true), 8)
            if (value.action.outcome != feedback.note) ui.add(content, ui.text(feedback.note, 15f), 4)
        }
        ui.add(content, ui.profileRow(activity.getString(R.string.health_feedback_history)) {
            showHistory(value.issue.id, value.action.id)
        }.apply { tag = "health-feedback-history" }, 8)
        dialog = AlertDialog.Builder(activity).setTitle(R.string.health_care_followup_title)
            .setView(ScrollView(activity).apply { addView(content) }).setNegativeButton(R.string.common_cancel, null).create().also {
                it.setOnDismissListener { content.removeAllViews() }; it.show()
            }
    }
    private fun pickTime(value: Snapshot) {
        dialog?.dismiss()
        val calendar = Calendar.getInstance().apply { timeInMillis = maxOf(System.currentTimeMillis() + 3_600_000L, value.reminder?.dueAt ?: 0L) }
        dialog = DatePickerDialog(activity, { _, year, month, day ->
            calendar.set(Calendar.YEAR, year); calendar.set(Calendar.MONTH, month); calendar.set(Calendar.DAY_OF_MONTH, day)
            dialog = TimePickerDialog(activity, { _, hour, minute ->
                calendar.set(Calendar.HOUR_OF_DAY, hour); calendar.set(Calendar.MINUTE, minute)
                calendar.set(Calendar.SECOND, 0); calendar.set(Calendar.MILLISECOND, 0)
                val at = calendar.timeInMillis
                if (at <= System.currentTimeMillis()) {
                    Toast.makeText(activity, R.string.health_care_followup_future_time, Toast.LENGTH_LONG).show()
                    return@TimePickerDialog
                }
                confirmTime(value, at)
            }, calendar.get(Calendar.HOUR_OF_DAY), calendar.get(Calendar.MINUTE), android.text.format.DateFormat.is24HourFormat(activity))
                .also { it.setTitle(R.string.health_care_followup_schedule); it.show() }
        }, calendar.get(Calendar.YEAR), calendar.get(Calendar.MONTH), calendar.get(Calendar.DAY_OF_MONTH)).also { it.show() }
    }
    private fun confirmTime(value: Snapshot, at: Long) {
        val outside = value.action.dueFrom?.let { at !in it..value.action.dueUntil!! } == true
        val text = activity.getString(R.string.health_care_followup_confirm_time, date(at)) +
            if (outside) "\n" + activity.getString(R.string.health_care_followup_outside) else ""
        dialog = AlertDialog.Builder(activity).setTitle(R.string.health_care_followup_schedule).setMessage(text)
            .setNegativeButton(R.string.common_cancel, null).setPositiveButton(android.R.string.ok) { _, _ ->
                change { store ->
                    val permission = HealthPrivacyStore(activity, names.privacy).use { it.policy() }
                    val source = HealthRecordStore(activity, names.records).use {
                        HealthCareEngine.inputVersion(store.settings().version, permission.version, it.metricVersion(value.issue.metric))
                    }
                    store.scheduleReminder(value.issue.id, value.action.id, value.issue.revision, value.reminder?.token,
                        permission, source, at, System.currentTimeMillis()) { ref -> HealthCareInstructionAccess.available(activity, names, ref) }
                }
            }.show()
    }
    private fun outcome(value: Snapshot) {
        dialog?.dismiss()
        val operationId = UUID.randomUUID().toString()
        val content = ui.column().apply { setPadding(ui.dp(20), ui.dp(8), ui.dp(20), ui.dp(16)) }
        val choices = RadioGroup(activity)
        HealthCareFeedbackKind.entries.forEach { kind -> choices.addView(RadioButton(activity).apply {
            id = kind.ordinal + 1; text = activity.getString(kind.label()); minHeight = ui.dp(48)
            tag = "health-feedback-kind-${kind.name}"
        }) }
        content.addView(choices)
        val input = EditText(activity).apply {
            tag = "health-care-followup-outcome"; isSaveEnabled = false
            importantForAutofill = View.IMPORTANT_FOR_AUTOFILL_NO_EXCLUDE_DESCENDANTS
            imeOptions = EditorInfo.IME_FLAG_NO_PERSONALIZED_LEARNING
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_MULTI_LINE
            filters = arrayOf(InputFilter.LengthFilter(2000)); minLines = 3; maxLines = 6
            hint = activity.getString(R.string.health_feedback_note_hint)
        }
        ui.add(content, input, 8)
        ui.add(content, ui.text(activity.getString(R.string.health_feedback_notice), 14f, muted = true), 8)
        dialog = AlertDialog.Builder(activity).setTitle(R.string.health_care_followup_complete)
            .setView(ScrollView(activity).apply { addView(content) }).setNegativeButton(R.string.common_cancel, null)
            .setPositiveButton(android.R.string.ok, null).create().also { d ->
                d.setOnDismissListener { input.text.clear(); content.removeAllViews() }
                d.setOnShowListener { d.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener {
                    val kind = HealthCareFeedbackKind.entries.firstOrNull { it.ordinal + 1 == choices.checkedRadioButtonId }
                    if (kind == null) {
                        Toast.makeText(activity, R.string.health_feedback_choose, Toast.LENGTH_SHORT).show(); return@setOnClickListener
                    }
                    val note = input.text.toString().trim()
                    if (note.isBlank()) { input.error = activity.getString(R.string.health_feedback_note_hint); return@setOnClickListener }
                    change { store ->
                        val permission = HealthPrivacyStore(activity, names.privacy).use { it.policy() }
                        check(permission.metrics && permission.profile)
                        store.recordActionFeedback(value.issue.id, value.issue.revision, value.action.id, kind, note, operationId, System.currentTimeMillis())
                    }
                } }; d.show()
            }
    }
    fun showHistory(concernId: String, actionId: String? = null, before: Int = Int.MAX_VALUE) {
        if (busy) return
        clear(); val token = generation
        worker.execute {
            val result = runCatching {
                val permission = HealthPrivacyStore(activity, names.privacy).use { it.policy() }
                check(permission.metrics && permission.profile)
                val page = HealthCareStore(activity, names.care).use { store ->
                    checkNotNull(store.concern(concernId)); store.feedback(concernId, actionId, before)
                }
                check(HealthPrivacyStore(activity, names.privacy).use { it.policy() } == permission)
                page
            }
            main.post { if (token == generation && !activity.isFinishing && !activity.isDestroyed) result.fold({ page ->
                val content = ui.column().apply { setPadding(ui.dp(20), ui.dp(8), ui.dp(20), ui.dp(16)) }
                if (page.items.isEmpty()) content.addView(ui.text(activity.getString(R.string.health_feedback_empty), 15f, muted = true))
                page.items.forEach { receipt -> ui.add(content, ui.profileRow(receipt.actionTitle,
                    "${activity.getString(receipt.feedback.kind.label())} · ${date(receipt.feedback.recordedAt)}\n${receipt.feedback.note}") {
                    dialog?.dismiss()
                    dialog = AlertDialog.Builder(activity).setTitle(receipt.actionTitle)
                        .setMessage("${activity.getString(receipt.feedback.kind.label())} · ${date(receipt.feedback.recordedAt)}\n\n" +
                            receipt.feedback.note + "\n\n" + activity.getString(R.string.health_feedback_history_notice))
                        .setNegativeButton(R.string.health_feedback_history) { _, _ -> showHistory(concernId, actionId, before) }.show()
                }.apply { tag = "health-feedback-row-${receipt.feedback.id}" }, 8) }
                dialog = AlertDialog.Builder(activity).setTitle(R.string.health_feedback_history)
                    .setView(ScrollView(activity).apply { addView(content) }).setNegativeButton(R.string.common_cancel, null)
                    .apply {
                        page.next?.let { next -> setPositiveButton(R.string.health_feedback_older) { _, _ -> showHistory(concernId, actionId, next) } }
                        if (before != Int.MAX_VALUE) setNeutralButton(R.string.health_feedback_latest_page) { _, _ -> showHistory(concernId, actionId) }
                    }.create().also { it.setOnDismissListener { content.removeAllViews() }; it.show() }
            }, { error() }) }
        }
    }
    private fun change(action: (HealthCareStore) -> Unit) {
        if (busy) return
        busy = true; clear(); val token = generation
        worker.execute {
            val result = runCatching { HealthCareStore(activity, names.care).use(action) }
            main.post {
                busy = false
                if (token == generation && !activity.isFinishing && !activity.isDestroyed) {
                    if (result.isFailure) error() else Toast.makeText(activity, R.string.health_care_plan_saved, Toast.LENGTH_SHORT).show()
                }
            }
        }
    }
    private fun date(value: Long) = DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT).format(Date(value))
    private fun error() = Toast.makeText(activity, R.string.health_care_plan_changed, Toast.LENGTH_LONG).show()
}

internal fun HealthCareReminderState.label(): Int = when (this) {
    HealthCareReminderState.SCHEDULED -> R.string.health_care_followup_scheduled
    HealthCareReminderState.DELIVERED -> R.string.health_care_followup_delivered
    HealthCareReminderState.CANCELLED -> R.string.health_care_followup_cancelled
}

internal fun HealthCareFeedbackKind.label(): Int = when (this) {
    HealthCareFeedbackKind.COMPLETED -> R.string.health_feedback_completed
    HealthCareFeedbackKind.PARTIAL -> R.string.health_feedback_partial
    HealthCareFeedbackKind.BARRIER -> R.string.health_feedback_barrier
}

package com.galaxyssi.chat

import android.app.Activity
import android.app.AlertDialog
import android.text.InputFilter
import android.text.InputType
import android.view.View
import android.view.inputmethod.EditorInfo
import android.widget.ArrayAdapter
import android.widget.EditText
import android.widget.ScrollView
import android.widget.Spinner
import android.widget.Toast
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.cancelChildren
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.text.DateFormat
import java.util.Date

/** Native Personal Health review; models can propose questions but cannot confirm their answers. */
internal class HealthCareQuestionReview(private val activity: Activity, private val names: HealthOverviewDatabases) {
    private val tasks = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private val ui = HealthCenterViews(activity)
    private var generation = 0
    private var dialog: AlertDialog? = null
    private data class Snapshot(val issue: HealthCareConcern, val privacy: HealthPrivacyPolicy,
        val page: HealthCareQuestionPage, val known: Map<String, String>)
    fun clear() { generation++; tasks.coroutineContext.cancelChildren(); dialog?.dismiss(); dialog = null }
    fun destroy() { clear(); tasks.cancel() }
    fun show(id: String, after: String = "") {
        clear()
        work {
            HealthCareEngine.evaluate(activity, names)
            val privacy = HealthPrivacyStore(activity, names.privacy).use { it.policy() }
            check(privacy.metrics && privacy.profile)
            val snapshot = HealthCareStore(activity, names.care).use { store ->
                val issue = store.concern(id) ?: throw HealthCareConflict()
                val profile = issue.profileLink?.let { HealthCareProfileAccess.capture(activity, it, names) }
                Snapshot(issue, privacy, store.questions(issue, after), HealthCareQuestionPolicy.known(issue, profile))
            }
            val done: () -> Unit = { list(snapshot, after.isNotEmpty()) }; done
        }
    }
    private fun content() = ui.column().apply {
        setPadding(ui.dp(20), ui.dp(8), ui.dp(20), ui.dp(16)); isSaveEnabled = false
        importantForAutofill = View.IMPORTANT_FOR_AUTOFILL_NO_EXCLUDE_DESCENDANTS
    }
    private fun display(content: android.widget.LinearLayout, title: Int, save: (() -> Unit)? = null) {
        val next = AlertDialog.Builder(activity).setTitle(title)
            .setView(ScrollView(activity).apply { addView(content); isSaveEnabled = false })
            .setNegativeButton(R.string.common_cancel, null).apply { if (save != null) setPositiveButton(R.string.health_question_save, null) }
            .create()
        dialog = next
        next.setOnDismissListener { content.removeAllViews(); if (dialog === next) dialog = null }
        next.show()
        if (save != null) next.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener { save() }
    }
    private fun list(snapshot: Snapshot, paged: Boolean) {
        val content = content()
        if (snapshot.page.items.isEmpty()) ui.add(content, ui.text(activity.getString(R.string.health_question_empty), 15f), 8)
        snapshot.page.items.forEach { question ->
            val value = HealthCareQuestionPolicy.view(question, snapshot.issue, snapshot.known)
            ui.add(content, ui.profileRow(question.question, activity.getString(label(value.getString("state")))) {
                clear(); edit(snapshot, question)
            }.apply { tag = "health-question-row-${question.id}" }, 8)
        }
        snapshot.page.next?.let { cursor -> ui.add(content, ui.command(R.string.health_care_more) { show(snapshot.issue.id, cursor) }
            .apply { tag = "health-question-next" }, 12) }
        if (paged) ui.add(content, ui.profileRow(activity.getString(R.string.health_question_first)) { show(snapshot.issue.id) }, 8)
        display(content, R.string.health_question_title)
    }
    private fun edit(snapshot: Snapshot, question: HealthCareQuestion) {
        val value = HealthCareQuestionPolicy.view(question, snapshot.issue, snapshot.known)
        val content = content()
        ui.add(content, ui.text(question.question, 17f, bold = true), 4)
        ui.add(content, ui.text(question.purpose, 14f), 8)
        ui.add(content, ui.text(activity.getString(R.string.health_question_record_time,
            DateFormat.getDateTimeInstance(DateFormat.SHORT, DateFormat.SHORT).format(Date(question.measuredAt))), 13f, muted = true), 8)
        if (question.basis != HealthCareQuestionPolicy.basis(snapshot.issue)) {
            ui.add(content, ui.text(activity.getString(R.string.health_question_stale_notice), 14f), 8)
            ui.add(content, ui.text(activity.getString(R.string.health_question_current_time,
                DateFormat.getDateTimeInstance(DateFormat.SHORT, DateFormat.SHORT).format(Date(snapshot.issue.assessment.measuredAt))), 13f), 4)
        }
        snapshot.known[question.key]?.let { fact ->
            val readable = when (fact) { "YES" -> activity.getString(R.string.health_care_yes); "NO" -> activity.getString(R.string.health_care_no)
                else -> runCatching { org.json.JSONObject(fact).let { j -> j.optJSONObject("value")?.let {
                    listOf(it.optString("text"), it.optString("unit")).filter(String::isNotBlank).joinToString(" ")
                } ?: j.opt("age_on_measurement_date").toString() } }.getOrDefault(fact) }
            ui.add(content, ui.text(activity.getString(R.string.health_question_saved_fact, readable), 14f, bold = true), 8)
        }
        ui.add(content, ui.text(activity.getString(R.string.health_question_answer_notice), 13f, muted = true), 8)
        val states = HealthCareQuestionState.entries
        val options = Spinner(activity).apply {
            tag = "health-question-state"
            adapter = ArrayAdapter(activity, android.R.layout.simple_spinner_dropdown_item, states.map { activity.getString(label(it.name)) })
            setSelection(question.state.ordinal); isSaveEnabled = false
        }
        ui.add(content, options, 8)
        val input = EditText(activity).apply {
            tag = "health-question-answer"; setText(value.optString("reviewed_answer", ""))
            hint = activity.getString(R.string.health_question_answer); inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_MULTI_LINE
            minLines = 2; maxLines = 6; filters = arrayOf(InputFilter.LengthFilter(2000)); isSaveEnabled = false
            importantForAutofill = View.IMPORTANT_FOR_AUTOFILL_NO_EXCLUDE_DESCENDANTS
            imeOptions = EditorInfo.IME_FLAG_NO_PERSONALIZED_LEARNING
        }
        ui.add(content, input, 8)
        display(content, R.string.health_question_review) {
            val state = states[options.selectedItemPosition]
            val answer = if (state in setOf(HealthCareQuestionState.ANSWERED, HealthCareQuestionState.CONFLICT)) input.text.toString().trim() else ""
            if (state in setOf(HealthCareQuestionState.ANSWERED, HealthCareQuestionState.CONFLICT) && answer.isBlank()) {
                input.error = activity.getString(R.string.health_question_answer_required)
            } else {
                dialog?.getButton(AlertDialog.BUTTON_POSITIVE)?.isEnabled = false
                work {
                    check(HealthPrivacyStore(activity, names.privacy).use { it.policy() } == snapshot.privacy)
                    if (!HealthCareProfileAccess.current(activity, snapshot.issue.profileLink, names)) throw HealthCareConflict()
                    HealthCareStore(activity, names.care).use { care ->
                        val source = HealthRecordStore(activity, names.records).use {
                            HealthCareEngine.inputVersion(care.settings().version, snapshot.privacy.version, it.metricVersion(snapshot.issue.metric))
                        }
                        if (source != snapshot.issue.inputVersion) throw HealthCareConflict()
                        care.reviewQuestion(snapshot.issue.id, snapshot.issue.revision, question.id, question.revision, state, answer, System.currentTimeMillis())
                    }
                    val done: () -> Unit = { clear(); Toast.makeText(activity, R.string.health_question_saved, Toast.LENGTH_SHORT).show() }; done
                }
            }
        }
    }
    private fun work(action: () -> (() -> Unit)) {
        val token = generation
        tasks.launch {
            try {
                val done = withContext(Dispatchers.IO) { action() }
                if (generation == token && !activity.isFinishing && !activity.isDestroyed) done()
            } catch (failure: Exception) {
                if (failure is CancellationException) throw failure
                if (generation == token && !activity.isFinishing && !activity.isDestroyed) {
                    clear(); Toast.makeText(activity, R.string.health_care_changed, Toast.LENGTH_LONG).show()
                }
            }
        }
    }
    companion object {
        fun label(state: String): Int = when (state) {
            "ANSWERED" -> R.string.health_question_answered
            "DEFERRED" -> R.string.health_question_deferred
            "DECLINED" -> R.string.health_question_declined
            "CONFLICT" -> R.string.health_question_conflict
            "STALE" -> R.string.health_question_stale
            else -> R.string.health_question_open
        }
    }
}

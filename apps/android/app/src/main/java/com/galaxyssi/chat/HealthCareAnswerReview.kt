package com.galaxyssi.chat

import android.app.Activity
import android.app.AlertDialog
import android.text.InputFilter
import android.text.InputType
import android.view.View
import android.view.inputmethod.EditorInfo
import android.widget.EditText
import android.widget.ScrollView
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

/** Shares the existing health review entry, without changing the Agent composer or message layout. */
internal class HealthCareAnswerReview(private val activity: Activity, private val names: HealthOverviewDatabases,
    private val source: (HealthCareAnswerDraft) -> AgentTranscriptEntry? = { draft ->
        if (names.fixture != null) null else AgentTranscriptStore(activity).let { store ->
            store.conversation(draft.grant.conversationId)?.takeIf {
                it.privateMode && it.trackingPaused && it.status == AgentConversationStatus.ACTIVE
            }?.let { store.fullEntry(draft.sourceId) }
        }
    }) {
    private val tasks = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private val ui = HealthCenterViews(activity)
    private var generation = 0
    private var dialog: AlertDialog? = null
    private data class Preview(val draft: HealthCareAnswerDraft, val question: HealthCareQuestion, val current: Boolean, val measuredAt: Long)
    fun clear() { generation++; tasks.coroutineContext.cancelChildren(); dialog?.dismiss(); dialog = null }
    fun destroy() { clear(); tasks.cancel() }
    private fun content() = ui.column().apply {
        setPadding(ui.dp(20), ui.dp(8), ui.dp(20), ui.dp(16)); isSaveEnabled = false
        importantForAutofill = View.IMPORTANT_FOR_AUTOFILL_NO_EXCLUDE_DESCENDANTS
    }
    private fun display(content: android.widget.LinearLayout, save: (() -> Unit)? = null, discard: (() -> Unit)? = null) {
        val next = AlertDialog.Builder(activity).setTitle(R.string.health_answer_title)
            .setView(ScrollView(activity).apply { addView(content); isSaveEnabled = false })
            .setNegativeButton(R.string.common_cancel, null).apply {
                if (save != null) setPositiveButton(R.string.health_question_save, null)
                if (discard != null) setNeutralButton(R.string.health_answer_discard, null)
            }.create()
        dialog = next
        next.setOnDismissListener { content.removeAllViews(); if (dialog === next) dialog = null }
        next.show()
        save?.let { action -> next.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener { action() } }
        discard?.let { action -> next.getButton(AlertDialog.BUTTON_NEUTRAL).setOnClickListener { action() } }
    }
    fun show(id: String, after: String = "") {
        clear()
        work {
            HealthCareEngine.evaluate(activity, names)
            permission()
            val page = HealthCareStore(activity, names.care).use { care ->
                val issue = care.concern(id) ?: throw HealthCareConflict()
                care.answers(issue, after).let { result -> result to result.items.map { it to care.question(it.questionId) } }
            }
            val done: () -> Unit = {
                val content = content()
                if (page.second.isEmpty()) ui.add(content, ui.text(activity.getString(R.string.health_answer_empty), 15f), 8)
                page.second.forEach { (draft, question) ->
                    ui.add(content, ui.profileRow(question?.question ?: activity.getString(R.string.health_question_stale),
                        activity.getString(R.string.health_answer_pending)) { edit(draft.id) }
                        .apply { tag = "health-answer-row-${draft.id}" }, 8)
                }
                page.first.next?.let { next -> ui.add(content, ui.command(R.string.health_care_more) { show(id, next) }, 8) }
                if (after.isNotEmpty()) ui.add(content, ui.command(R.string.health_question_first) { show(id) }, 8)
                display(content)
            }; done
        }
    }
    private fun permission() = HealthPrivacyStore(activity, names.privacy).use { it.policy() }.also { check(it.metrics && it.profile) }
    private fun sourcesCurrent(issue: HealthCareConcern, settings: HealthCareSettings, privacy: HealthPrivacyPolicy) =
        HealthCareProfileAccess.current(activity, issue.profileLink, names) && HealthRecordStore(activity, names.records).use {
            issue.inputVersion == HealthCareEngine.inputVersion(settings.version, privacy.version, it.metricVersion(issue.metric))
        }
    private fun edit(id: String) {
        clear()
        work {
            val privacy = permission()
            val snapshot = HealthCareStore(activity, names.care).use { care ->
                val draft = care.answer(id) ?: throw HealthCareConflict()
                val issue = care.concern(draft.grant.concernId) ?: throw HealthCareConflict()
                val question = care.question(draft.questionId) ?: throw HealthCareConflict()
                check(draft.scope == HealthCareQuestionPolicy.scope(issue) && draft.state == HealthCareAnswerState.PENDING)
                val valid = HealthCareAnswerPolicy.current(draft, issue, question, care.settings(), privacy) &&
                    sourcesCurrent(issue, care.settings(), privacy) && source(draft)?.let {
                        it.id == draft.sourceId && HealthCareAnswerPolicy.userSource(draft.grant, it, draft.quote)
                    } == true
                Preview(draft, question, valid, issue.assessment.measuredAt)
            }
            val done: () -> Unit = {
                val (draft, question, valid, measuredAt) = snapshot
                val content = content()
                ui.add(content, ui.text(question.question, 17f, bold = true), 4)
                ui.add(content, ui.text(question.purpose, 14f), 8)
                ui.add(content, ui.text(activity.getString(R.string.health_question_current_time,
                    DateFormat.getDateTimeInstance(DateFormat.SHORT, DateFormat.SHORT).format(Date(measuredAt))), 13f, muted = true), 8)
                ui.add(content, ui.text(activity.getString(if (valid) R.string.health_answer_notice else R.string.health_answer_stale), 14f), 8)
                val input = EditText(activity).apply {
                    tag = "health-answer-input"; inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_MULTI_LINE
                    minLines = 2; maxLines = 6; filters = arrayOf(InputFilter.LengthFilter(2000)); isSaveEnabled = false
                    importantForAutofill = View.IMPORTANT_FOR_AUTOFILL_NO_EXCLUDE_DESCENDANTS
                    imeOptions = EditorInfo.IME_FLAG_NO_PERSONALIZED_LEARNING
                }
                if (valid) {
                    ui.add(content, ui.text(activity.getString(R.string.health_answer_quote, draft.quote), 14f, muted = true), 8)
                    if (question.answer.isNotBlank()) ui.add(content, ui.text(activity.getString(R.string.health_answer_previous, question.answer), 14f), 8)
                    input.setText(draft.answer); ui.add(content, input, 8)
                }
                val save: (() -> Unit)? = if (!valid) null else ({
                    val answer = input.text.toString().trim()
                    if (answer.isEmpty()) input.error = activity.getString(R.string.health_question_answer_required)
                    else finish(draft, true, answer, privacy)
                })
                display(content, save) { finish(draft, false, "", privacy) }
            }; done
        }
    }
    private fun finish(draft: HealthCareAnswerDraft, accept: Boolean, answer: String, privacy: HealthPrivacyPolicy) {
        dialog?.getButton(AlertDialog.BUTTON_POSITIVE)?.isEnabled = false
        dialog?.getButton(AlertDialog.BUTTON_NEUTRAL)?.isEnabled = false
        work {
            check(permission() == privacy)
            HealthCareStore(activity, names.care).use { care ->
                val issue = care.concern(draft.grant.concernId) ?: throw HealthCareConflict()
                if (accept && !sourcesCurrent(issue, care.settings(), privacy)) throw HealthCareConflict()
                val receipt = care.reviewAnswer(draft.id, accept, answer, privacy, if (accept) source(draft) else null, System.currentTimeMillis())
                if (receipt.state != if (accept) HealthCareAnswerState.ACCEPTED else HealthCareAnswerState.DISMISSED) throw HealthCareConflict()
            }
            val done: () -> Unit = {
                clear(); Toast.makeText(activity, if (accept) R.string.health_question_saved else R.string.health_answer_discarded, Toast.LENGTH_SHORT).show()
            }; done
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
}

package com.galaxyssi.chat

import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.widget.CheckBox
import android.widget.ScrollView
import android.widget.Toast
import org.json.JSONObject
import org.json.JSONArray
import java.util.concurrent.Executors

/** Separate consent for future model calls; a local tracking switch never grants network access. */
internal class HealthCareResearchReview(private val activity: Activity, private val names: HealthOverviewDatabases) {
    private val ui = HealthCenterViews(activity)
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private var generation = 0
    private var busy = false
    private var dialog: AlertDialog? = null
    private var questionReview: HealthCareQuestionReview? = null
    fun clear() { generation++; dialog?.dismiss(); dialog = null; questionReview?.clear() }
    fun destroy() { clear(); questionReview?.destroy(); worker.shutdown() }

    fun show(id: String) {
        if (busy) return
        clear()
        work {
            val privacy = HealthPrivacyStore(activity, names.privacy).use { it.policy() }
            check(privacy.metrics && privacy.profile) { activity.getString(R.string.health_overview_permission) }
            HealthCareStore(activity, names.care).use { care ->
                val issue = care.concern(id) ?: throw HealthCareConflict()
                val authorization = care.researchAuthorization(id)
                val job = care.latestResearchJob(id)
                val enabled = care.settings().enabled && HealthCareResearchPolicy.eligible(issue)
                val review = job?.let { care.modelReview(it.turnId) }
                val related = HealthCareRelatedContext.capture(care, authorization?.scope?.related?.keys.orEmpty())
                val done: () -> Unit = { render(issue, authorization, job, enabled, review, related) }
                done
            }
        }
    }

    private fun render(issue: HealthCareConcern, authorization: HealthCareResearchAuthorization?, job: HealthCareResearchJob?, enabled: Boolean,
        review: HealthCareModelReview?, related: Map<HealthMetric, String>) {
        val content = ui.column().apply { setPadding(ui.dp(20), ui.dp(8), ui.dp(20), ui.dp(16)) }
        content.addView(ui.text(activity.getString(issue.metric.titleResource()), 17f, bold = true))
        ui.add(content, ui.text(activity.getString(if (authorization?.active == true) R.string.health_research_on else R.string.health_research_off), 14f)
            .apply { tag = "health-research-authorization" }, 8)
        authorization?.scope?.let { scope -> ui.add(content, ui.text(destination(scope), 14f), 8) }
        if (authorization?.active == true && authorization.scope.related.isNotEmpty())
            ui.add(content, ui.text(activity.getString(R.string.health_related_selected,
                authorization.scope.related.keys.sortedBy { it.name }.joinToString(" / ") { activity.getString(it.titleResource()) }), 14f)
                .apply { tag = "health-research-related-scope" }, 8)
        if (authorization?.active == true) ui.add(content, ui.text(activity.getString(
            if (authorization.scope.feedbackHistoryShared) R.string.health_research_feedback_on else R.string.health_research_feedback_off), 14f)
            .apply { tag = "health-research-feedback-scope" }, 8)
        job?.let {
            ui.add(content, ui.text(activity.getString(it.state.titleResource()), 15f, bold = true).apply { tag = "health-research-state" }, 12)
            if (it.detail.isNotBlank()) ui.add(content, ui.text(it.detail, 14f), 6)
        }
        review?.let { value ->
            ui.add(content, ui.text(activity.getString(R.string.health_model_review_title), 16f, bold = true), 16)
            if (value.inputVersion != issue.inputVersion || value.trigger != HealthCareResearchPolicy.trigger(issue, System.currentTimeMillis(), related))
                ui.add(content, ui.text(activity.getString(R.string.health_model_review_historical), 14f), 6)
            ui.add(content, ui.text(value.input.summary, 15f).apply { tag = "health-model-review-summary" }, 8)
            listOf(R.string.health_model_review_reason to value.input.rationale,
                R.string.health_model_review_uncertainty to value.input.uncertainty,
                R.string.health_model_review_next to value.input.nextStep).forEach { (label, text) ->
                ui.add(content, ui.text(activity.getString(label), 14f, bold = true), 10)
                ui.add(content, ui.text(text, 14f), 4)
            }
            if (value.input.questions.isNotEmpty()) ui.add(content, ui.profileRow(
                activity.getString(R.string.health_model_review_questions, value.input.questions.size)) {
                dialog?.dismiss()
                val questions = questionReview ?: HealthCareQuestionReview(activity, names).also { questionReview = it }
                questions.show(issue.id, selected = value.input.questions.map { it.id }.toSet())
            }.apply { tag = "health-model-review-questions" }, 10)
            val events = value.input.events.joinToString(" / ") { event -> activity.getString(when (event) {
                HealthCareReviewEvent.SOURCE_CHANGE -> R.string.health_model_review_source
                HealthCareReviewEvent.USER_FEEDBACK -> R.string.health_model_review_feedback
                HealthCareReviewEvent.CONFIRMED_ACTION_DUE -> R.string.health_model_review_due
            }) }
            ui.add(content, ui.text(activity.getString(R.string.health_model_review_events, events), 14f), 10)
            ui.add(content, ui.text(activity.getString(R.string.health_model_review_notice), 13f), 10)
        }
        if (authorization?.active == true) ui.add(content, ui.profileRow(activity.getString(R.string.health_research_revoke)) {
            dialog?.dismiss()
            work {
                HealthCareStore(activity, names.care).use { it.revokeResearch(issue.id, authorization.id, System.currentTimeMillis()) }
                val done: () -> Unit = { show(issue.id) }
                done
            }
        }.apply { tag = "health-research-revoke" }, 12)
        if (enabled && names.fixture == null) ui.add(content, ui.profileRow(activity.getString(R.string.health_research_enable)) {
            dialog?.dismiss()
            work {
                val preview = HealthCareResearchRuntime.preview(activity.applicationContext, issue.id)
                val done: () -> Unit = { consent(preview, authorization?.id) }
                done
            }
        }.apply { tag = "health-research-enable" }, 12)
        if (names.fixture == null) ui.add(content, ui.profileRow(activity.getString(R.string.health_research_open)) {
            dialog?.dismiss()
            work {
                val conversation = HealthCareDiscussion.open(activity.applicationContext, issue.id)
                val done: () -> Unit = { activity.startActivity(Intent(activity, MainActivity::class.java)
                    .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                    .putExtra("galaxyssi_open_agent", true).putExtra("galaxyssi_agent_conversation_id", conversation)) }
                done
            }
        }, 8)
        display(AlertDialog.Builder(activity).setTitle(R.string.health_research_title)
            .setView(ScrollView(activity).apply { addView(content) }).setNegativeButton(R.string.common_cancel, null).create(), content::removeAllViews)
        if (review != null && HealthCareModelReviewVisibility.show(this, names.care, review.grant.conversationId) && names.fixture == null)
            HealthReminderWork.sourceRemindersChanged(activity.applicationContext)
    }

    private fun consent(preview: HealthCareDiscussionPreview, expectedId: String?) {
        val content = ui.column().apply { setPadding(ui.dp(20), ui.dp(8), ui.dp(20), ui.dp(16)) }
        content.addView(ui.text(activity.getString(R.string.health_research_destination, preview.target.title,
            preview.grant.modelId.ifBlank { activity.getString(R.string.health_care_discussion_default_model) },
            preview.grant.effort.ifBlank { activity.getString(R.string.health_care_unknown) }), 15f, bold = true))
        ui.add(content, ui.text(activity.getString(R.string.health_research_consent), 14f), 12)
        if (preview.grant.questionsShared) ui.add(content, ui.text(activity.getString(R.string.health_questions_disclosure), 14f), 8)
        preview.grant.profileLink?.scope?.let {
            ui.add(content, ui.text(activity.getString(R.string.health_care_profile_shared, it.fields.size, it.entries.size), 14f), 8)
        }
        ui.add(content, ui.text(activity.getString(preview.concern.metric.titleResource()) + " · " +
            preview.concern.assessment.value + " " + preview.concern.assessment.unit, 16f, bold = true), 12)
        val raw = ui.text(preview.snapshot, 13f).apply {
            visibility = android.view.View.GONE
            tag = "health-research-data-preview"
        }
        ui.add(content, ui.profileRow(activity.getString(R.string.health_care_discussion_data)) {
            raw.visibility = if (raw.visibility == android.view.View.GONE) android.view.View.VISIBLE else android.view.View.GONE
        }, 8)
        ui.add(content, raw, 8)
        val selected = linkedSetOf<HealthMetric>()
        var shareHistory = false
        fun refreshPreview() {
            raw.text = JSONObject(preview.snapshot).apply {
                put("feedback_history", JSONObject().put("authorized", shareHistory).put("included", false)
                    .put("read_tool", if (shareHistory) HealthCareFeedbackTool.ID else JSONObject.NULL))
                if (selected.isEmpty()) remove("related_measurements") else put("related_measurements", JSONObject()
                    .put("selected", JSONArray(preview.relatedOptions.filter { it.metric in selected }.map { JSONObject(it.snapshot) }))
                    .put("history_tool", HealthCareHistoryTool.ID).put("complete_health_archive", false))
            }.toString(2)
        }
        if (preview.relatedOptions.isNotEmpty()) {
            ui.add(content, ui.text(activity.getString(R.string.health_related_title), 16f, bold = true), 12)
            ui.add(content, ui.text(activity.getString(R.string.health_related_consent), 14f), 6)
            preview.relatedOptions.forEach { option ->
                ui.add(content, CheckBox(activity).apply {
                    text = activity.getString(option.metric.titleResource())
                    tag = "health-research-related-${option.metric.name}"
                    minimumHeight = ui.dp(48)
                    isChecked = false
                    setOnCheckedChangeListener { _, value ->
                        if (value) selected += option.metric else selected -= option.metric
                        refreshPreview()
                    }
                }, 4)
            }
        }
        val feedback = CheckBox(activity).apply {
            text = activity.getString(R.string.health_research_feedback_consent)
            tag = "health-research-feedback-history"
            isChecked = false
            setOnCheckedChangeListener { _, value ->
                shareHistory = value
                refreshPreview()
            }
        }
        ui.add(content, feedback, 12)
        val checked = CheckBox(activity).apply { text = activity.getString(R.string.health_research_acknowledge); tag = "health-research-consent" }
        ui.add(content, checked, 12)
        val next = AlertDialog.Builder(activity).setTitle(R.string.health_research_title)
            .setView(ScrollView(activity).apply { addView(content) }).setNegativeButton(R.string.common_cancel, null)
            .setPositiveButton(android.R.string.ok, null).create()
        display(next, content::removeAllViews)
        next.getButton(AlertDialog.BUTTON_POSITIVE).apply {
            isEnabled = false
            checked.setOnCheckedChangeListener { _, value -> isEnabled = value }
            setOnClickListener {
                if (!checked.isChecked || busy) return@setOnClickListener
                val shareFeedback = feedback.isChecked
                val related = selected.toSet()
                next.dismiss()
                work {
                    HealthCareResearchRuntime.authorize(activity.applicationContext, preview, expectedId, shareFeedback, related)
                    val done: () -> Unit = { show(preview.concern.id) }
                    done
                }
            }
        }
    }

    private fun destination(scope: HealthCareDiscussionGrant) = activity.getString(R.string.health_research_destination,
        scope.targetId, scope.modelId.ifBlank { activity.getString(R.string.health_care_unknown) },
        scope.effort.ifBlank { activity.getString(R.string.health_care_unknown) })

    private fun display(value: AlertDialog, release: () -> Unit) {
        dialog = value
        value.setOnDismissListener {
            release(); if (dialog === value) dialog = null
            if (HealthCareModelReviewVisibility.hide(this) && names.fixture == null)
                HealthReminderWork.sourceRemindersChanged(activity.applicationContext)
        }
        value.show()
    }

    private fun work(action: () -> (() -> Unit)) {
        if (busy) return
        busy = true; val token = generation
        worker.execute {
            val result = runCatching(action)
            main.post {
                busy = false
                if (generation == token && !activity.isFinishing && !activity.isDestroyed) result.fold({ it() }, {
                    Toast.makeText(activity, it.message?.takeIf(String::isNotBlank) ?: activity.getString(R.string.health_care_changed), Toast.LENGTH_LONG).show()
                })
            }
        }
    }
}

internal fun HealthCareResearchState.titleResource(): Int = when (this) {
    HealthCareResearchState.QUEUED -> R.string.health_research_queued
    HealthCareResearchState.DISPATCHED -> R.string.health_research_running
    HealthCareResearchState.COMPLETED -> R.string.health_research_completed
    HealthCareResearchState.FAILED -> R.string.health_research_failed
    HealthCareResearchState.CANCELLED -> R.string.health_research_cancelled
    HealthCareResearchState.SUPERSEDED -> R.string.health_research_superseded
}

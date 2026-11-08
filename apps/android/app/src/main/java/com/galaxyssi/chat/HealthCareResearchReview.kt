package com.galaxyssi.chat

import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.widget.CheckBox
import android.widget.ScrollView
import android.widget.Toast
import java.util.concurrent.Executors

/** Separate consent for future model calls; a local tracking switch never grants network access. */
internal class HealthCareResearchReview(private val activity: Activity, private val names: HealthOverviewDatabases) {
    private val ui = HealthCenterViews(activity)
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private var generation = 0
    private var busy = false
    private var dialog: AlertDialog? = null
    fun clear() { generation++; dialog?.dismiss(); dialog = null }
    fun destroy() { clear(); worker.shutdown() }

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
                val done: () -> Unit = { render(issue, authorization, job, enabled) }
                done
            }
        }
    }

    private fun render(issue: HealthCareConcern, authorization: HealthCareResearchAuthorization?, job: HealthCareResearchJob?, enabled: Boolean) {
        val content = ui.column().apply { setPadding(ui.dp(20), ui.dp(8), ui.dp(20), ui.dp(16)) }
        content.addView(ui.text(activity.getString(issue.metric.titleResource()), 17f, bold = true))
        ui.add(content, ui.text(activity.getString(if (authorization?.active == true) R.string.health_research_on else R.string.health_research_off), 14f)
            .apply { tag = "health-research-authorization" }, 8)
        authorization?.scope?.let { scope -> ui.add(content, ui.text(destination(scope), 14f), 8) }
        job?.let {
            ui.add(content, ui.text(activity.getString(it.state.titleResource()), 15f, bold = true).apply { tag = "health-research-state" }, 12)
            if (it.detail.isNotBlank()) ui.add(content, ui.text(it.detail, 14f), 6)
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
    }

    private fun consent(preview: HealthCareDiscussionPreview, expectedId: String?) {
        val content = ui.column().apply { setPadding(ui.dp(20), ui.dp(8), ui.dp(20), ui.dp(16)) }
        content.addView(ui.text(activity.getString(R.string.health_research_destination, preview.target.title,
            preview.grant.modelId.ifBlank { activity.getString(R.string.health_care_discussion_default_model) },
            preview.grant.effort.ifBlank { activity.getString(R.string.health_care_unknown) }), 15f, bold = true))
        ui.add(content, ui.text(activity.getString(R.string.health_research_consent), 14f), 12)
        ui.add(content, ui.text(activity.getString(preview.concern.metric.titleResource()) + " · " +
            preview.concern.assessment.value + " " + preview.concern.assessment.unit, 16f, bold = true), 12)
        val raw = ui.text(preview.snapshot, 13f).apply { visibility = android.view.View.GONE }
        ui.add(content, ui.profileRow(activity.getString(R.string.health_care_discussion_data)) {
            raw.visibility = if (raw.visibility == android.view.View.GONE) android.view.View.VISIBLE else android.view.View.GONE
        }, 8)
        ui.add(content, raw, 8)
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
                next.dismiss()
                work {
                    HealthCareResearchRuntime.authorize(activity.applicationContext, preview, expectedId)
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
        value.setOnDismissListener { release(); if (dialog === value) dialog = null }
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

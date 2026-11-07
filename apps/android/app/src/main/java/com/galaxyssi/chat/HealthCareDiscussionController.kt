package com.galaxyssi.chat

import android.app.AlertDialog
import android.content.Intent
import android.widget.ScrollView
import android.widget.Toast

internal class HealthCareDiscussionController(private val activity: MainActivity) {
    private var generation = 0
    private var busy = false
    private var dialog: AlertDialog? = null
    fun clear() { generation++; busy = false; dialog?.dismiss(); dialog = null }

    fun confirm(conversation: AgentConversation, question: String, attachments: List<AgentInputAttachment>,
        send: (HealthCareDiscussionPreview) -> Unit) {
        if (busy) return
        if (attachments.isNotEmpty()) {
            Toast.makeText(activity, R.string.health_care_discussion_import, Toast.LENGTH_LONG).show(); return
        }
        busy = true
        val token = ++generation
        activity.agentSubmissionExecutor.execute {
            val result = runCatching { HealthCareDiscussion.prepare(activity.applicationContext, conversation.id, question,
                activity.mobileNativeAgent.snapshot().runtimeContext) }
            activity.runOnUiThread {
                if (token != generation || activity.isFinishing || activity.isDestroyed) return@runOnUiThread
                busy = false
                if (activity.agentTranscriptStore.activeConversation().id != conversation.id) return@runOnUiThread
                result.fold({ preview ->
                    busy = true
                    val ui = HealthCenterViews(activity)
                    val body = ui.column().apply { setPadding(ui.dp(20), ui.dp(8), ui.dp(20), ui.dp(12)) }
                    body.addView(ui.text(activity.getString(R.string.health_care_discussion_disclosure,
                        preview.target.title, preview.grant.modelId.ifBlank { activity.getString(R.string.health_care_discussion_default_model) }), 15f))
                    ui.add(body, ui.text(question, 16f, bold = true), 16)
                    ui.add(body, ui.text(activity.getString(preview.concern.metric.titleResource()) + " · " +
                        preview.concern.assessment.value + " " + preview.concern.assessment.unit, 17f, bold = true), 12)
                    val raw = ui.text(preview.snapshot, 13f).apply { visibility = android.view.View.GONE }
                    ui.add(body, ui.profileRow(activity.getString(R.string.health_care_discussion_data)) {
                        raw.visibility = if (raw.visibility == android.view.View.GONE) android.view.View.VISIBLE else android.view.View.GONE
                    }, 8)
                    ui.add(body, raw, 8)
                    dialog = AlertDialog.Builder(activity).setTitle(R.string.health_care_discussion_confirm)
                        .setView(ScrollView(activity).apply { addView(body) })
                        .setOnDismissListener { dialog = null; body.removeAllViews() }
                        .setNegativeButton(R.string.common_cancel) { _, _ -> busy = false }
                        .setOnCancelListener { busy = false }
                        .setPositiveButton(R.string.health_care_discussion_send) { _, _ ->
                            busy = true
                            activity.agentSubmissionExecutor.execute {
                                val approval = runCatching { HealthCareDiscussion.approve(activity.applicationContext, preview) }
                                activity.runOnUiThread {
                                    if (token != generation) return@runOnUiThread
                                    busy = false
                                    if (activity.isFinishing || activity.isDestroyed ||
                                        activity.agentTranscriptStore.activeConversation().id != conversation.id) return@runOnUiThread
                                    approval.fold({ send(preview) }, { showError(it) })
                                }
                            }
                        }.show()
                }, ::showError)
            }
        }
    }
    private fun showError(error: Throwable) {
        dialog = AlertDialog.Builder(activity).setTitle(R.string.health_care_discussion_title_short)
            .setMessage(if (error is HealthCareConflict) activity.getString(R.string.health_care_changed)
                else error.message ?: activity.getString(R.string.health_storage_error))
            .setNegativeButton(R.string.common_cancel, null)
            .setNeutralButton(R.string.health_privacy_title) { _, _ -> activity.startActivity(Intent(activity, HealthPrivacyActivity::class.java)) }
            .show()
    }
}

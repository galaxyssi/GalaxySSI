package com.galaxyssi.chat

import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.widget.ScrollView
import android.widget.Toast
import java.util.concurrent.Executors

/** Target edits use the existing scoped Agent discussion; only native confirmation can adopt a draft. */
internal class HealthCareTargetReview(private val activity: Activity, private val names: HealthOverviewDatabases) {
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
        clear(); val token = generation
        worker.execute {
            val result = runCatching {
                HealthCareEngine.evaluate(activity.applicationContext, names)
                val privacy = HealthPrivacyStore(activity, names.privacy).use { it.policy() }
                check(privacy.metrics && privacy.profile)
                HealthCareStore(activity, names.care).use { store ->
                    val issue = store.concern(id) ?: throw HealthCareConflict()
                    check(issue.target != null)
                    issue to issue.target.planId.takeIf { it.isNotEmpty() }?.let(store::plan)
                }
            }
            main.post { if (token == generation && !activity.isFinishing && !activity.isDestroyed) result.fold({ render(it.first, it.second) }, { error() }) }
        }
    }
    private fun render(issue: HealthCareConcern, plan: HealthCarePlan?) {
        val content = ui.column().apply { setPadding(ui.dp(20), ui.dp(8), ui.dp(20), ui.dp(16)) }
        content.addView(ui.text(HealthCareTargetPresentation.details(activity, issue), 15f).apply { tag = "health-target-details" })
        plan?.target?.let { draft ->
            ui.add(content, ui.text(HealthCareApplicabilityPresentation.text(activity, draft.applicability, issue,
                HealthCareTargetPolicy.canAccept(draft, issue)), 14f), 12)
            plan.sources.forEach { source ->
                ui.add(content, ui.profileRow(source.title, "${source.version}\n${source.quote}") {
                    runCatching { activity.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(source.url))) }.onFailure { error() }
                }, 8)
            }
        }
        dialog = AlertDialog.Builder(activity).setTitle(R.string.health_care_target)
            .setView(ScrollView(activity).apply { addView(content) }).setPositiveButton(R.string.common_cancel, null)
            .setNeutralButton(R.string.health_target_discuss) { _, _ ->
                if (names.fixture == null) change(navigation = true) {
                    val conversation = HealthCareDiscussion.open(activity.applicationContext, issue.id)
                    val completion: () -> Unit = { activity.startActivity(Intent(activity, MainActivity::class.java)
                        .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                        .putExtra("galaxyssi_open_agent", true).putExtra("galaxyssi_agent_conversation_id", conversation)) }
                    completion
                }
            }.setNegativeButton(R.string.health_target_revoke) { _, _ -> confirmRevoke(issue) }.create().also { d ->
                d.setOnDismissListener { content.removeAllViews(); if (dialog === d) dialog = null }; d.show()
            }
    }
    private fun confirmRevoke(issue: HealthCareConcern) {
        dialog = AlertDialog.Builder(activity).setTitle(R.string.health_target_revoke).setMessage(R.string.health_target_revoke_notice)
            .setNegativeButton(R.string.common_cancel, null).setPositiveButton(android.R.string.ok) { _, _ -> change {
                val privacy = HealthPrivacyStore(activity, names.privacy).use { it.policy() }
                HealthCareStore(activity, names.care).use { it.revokeTarget(issue.id, issue.revision, privacy) }
                val completion: () -> Unit = { Toast.makeText(activity, R.string.health_care_plan_saved, Toast.LENGTH_SHORT).show() }
                completion
            } }.show()
    }
    private fun change(navigation: Boolean = false, action: () -> (() -> Unit)) {
        if (busy) return
        busy = true; val token = generation
        worker.execute {
            val result = runCatching(action)
            main.post {
                busy = false
                // Creating a replacement private conversation can itself publish a store-change event.
                if ((generation == token || navigation && activity.hasWindowFocus()) && !activity.isFinishing && !activity.isDestroyed)
                    result.fold({ it() }, { error() })
            }
        }
    }
    private fun error() = Toast.makeText(activity, R.string.health_care_changed, Toast.LENGTH_LONG).show()
}

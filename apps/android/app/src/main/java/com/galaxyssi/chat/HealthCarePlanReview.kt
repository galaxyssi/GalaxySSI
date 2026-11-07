package com.galaxyssi.chat

import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.widget.CheckBox
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.Toast
import java.text.DateFormat
import java.util.Date
import java.util.concurrent.Executors

/** Shared by the Agent surface and Personal Health; confirmation never submits a new model request. */
internal class HealthCarePlanReview(private val activity: Activity, private val names: HealthOverviewDatabases) {
    private val ui = HealthCenterViews(activity)
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private var generation = 0
    private var dialog: AlertDialog? = null
    private var busy = false
    fun clear() { generation++; dialog?.dismiss(); dialog = null }
    fun destroy() { clear(); worker.shutdown() }

    private data class Snapshot(val plan: HealthCarePlan, val issue: HealthCareConcern, val current: Boolean)
    private fun snapshot(id: String): Snapshot {
        HealthCareEngine.evaluate(activity.applicationContext, names)
        val privacy = HealthPrivacyStore(activity, names.privacy).use { it.policy() }
        check(privacy.metrics && privacy.profile)
        return HealthCareStore(activity, names.care).use { store ->
            val plan = store.plan(id) ?: throw HealthCareConflict()
            val issue = store.concern(plan.grant.concernId) ?: throw HealthCareConflict()
            check(plan.state == HealthCarePlanState.PENDING)
            val settings = store.settings()
            val source = HealthRecordStore(activity, names.records).use {
                HealthCareEngine.inputVersion(settings.version, privacy.version, it.metricVersion(issue.metric))
            }
            Snapshot(plan, issue, HealthCarePlanPolicy.current(plan, issue, settings, privacy, source))
        }
    }
    fun show(id: String) {
        if (busy) return
        clear(); val token = generation
        worker.execute {
            val result = runCatching { snapshot(id) }
            main.post { if (generation == token && !activity.isFinishing && !activity.isDestroyed) result.fold(::render, { error() }) }
        }
    }
    private fun render(snapshot: Snapshot) {
        val content = LinearLayout(activity).apply { orientation = LinearLayout.VERTICAL; setPadding(ui.dp(20), ui.dp(8), ui.dp(20), ui.dp(16)) }
        val plan = snapshot.plan
        val selected = linkedSetOf<String>()
        content.addView(ui.text(activity.getString(R.string.health_care_plan_notice), 14f, muted = true))
        ui.add(content, ui.text(activity.getString(R.string.health_care_plan_model, plan.grant.targetId, plan.grant.modelId), 13f, muted = true), 8)
        if (!snapshot.current) ui.add(content, ui.text(activity.getString(R.string.health_care_plan_stale), 15f, bold = true), 12)
        ui.add(content, ui.text(activity.getString(R.string.health_care_plan_uncertainty), 15f, bold = true), 12)
        ui.add(content, ui.text(plan.uncertainty, 14f), 4)
        val validActions = plan.actions.filter { it.dueUntil == null || it.dueUntil >= System.currentTimeMillis() }.map { it.id }.toSet()
        plan.actions.forEachIndexed { index, action ->
            ui.add(content, CheckBox(activity).apply {
                text = action.description; minimumHeight = ui.dp(48); tag = "health-plan-action-$index"
                isEnabled = snapshot.current && action.id in validActions
                setOnCheckedChangeListener { _, checked ->
                    if (checked) selected += action.id else selected -= action.id
                    dialog?.getButton(AlertDialog.BUTTON_POSITIVE)?.isEnabled = selected.isNotEmpty()
                }
            }, 12)
            ui.add(content, ui.text(action.rationale, 14f), 4)
            ui.add(content, ui.text(action.source, 13f, muted = true), 4)
            action.dueFrom?.let {
                ui.add(content, ui.text(activity.getString(R.string.health_care_plan_window, date(it), date(action.dueUntil!!)), 14f), 4)
            }
            if (action.id !in validActions) ui.add(content, ui.text(activity.getString(R.string.health_care_plan_window_expired), 14f), 4)
        }
        ui.add(content, ui.text(activity.getString(R.string.health_care_plan_sources), 15f, bold = true), 16)
        plan.sources.forEach { source ->
            ui.add(content, ui.profileRow(source.title, "${source.version}\n${source.applicability}") {
                runCatching { activity.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(source.url))) }.onFailure { error() }
            }, 6)
        }
        dialog = AlertDialog.Builder(activity).setTitle(R.string.health_care_plan_title)
            .setView(ScrollView(activity).apply { addView(content) })
            .setNeutralButton(R.string.common_cancel, null)
            .setNegativeButton(R.string.health_care_plan_dismiss) { _, _ -> change { store -> store.dismissPlan(plan.id, System.currentTimeMillis()) } }
            .setPositiveButton(R.string.health_care_plan_accept, null).create().also { d ->
                d.setOnDismissListener { content.removeAllViews(); if (dialog === d) dialog = null }
                d.setOnShowListener {
                    d.getButton(AlertDialog.BUTTON_POSITIVE).isEnabled = false
                    d.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener {
                        val chosen = selected.toSet()
                        if (chosen.isEmpty()) return@setOnClickListener
                        d.dismiss()
                        change { store ->
                            val privacy = HealthPrivacyStore(activity, names.privacy).use { it.policy() }
                            val settings = store.settings()
                            val source = HealthRecordStore(activity, names.records).use {
                                HealthCareEngine.inputVersion(settings.version, privacy.version, it.metricVersion(snapshot.issue.metric))
                            }
                            store.resolvePlan(plan.id, chosen, snapshot.issue.revision, privacy, source, System.currentTimeMillis())
                        }
                    }
                }
                d.show()
            }
    }
    private fun change(action: (HealthCareStore) -> Unit) {
        if (busy) return
        busy = true; val token = generation
        worker.execute {
            val result = runCatching { HealthCareStore(activity, names.care).use(action) }
            main.post {
                busy = false
                if (generation == token && !activity.isFinishing && !activity.isDestroyed) {
                    if (result.isFailure) error()
                    else Toast.makeText(activity, R.string.health_care_plan_saved, Toast.LENGTH_SHORT).show()
                }
            }
        }
    }
    private fun error() = Toast.makeText(activity, R.string.health_care_plan_changed, Toast.LENGTH_LONG).show()
    private fun date(value: Long) = DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT).format(Date(value))
}

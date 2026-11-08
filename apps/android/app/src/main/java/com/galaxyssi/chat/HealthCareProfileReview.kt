package com.galaxyssi.chat

import android.app.Activity
import android.app.AlertDialog
import android.widget.CheckBox
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

/** Scope is configured in Personal Health; the Agent page itself does not change. */
internal class HealthCareProfileReview(private val activity: Activity, private val names: HealthOverviewDatabases) {
    private val tasks = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private val ui = HealthCenterViews(activity)
    private var generation = 0
    private var dialog: AlertDialog? = null
    private var picker: AlertDialog? = null
    fun clear() { generation++; tasks.coroutineContext.cancelChildren(); picker?.dismiss(); picker = null; dialog?.dismiss(); dialog = null }
    fun destroy() { clear(); tasks.cancel() }
    fun show(id: String) {
        clear()
        work {
            val policy = HealthPrivacyStore(activity, names.privacy).use { it.policy() }
            check(policy.profile && policy.metrics)
            val issue = HealthCareStore(activity, names.care).use { it.concern(id) } ?: throw HealthCareConflict()
            val profile = HealthProfileStore(activity, names.profile, names.privacy).use {
                it.capture(HealthProfileField.entries.filter { field -> field != HealthProfileField.NAME }.toSet(),
                    issue.profileLink?.scope?.entries.orEmpty(), allowMissingEntries = true)
            }
            val done: () -> Unit = { render(issue, profile, policy) }
            done
        }
    }
    private fun render(issue: HealthCareConcern, profile: HealthProfileContext, privacy: HealthPrivacyPolicy) {
        val fields = issue.profileLink?.scope?.fields.orEmpty().toMutableSet()
        var entries = profile.entries.associate { it.id to HealthAnalysisBackgroundChoice(it.token, it.kind, it.name) }
        val content = ui.column().apply { setPadding(ui.dp(20), ui.dp(8), ui.dp(20), ui.dp(16)); isSaveEnabled = false }
        ui.add(content, ui.text(activity.getString(R.string.health_care_profile_scope), 14f), 4)
        if (issue.profileLink?.scope?.generation?.let { it != profile.stamp.generation } == true ||
            issue.profileLink?.scope?.entries.orEmpty().size != entries.size) {
            ui.add(content, ui.text(activity.getString(R.string.health_care_profile_changed), 14f, bold = true), 8)
        }
        profile.fields.forEach { (field, value) ->
            ui.add(content, CheckBox(activity).apply {
                tag = "health-care-profile-field-${field.name}"; minimumHeight = ui.dp(48); isSaveEnabled = false
                text = activity.getString(field.titleResource()) + "\n" + activity.healthProfileDisplay(field, value)
                isChecked = field in fields
                setOnCheckedChangeListener { _, checked -> if (checked) fields += field else fields -= field }
            }, 8)
        }
        val count = ui.text("", 14f)
        fun count() { count.text = activity.getString(R.string.health_care_profile_entries, entries.size) }
        count()
        ui.add(content, count, 8)
        ui.add(content, ui.profileRow(activity.getString(R.string.health_assistant_background)) {
            picker = activity.chooseHealthAnalysisBackground(tasks, names, entries, blocked = { clear() }) {
                entries = it; count()
            }
        }.apply { tag = "health-care-profile-background" }, 8)
        val next = AlertDialog.Builder(activity).setTitle(R.string.health_care_profile_title)
            .setView(ScrollView(activity).apply { addView(content); isSaveEnabled = false })
            .setNegativeButton(R.string.common_cancel, null).setPositiveButton(android.R.string.ok, null)
            .setNeutralButton(R.string.health_care_profile_remove, null).create()
        dialog = next
        next.setOnDismissListener { content.removeAllViews(); if (dialog === next) dialog = null }
        next.show()
        fun save(remove: Boolean) {
            val chosen = if (remove) emptySet() else fields.toSet()
            val backgrounds = if (remove) emptyMap() else entries.toMap()
            next.getButton(AlertDialog.BUTTON_POSITIVE).isEnabled = false
            next.getButton(AlertDialog.BUTTON_NEUTRAL).isEnabled = false
            work {
                check(HealthPrivacyStore(activity, names.privacy).use { it.policy() } == privacy)
                val link = if (chosen.isEmpty() && backgrounds.isEmpty()) null else {
                    val scope = HealthCareProfileScope(profile.stamp.generation, chosen, backgrounds.keys)
                    val stamp = HealthProfileStamp(scope.generation, chosen.associate { "field:${it.name}" to
                        profile.stamp.versions.getValue("field:${it.name}") } + backgrounds.mapKeys { "entry:${it.key}" }.mapValues { it.value.token })
                    HealthCareProfileLink(scope, stamp).also {
                        if (!HealthCareProfileAccess.current(activity, it, names)) throw HealthProfileConflict()
                    }
                }
                HealthCareStore(activity, names.care).use { care -> care.update(issue.id, issue.revision, "profile_scope_reviewed") {
                    if (it.profileLink == link) it else it.copy(profileLink = link,
                        stage = if (it.stage in setOf(HealthCareStage.PAUSED, HealthCareStage.CLOSED)) it.stage else HealthCareStage.REASSESS)
                } }
                val done: () -> Unit = { clear() }
                done
            }
        }
        next.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener { save(false) }
        next.getButton(AlertDialog.BUTTON_NEUTRAL).setOnClickListener { save(true) }
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
                    clear()
                    Toast.makeText(activity, R.string.health_care_profile_changed, Toast.LENGTH_LONG).show()
                }
            }
        }
    }
}

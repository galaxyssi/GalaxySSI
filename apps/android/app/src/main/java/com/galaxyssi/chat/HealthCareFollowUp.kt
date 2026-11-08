package com.galaxyssi.chat

import java.time.ZoneId
import java.util.UUID
import org.json.JSONObject

internal enum class HealthCareReminderState { SCHEDULED, DELIVERED, CANCELLED }

/** The reminder time is a user choice, not a replacement for the clinical review window. */
internal data class HealthCareReminder(val actionId: String, val concernId: String, val token: String,
    val anchor: String, val privacyVersion: String, val dueAt: Long, val updatedAt: Long,
    val state: HealthCareReminderState = HealthCareReminderState.SCHEDULED) {
    init {
        require(listOf(actionId, concernId, token).all(HealthProfilePolicy::uuid))
        require(anchor.matches(Regex("[0-9a-f]{64}")) && privacyVersion.isNotBlank() && dueAt > 0 && updatedAt > 0)
    }
    fun json() = JSONObject().put("action", actionId).put("concern", concernId).put("token", token)
        .put("anchor", anchor).put("privacy", privacyVersion).put("due", dueAt).put("updated", updatedAt).put("state", state.name)
    companion object { fun from(j: JSONObject) = HealthCareReminder(j.getString("action"), j.getString("concern"),
        j.getString("token"), j.getString("anchor"), j.getString("privacy"), j.getLong("due"), j.getLong("updated"),
        HealthCareReminderState.valueOf(j.getString("state"))) }
}

internal object HealthCareFollowUpPolicy {
    fun basis(issue: HealthCareConcern): String = AgentNativeJsonCodec.sha256(mapOf("source" to issue.inputVersion,
        "context" to issue.context?.json()?.toString()) + targetBasis(issue))
    fun anchor(issue: HealthCareConcern, action: HealthCareAction): String = AgentNativeJsonCodec.sha256(mapOf(
        "concern" to issue.id, "source" to issue.inputVersion, "context" to issue.context?.json()?.toString(),
        "action" to action.json().toString()) + targetBasis(issue))
    // Leave pre-target reminder hashes unchanged; changing a target requires a new action review.
    private fun targetBasis(issue: HealthCareConcern): Map<String, String> = issue.target?.let {
        mapOf("individual_target" to it.json().toString())
    }.orEmpty() + if (issue.targetRevision > 0) mapOf("target_revision" to issue.targetRevision.toString()) else emptyMap()

    fun eligible(issue: HealthCareConcern, action: HealthCareAction, settings: HealthCareSettings,
        privacy: HealthPrivacyPolicy, sourceVersion: String): Boolean =
        settings.enabled && privacy.metrics && privacy.profile && issue.assessment.record != null &&
            issue.stage !in setOf(HealthCareStage.PAUSED, HealthCareStage.CLOSED) &&
            issue.inputVersion == sourceVersion && action in issue.actions && action.state == HealthCareActionState.CONFIRMED &&
            action.basis == basis(issue)

    fun current(reminder: HealthCareReminder, issue: HealthCareConcern, settings: HealthCareSettings,
        privacy: HealthPrivacyPolicy, sourceVersion: String): Boolean {
        val action = issue.actions.firstOrNull { it.id == reminder.actionId } ?: return false
        return reminder.concernId == issue.id && reminder.privacyVersion == privacy.version &&
            reminder.anchor == anchor(issue, action) && eligible(issue, action, settings, privacy, sourceVersion)
    }

    fun schedule(issue: HealthCareConcern, action: HealthCareAction, settings: HealthCareSettings,
        privacy: HealthPrivacyPolicy, sourceVersion: String, at: Long, now: Long): HealthCareReminder {
        require(at > now && now > 0)
        if (!eligible(issue, action, settings, privacy, sourceVersion)) throw HealthCareConflict()
        return HealthCareReminder(action.id, issue.id, UUID.randomUUID().toString(), anchor(issue, action), privacy.version, at, now)
    }

    fun finish(issue: HealthCareConcern, actionId: String, outcome: String, now: Long): HealthCareConcern {
        val note = outcome.trim()
        require(note.isNotBlank() && note.length <= 2000)
        val action = issue.actions.firstOrNull { it.id == actionId } ?: throw HealthCareConflict()
        if (action.state != HealthCareActionState.CONFIRMED || !issue.open) throw HealthCareConflict()
        return issue.copy(actions = issue.actions.map { if (it.id == actionId) it.copy(state = HealthCareActionState.DONE, outcome = note) else it },
            stage = if (issue.stage == HealthCareStage.PAUSED) issue.stage else HealthCareStage.REASSESS,
            updatedAt = maxOf(now, issue.updatedAt))
    }

    fun deliveryTime(dueAt: Long, settings: HealthReminderSettings, now: Long, zone: ZoneId): Long =
        maxOf(dueAt, HealthReminderPolicy.deliveryDeferredUntil(settings, maxOf(dueAt, now), zone) ?: 0L)
}

/** Bounded, replayable reconciliation; notifications never contain the action text or measurement. */
internal object HealthCareReminderDelivery {
    fun reconcile(store: HealthCareStore, settings: HealthReminderSettings, now: Long, zone: ZoneId,
        systemAllowed: Boolean, visible: Set<String>, valid: (HealthCareReminder) -> Boolean,
        post: (HealthCareReminder) -> Boolean, cancel: (String) -> Unit): Long? {
        visible.forEach { id ->
            val value = store.reminder(id)
            if (value == null || value.state == HealthCareReminderState.CANCELLED || !valid(value) ||
                !settings.notifications || !systemAllowed || value.dueAt > now ||
                HealthReminderPolicy.deliveryDeferredUntil(settings, now, zone) != null) cancel(id)
        }
        if (!settings.notifications || !systemAllowed) return null
        val deferred = HealthReminderPolicy.deliveryDeferredUntil(settings, now, zone)
        if (deferred != null) return store.nextReminder()?.let { maxOf(it, deferred) }
        var failed = false
        store.dueReminders(now).forEach { value ->
            if (!valid(value)) store.cancelReminder(value.actionId, value.token, now)
            else if (post(value)) {
                try { store.markReminderDelivered(value.actionId, value.token, now) }
                catch (_: HealthCareConflict) { cancel(value.actionId) }
            }
            else failed = true
        }
        // Yield after one page, and back off an OS delivery failure instead of spinning on a past deadline.
        return store.nextReminder()?.let { maxOf(it, now + if (failed) 60_000L else 1000L) }
    }
}

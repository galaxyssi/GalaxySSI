package com.galaxyssi.chat

import android.content.Context
import android.content.Intent
import java.time.ZoneId

internal object HealthCareReminderRuntime {
    fun openIntent(context: Context, reminder: HealthCareReminder, names: HealthOverviewDatabases = HealthOverviewDatabases()): Intent {
        reminder.appointment?.let { return Intent(context, HealthCareEncountersActivity::class.java).putHealthNavigationFixture(names)
            .putExtra("health_care_id", reminder.concernId).putExtra("health_encounter_id", it.encounter)
            .setData(android.net.Uri.parse("galaxyssi://health/appointment/${reminder.concernId}/${reminder.actionId}")) }
        val ref = HealthCareStore(context, names.care).use { care ->
            care.concern(reminder.concernId)?.actions?.firstOrNull { it.id == reminder.actionId }?.visitReview
        }
        return Intent(context, if (ref == null) HealthCareActivity::class.java else HealthCareVisitFollowUpActivity::class.java)
            .putHealthNavigationFixture(names).putExtra("health_care_id", reminder.concernId).apply {
                ref?.let { putExtra("health_encounter_id", it.encounter) }
                data = android.net.Uri.parse("galaxyssi://health/care/${reminder.concernId}/${reminder.actionId}")
            }
    }
    fun reconcile(context: Context, settings: HealthReminderSettings, now: Long, zone: ZoneId, allowed: Boolean,
        visible: Set<String>, post: (HealthCareReminder) -> Boolean, cancel: (String) -> Unit,
        names: HealthOverviewDatabases = HealthOverviewDatabases()): Long? {
        if (!context.getDatabasePath(names.care).exists()) { visible.forEach(cancel); return null }
        return try {
            HealthCareEngine.evaluate(context, names, now)
            reconcileVerified(context, settings, now, zone, allowed, visible, post, cancel, names)
        } catch (failure: Exception) {
            visible.forEach { runCatching { cancel(it) } }
            android.util.Log.w("HealthReminder", "Care reconciliation failed: ${failure.javaClass.simpleName}")
            if (failure is android.database.sqlite.SQLiteDatabaseLockedException || failure is HealthCareConflict) now + 60_000L else null
        }
    }
    private fun reconcileVerified(context: Context, settings: HealthReminderSettings, now: Long, zone: ZoneId, allowed: Boolean,
        visible: Set<String>, post: (HealthCareReminder) -> Boolean, cancel: (String) -> Unit, names: HealthOverviewDatabases): Long? =
        HealthCareStore(context, names.care).use { care ->
            HealthPrivacyStore(context, names.privacy).use { privacy ->
                HealthRecordStore(context, names.records).use { records ->
                    val permission = privacy.policy()
                    val enabled = care.settings().enabled && permission.metrics && permission.profile
                    care.cancelReminders(now, if (enabled) permission.version else null)
                    var appointmentExpiry: Long? = null
                    fun valid(value: HealthCareReminder): Boolean {
                        val issue = care.concern(value.concernId) ?: return false
                        val currentPermission = privacy.policy()
                        val currentSettings = care.settings()
                        value.appointment?.let {
                            val visit = care.encounter(it.encounter)
                            if (!HealthCareAppointmentPolicy.current(value, issue, visit, currentSettings, currentPermission, now)) return false
                            val expires = visit!!.details.plannedAt!!
                            appointmentExpiry = minOf(appointmentExpiry ?: expires, expires)
                            return true
                        }
                        val action = issue.actions.firstOrNull { it.id == value.actionId } ?: return false
                        val source = HealthCareEngine.inputVersion(currentSettings.version, currentPermission.version, records.metricVersion(issue.metric))
                        return HealthCareFollowUpPolicy.current(value, issue, currentSettings, currentPermission, source) &&
                            HealthCareInstructionAccess.current(context, names, care, issue, action) &&
                            HealthCareProfileAccess.current(context, issue.profileLink, names)
                    }
                    val delivery = HealthCareReminderDelivery.reconcile(care, settings, now, zone, allowed, visible, ::valid,
                        post = { value -> valid(value) && post(value) }, cancel = cancel,
                        foreground = { value -> care.concern(value.concernId)?.actions?.firstOrNull { it.id == value.actionId }
                            ?.visitReview?.let { HealthCareVisitReviewVisibility.contains(names.care, it.encounter) } == true })
                    // Reopen due reviews even without notification permission; this does not post or authorize an alert.
                    listOfNotNull(delivery, appointmentExpiry,
                        care.nextMaintenanceReview()?.takeIf { enabled }?.coerceAtLeast(now + 1000)).minOrNull()
                }
            }
        }
}

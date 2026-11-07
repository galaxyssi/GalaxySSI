package com.galaxyssi.chat

import android.content.Context
import java.time.ZoneId

internal object HealthCareReminderRuntime {
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
                    fun valid(value: HealthCareReminder): Boolean {
                        val issue = care.concern(value.concernId) ?: return false
                        val currentPermission = privacy.policy()
                        val currentSettings = care.settings()
                        val source = HealthCareEngine.inputVersion(currentSettings.version, currentPermission.version, records.metricVersion(issue.metric))
                        return HealthCareFollowUpPolicy.current(value, issue, currentSettings, currentPermission, source)
                    }
                    HealthCareReminderDelivery.reconcile(care, settings, now, zone, allowed, visible, ::valid,
                        post = { value -> valid(value) && post(value) }, cancel = cancel)
                }
            }
        }
}

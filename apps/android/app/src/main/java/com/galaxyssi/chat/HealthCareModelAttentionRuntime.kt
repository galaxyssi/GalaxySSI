package com.galaxyssi.chat

import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import java.time.ZoneId

internal object HealthCareModelAttentionRuntime {
    fun openIntent(context: Context, notice: HealthCareModelAttention) = Intent(context, MainActivity::class.java)
        .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        .putExtra("galaxyssi_open_agent", true).putExtra("galaxyssi_agent_conversation_id", notice.conversationId)
        .setData(Uri.parse("galaxyssi://health/model-review/${notice.concernId}/${notice.turnId}"))

    fun reconcile(context: Context, settings: HealthReminderSettings, now: Long, zone: ZoneId, allowed: Boolean,
        visible: Map<String, Boolean>, post: (HealthCareModelAttention) -> Boolean, cancel: (String) -> Unit,
        names: HealthOverviewDatabases = HealthOverviewDatabases(),
        binding: (HealthCareResearchAuthorization) -> Boolean = { HealthCareResearchRuntime.bindingCurrent(context, it) }): Long? {
        if (!context.getDatabasePath(names.care).exists()) { visible.keys.forEach(cancel); return null }
        return try {
            HealthCareStore(context, names.care).use { care ->
                HealthPrivacyStore(context, names.privacy).use { privacy ->
                    HealthRecordStore(context, names.records).use { records ->
                        fun valid(value: HealthCareModelAttention): Boolean {
                            if (!care.modelAttentionCurrent(value, now)) return false
                            val issue = care.concern(value.concernId) ?: return false
                            val auth = care.researchAuthorization(issue.id) ?: return false
                            val permission = privacy.policy()
                            return permission.metrics && permission.profile && permission.version == auth.scope.privacyVersion &&
                                issue.inputVersion == HealthCareEngine.inputVersion(care.settings().version, permission.version, records.metricVersion(issue.metric)) &&
                                HealthCareProfileAccess.current(context, issue.profileLink, names) &&
                                care.discussionGrant(value.turnId)?.let { HealthCareRelatedContext.sourceCurrent(context, names, it) } == true && binding(auth)
                        }
                        HealthCareModelAttentionDelivery.reconcile(care, settings, now, zone, allowed, visible, ::valid,
                            post = { valid(it) && post(it) }, cancel = cancel, foreground = {
                                !context.getSystemService(KeyguardManager::class.java).isKeyguardLocked &&
                                    HealthCareModelReviewVisibility.contains(names.care, it.conversationId)
                            })
                    }
                }
            }
        } catch (failure: Exception) {
            visible.keys.forEach { runCatching { cancel(it) } }
            android.util.Log.w("HealthReminder", "Model attention reconciliation failed: ${failure.javaClass.simpleName}")
            if (failure is android.database.sqlite.SQLiteDatabaseLockedException || failure is HealthCareConflict) now + 60_000L else null
        }
    }
}

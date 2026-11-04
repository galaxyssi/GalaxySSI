package com.galaxyssi.chat

import android.content.Context
import android.content.Intent
import android.net.Uri
import java.util.UUID
import org.json.JSONObject

internal val HealthSyncOutcome.isSyncFailure: Boolean get() = when (this) {
    HealthSyncOutcome.PERMISSION, HealthSyncOutcome.UNAVAILABLE, HealthSyncOutcome.NETWORK,
    HealthSyncOutcome.TRANSPORT, HealthSyncOutcome.TIMEOUT, HealthSyncOutcome.STORAGE, HealthSyncOutcome.FAILED -> true
    else -> false
}

internal data class HealthSyncIncident(
    val id: String, val scope: HealthConnectScope, val outcome: HealthSyncOutcome,
    val failedAt: Long, val lastSuccess: Long, val acknowledgedAt: Long = 0L, val resolvedAt: Long = 0L,
    val delivery: HealthReminderDelivery = HealthReminderDelivery.IN_APP_ONLY
) {
    init {
        require(HealthProfilePolicy.uuid(id) && outcome.isSyncFailure && failedAt > 0)
        require(lastSuccess >= 0 && acknowledgedAt >= 0 && resolvedAt >= 0)
    }

    val handled get() = acknowledgedAt != 0L || resolvedAt != 0L
    val handledDelivery get() = if (delivery == HealthReminderDelivery.WAITING) HealthReminderDelivery.IN_APP_ONLY else delivery

    fun matches(filter: HealthReminderFilter) = when (filter) {
        HealthReminderFilter.PENDING -> !handled
        HealthReminderFilter.HANDLED -> handled
        HealthReminderFilter.ALL -> true
    }

    fun json() = JSONObject().put("id", id).put("scope", scope.name).put("outcome", outcome.name)
        .put("failedAt", failedAt).put("lastSuccess", lastSuccess).put("acknowledgedAt", acknowledgedAt)
        .put("resolvedAt", resolvedAt).put("delivery", delivery.name)

    fun intent(context: Context) = Intent(context, HealthSyncActivity::class.java)
        .putExtra("health_sync_scope", scope.name)
        .setData(Uri.parse("galaxyssi://health/sync-incident/$id"))

    companion object {
        fun from(value: JSONObject) = HealthSyncIncident(value.getString("id"), HealthConnectScope.valueOf(value.getString("scope")),
            HealthSyncOutcome.valueOf(value.getString("outcome")), value.getLong("failedAt"), value.getLong("lastSuccess"),
            value.getLong("acknowledgedAt"), value.getLong("resolvedAt"),
            HealthReminderDelivery.valueOf(value.optString("delivery", HealthReminderDelivery.IN_APP_ONLY.name)))

        fun fromCheckpoint(mark: HealthSyncCheckpoint): HealthSyncIncident? =
            if (mark.outcome.isSyncFailure && mark.lastAttempt > 0) HealthSyncIncident(
                UUID.nameUUIDFromBytes("health-sync:${mark.scope.name}:${mark.lastAttempt}".toByteArray(Charsets.UTF_8)).toString(),
                mark.scope, mark.outcome, mark.lastAttempt, mark.lastSuccess
            ) else null
    }
}

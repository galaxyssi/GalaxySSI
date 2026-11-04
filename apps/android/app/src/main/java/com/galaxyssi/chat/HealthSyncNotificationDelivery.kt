package com.galaxyssi.chat

import java.time.ZoneId

internal object HealthSyncNotificationDelivery {
    fun reconcile(
        records: HealthRecordStore, settings: HealthReminderSettings, selected: Set<HealthConnectScope>,
        now: Long, zone: ZoneId, systemAllowed: Boolean, visible: Map<String, Boolean>,
        post: (HealthSyncIncident) -> Boolean, cancel: (String) -> Unit
    ): Long? {
        val active = HealthConnectScope.entries.mapNotNull(records::storedSyncIncident).filterNot { it.handled }
        val visibleCandidates = active.filter { it.scope in selected }.associateBy { it.id }
        val allowed = settings.notifications && systemAllowed
        val deferUntil = maxOf(settings.pauseUntil, HealthReminderPolicy.quietUntil(settings, now, zone) ?: 0L)
        for ((id, privateOnLock) in visible) {
            if (!allowed || now < settings.pauseUntil || privateOnLock != settings.hideOnLock || id !in visibleCandidates) cancel(id)
        }
        var deferred = false
        for (incident in active) {
            if (incident.delivery != HealthReminderDelivery.WAITING) continue
            val eligible = allowed && incident.scope in selected
            if (eligible && visible[incident.id] == settings.hideOnLock) {
                if (!records.finishSyncNotice(incident, HealthReminderDelivery.POSTED)) cancel(incident.id)
                continue
            }
            if (eligible && deferUntil > now) {
                deferred = true
                continue
            }
            val posted = eligible && post(incident)
            if (!records.finishSyncNotice(incident, if (posted) HealthReminderDelivery.POSTED else HealthReminderDelivery.IN_APP_ONLY) && posted) {
                cancel(incident.id)
            }
        }
        return deferUntil.takeIf { deferred }
    }
}

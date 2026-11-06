package com.galaxyssi.chat

import java.time.LocalDate
import java.time.ZoneId

internal object HealthRoutineNotificationDelivery {
    fun daily(
        store: HealthReminderStore, settings: HealthReminderSettings, now: Long, zone: ZoneId, systemAllowed: Boolean,
        visible: Map<LocalDate, Boolean>, post: (HealthReminderOccurrence) -> Boolean, cancel: (LocalDate) -> Unit,
    ): Long? {
        val allowed = settings.enabled && settings.notifications && systemAllowed
        val deferred = HealthReminderPolicy.deliveryDeferredUntil(settings, now, zone)
        for ((day, privateOnLock) in visible) {
            val event = if (allowed && deferred == null) store.occurrence(day) else null
            if (event?.state != HealthReminderState.PENDING || maxOf(event.dueAt, event.resumeAt) > now ||
                privateOnLock != settings.hideOnLock) cancel(day)
        }
        val pending = store.pendingDelivery(now)
        if (!allowed || deferred == null) for (event in pending) {
            val posted = allowed && post(event)
            val saved = store.delivered(event, if (posted) HealthReminderDelivery.POSTED else HealthReminderDelivery.IN_APP_ONLY)
            if (posted && !saved) cancel(event.day)
        }
        if (!allowed) return null
        val future = store.nextFutureDelivery(now)?.let { maxOf(it, deferred ?: 0L) }
        return listOfNotNull(future, deferred?.takeIf { pending.isNotEmpty() }).minOrNull()
    }

    fun sleep(
        store: HealthReminderStore, alert: HealthSleepAlert?, settings: HealthReminderSettings, now: Long, zone: ZoneId,
        systemAllowed: Boolean, visible: Map<String, Boolean>, post: (HealthSleepAlert) -> Boolean, cancel: (String) -> Unit,
    ): Long? {
        val allowed = settings.sleepChanges && settings.notifications && systemAllowed
        val deferred = HealthReminderPolicy.deliveryDeferredUntil(settings, now, zone)
        val pending = alert?.takeIf { it.open && it.state == HealthReminderState.PENDING }
        val due = pending?.let { maxOf(it.openedAt, it.resumeAt) }
        for ((id, privateOnLock) in visible) {
            if (!allowed || deferred != null || pending?.id != id || due == null || due > now ||
                privateOnLock != settings.hideOnLock) cancel(id)
        }
        if (pending == null || due == null || pending.delivery != HealthReminderDelivery.WAITING) return null
        if (allowed && due > now) return maxOf(due, deferred ?: 0L)
        if (!HealthReminderPolicy.deliveryDue(due, now)) return null
        if (allowed && deferred != null) return deferred
        val posted = allowed && post(pending)
        val saved = store.sleepDelivered(pending, if (posted) HealthReminderDelivery.POSTED else HealthReminderDelivery.IN_APP_ONLY)
        if (posted && !saved) cancel(pending.id)
        return null
    }
}

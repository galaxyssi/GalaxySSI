package com.galaxyssi.chat

import java.time.ZoneId

internal data class HealthReportNotice(val id: String, val dueAt: Long, val delivery: HealthReminderDelivery)

internal object HealthReportNotificationDelivery {
    fun reconcile(
        store: HealthReminderStore, settings: HealthReminderSettings, now: Long, zone: ZoneId, systemAllowed: Boolean,
        visible: Map<String, Boolean>, lookup: (Set<String>) -> Map<String, HealthReportReview>,
        post: (HealthReportReview) -> Boolean, cancel: (String) -> Unit
    ): Long? {
        val allowed = settings.reportReviews && settings.notifications && systemAllowed
        val quietUntil = HealthReminderPolicy.quietUntil(settings, now, zone)
        val deferUntil = maxOf(settings.pauseUntil, quietUntil ?: 0L)
        val due = if (!allowed || deferUntil <= now) store.dueReportNotices(now) else emptyList()
        val ids = visible.keys + due.map { it.id }
        val reports = if (allowed && ids.isNotEmpty()) lookup(ids) else emptyMap()
        for ((id, privateOnLock) in visible) {
            if (!allowed || now < settings.pauseUntil || privateOnLock != settings.hideOnLock ||
                reports[id]?.state(now) != HealthReminderState.PENDING) cancel(id)
        }
        for (notice in due) {
            val review = reports[notice.id]
            val posted = review != null && review.state(now) == HealthReminderState.PENDING && post(review)
            if (!store.finishReportNotice(notice, if (posted) HealthReminderDelivery.POSTED else HealthReminderDelivery.IN_APP_ONLY) && posted) {
                cancel(notice.id)
            }
        }
        val next = store.nextReportNotice() ?: return null
        return when {
            allowed -> maxOf(next, deferUntil, now + 1000L)
            next <= now -> now + 1000L
            else -> null
        }
    }
}

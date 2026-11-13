package com.galaxyssi.chat

import java.time.ZoneId

/** One stable notification per concern; durable receipts prevent replay after dismissal or restart. */
internal object HealthCareModelAttentionDelivery {
    fun reconcile(store: HealthCareStore, settings: HealthReminderSettings, now: Long, zone: ZoneId, systemAllowed: Boolean,
        visible: Map<String, Boolean>, valid: (HealthCareModelAttention) -> Boolean,
        post: (HealthCareModelAttention) -> Boolean, cancel: (String) -> Unit,
        foreground: (HealthCareModelAttention) -> Boolean = { false }): Long? {
        val allowed = settings.modelReviews && settings.notifications && systemAllowed
        val deferred = HealthReminderPolicy.deliveryDeferredUntil(settings, now, zone)
        for ((id, privateOnLock) in visible) {
            val value = store.modelAttention(id)
            if (value == null || value.state !in setOf(HealthCareAttentionState.WAITING, HealthCareAttentionState.POSTED) ||
                !valid(value) || !allowed || deferred != null || foreground(value) || privateOnLock != settings.hideOnLock) cancel(id)
        }
        var failed = false
        for (value in store.pendingModelAttention()) {
            val next = when {
                !valid(value) -> HealthCareAttentionState.STALE
                !allowed || foreground(value) -> HealthCareAttentionState.IN_APP_ONLY
                deferred != null -> null
                visible[value.concernId] == settings.hideOnLock -> HealthCareAttentionState.POSTED
                post(value) -> HealthCareAttentionState.POSTED
                else -> { failed = true; null }
            }
            if (next == HealthCareAttentionState.POSTED && !valid(value)) {
                cancel(value.concernId)
                store.finishModelAttention(value, HealthCareAttentionState.STALE)
            } else if (next != null && !store.finishModelAttention(value, next)) cancel(value.concernId)
        }
        if (store.pendingModelAttention(1).isEmpty()) return null
        return maxOf(now + if (failed) 60_000L else 1000L, if (allowed) deferred ?: 0L else 0L)
    }
}

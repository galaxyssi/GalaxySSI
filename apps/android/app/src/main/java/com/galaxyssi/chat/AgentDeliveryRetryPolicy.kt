package com.galaxyssi.chat

import android.content.Context
import org.json.JSONObject

/** Bounded retries reuse the original Signal ciphertext and all task identifiers. */
internal object AgentDeliveryRetryPolicy {
    const val MAX_RECOVERY_ATTEMPTS = 6
    const val RECOVERY_DELAY_MILLIS = 60_000L
    const val MAX_ACTIVE_AGE_MILLIS = 15 * 60_000L

    fun defer(item: JSONObject, maxAttempts: Int, nowMillis: Long): Boolean {
        val firstAttempt = item.optLong("first_attempt_at", item.optLong("created_at"))
        val age = nowMillis - firstAttempt
        val recoveries = item.optInt("agent_recovery_attempts")
        if (maxAttempts <= 0 || item.optInt("attempts") < maxAttempts ||
            firstAttempt <= 0L || age < 0L || age >= MAX_ACTIVE_AGE_MILLIS - RECOVERY_DELAY_MILLIS ||
            recoveries !in 0 until MAX_RECOVERY_ATTEMPTS ||
            item.optString("attachment_transfer_id").isNotBlank() ||
            (item.optJSONArray("blocked_by_attachment_transfers")?.length() ?: 0) > 0
        ) return false
        item.put("attempts", maxAttempts - 1)
            .put("agent_recovery_attempts", recoveries + 1)
            .put("status", "awaiting_delivery_confirmation")
            .put("next_attempt_at", nowMillis + RECOVERY_DELAY_MILLIS)
            .put("updated_at", nowMillis)
        return true
    }

    fun expired(firstAttemptMillis: Long, nowMillis: Long): Boolean =
        firstAttemptMillis > 0L && (nowMillis < firstAttemptMillis ||
            nowMillis - firstAttemptMillis >= MAX_ACTIVE_AGE_MILLIS)

    fun eligible(context: Context, source: Long, contact: String): Boolean {
        if (source <= 0L || contact.isBlank() || AgentTerminalDeliveryStore.isTerminal(context, source)) return false
        val delivery = AgentPendingDeliveryStore.find(context, source, contact) ?: return false
        if (delivery.contactId != contact || delivery.recoverySuccessorSourceMessageId > 0L ||
            AgentPendingDeliveryStore.isSuperseded(context, source, delivery.conversationId, delivery.turnId)
        ) return false
        return AndroidAgentRemoteRecovery.hasCurrentBinding(context, delivery)
    }
}

package com.galaxyssi.chat

internal object ContactReminderPolicy {
    const val TYPE = "peer_attention"
    const val LIFETIME_MS = 120_000L
    const val SOUND_MS = 30_000L
    val terminal = setOf("acknowledged", "dismissed", "cancelled", "expired", "failed", "disabled")
    val receipts = setOf("received", "quiet", "muted", "acknowledged", "dismissed", "disabled")

    fun valid(id: String, createdAt: Long, expiresAt: Long, now: Long): Boolean =
        id.matches(Regex("[a-zA-Z0-9-]{16,64}")) && createdAt > 0 &&
            createdAt <= now + 30_000 && expiresAt > createdAt &&
            expiresAt - createdAt <= LIFETIME_MS && now < expiresAt

    fun next(current: String, event: String, outgoing: Boolean): String {
        if (current in terminal) return current
        if (event == "expired" || event == "failed") return event
        if (outgoing) {
            if (event == "cancelled") return event
            if (event !in receipts) return current
            if (event in terminal) return event
            if (current == "muted" || (current == "quiet" && event == "received")) return current
            return event
        }
        return if (event in setOf("cancelled", "acknowledged", "dismissed", "muted", "disabled", "quiet"))
            event else current
    }
}

internal data class ContactReminder(
    val id: String,
    val contactId: String,
    val outgoing: Boolean,
    val createdAt: Long,
    val expiresAt: Long,
    val status: String,
    val historyId: Long = 0L
) {
    val terminal get() = status in ContactReminderPolicy.terminal
}

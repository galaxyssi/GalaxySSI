package com.galaxyssi.chat

/** Admission is not PUBACK. Existing receipt maintenance owns retries and lifetime. */
internal class MqttReceiptPublication(
    private val now: () -> Long,
    private val publish: (Set<String>) -> Attempt?
) {
    data class Attempt(val broker: String, val complete: () -> Boolean, val successful: () -> Boolean)
    private val attempts = mutableListOf<Attempt>()
    private var lastSent = Long.MIN_VALUE

    @Synchronized fun send(): Boolean {
        if (attempts.any { it.successful() }) return true
        val at = now()
        if (attempts.any { !it.complete() } && lastSent != Long.MIN_VALUE &&
            at - lastSent < 2 * MqttBrokerCatalog.RECEIPT_RETRY_MS) return false
        val next = publish(attempts.map { it.broker }.toSet()) ?: run {
            if (attempts.all { it.complete() }) attempts.clear()
            return false
        }
        attempts.add(next)
        lastSent = at
        return next.successful()
    }
}

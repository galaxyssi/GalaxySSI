package com.galaxyssi.watch

/** Session-scoped, fail-closed stability gate; no text is persisted or logged. */
internal class WatchConfirmGate {
    private var expires = 0L
    private var candidate = ""
    private var stableSince = 0L
    val hasCandidate: Boolean get() = candidate.isNotEmpty()
    fun arm(now: Long) { cancel(); expires = now + 120_000 }
    fun active(now: Long) = expires > now
    fun cancel() { expires = 0; reset() }
    fun reset() { candidate = ""; stableSince = 0 }
    fun ready(key: String?, now: Long): Boolean {
        if (!active(now)) { cancel(); return false }
        if (key.isNullOrBlank()) { reset(); return false }
        if (key != candidate) { candidate = key; stableSince = now; return false }
        return now - stableSince >= 3000
    }
}

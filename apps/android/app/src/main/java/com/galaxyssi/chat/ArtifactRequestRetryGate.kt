package com.galaxyssi.chat

/** Coalesces taps briefly, but preserves save intent until the artifact arrives. */
internal class ArtifactRequestRetryGate(
    private val nowMillis: () -> Long,
    private val retryAfterMillis: Long = 30_000L
) {
    private val requests = mutableMapOf<String, Long>()

    @Synchronized
    fun add(key: String): Boolean {
        val now = nowMillis()
        val previous = requests[key]
        if (previous != null && now >= previous && now - previous < retryAfterMillis) return false
        requests[key] = now
        return true
    }

    @Synchronized
    fun remove(key: String): Boolean = requests.remove(key) != null
}

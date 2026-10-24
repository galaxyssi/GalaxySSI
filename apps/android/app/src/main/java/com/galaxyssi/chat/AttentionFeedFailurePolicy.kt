package com.galaxyssi.chat

import java.io.IOException
import java.net.URI

internal object AttentionFeedFailurePolicy {
    const val HOST_BACKOFF = 5 * 60_000L
    fun hostKey(url: String): String = "feed-host:" + URI(url).host.lowercase()

    fun affectsHost(failure: Throwable, search: Boolean): Boolean {
        if (search && failure.message == "news_feed_invalid_document") return true
        return generateSequence(failure) { it.cause }.take(8).any {
            it is IOException || it is AgentNativeToolTimeoutException ||
                it is AgentWebMediaException && it.code in setOf("network_error", "dns_failed", "timeout")
        }
    }
}

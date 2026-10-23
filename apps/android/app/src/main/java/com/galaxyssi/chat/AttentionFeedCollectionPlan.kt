package com.galaxyssi.chat

/** A successful publisher must not suppress discovery or any remaining publisher. */
internal object AttentionFeedCollectionPlan {
    const val BATCH_SIZE = 4
    const val CACHE_MILLIS = 30 * 60_000L
    const val MAX_FEED_BYTES = 2 * 1024 * 1024L

    fun endpoints(topic: AttentionTopic): List<String> = ordered(
        ProactiveAttentionWebSources.explicit(topic) + ProactiveAttentionFeedSources.originals(topic),
        ProactiveAttentionFeedPolicy.endpoints(topic))

    // Slow search endpoints must not delay the first batch of independent original publishers.
    fun ordered(publishers: List<String>, discovery: List<String>): List<String> = (publishers + discovery).distinct()

    fun batch(endpoints: List<String>, cursor: Int): List<String> = endpoints.drop(cursor.coerceIn(0, endpoints.size)).take(BATCH_SIZE)

    fun publisher(url: String, label: String): String {
        if (label.isNotBlank() && label != "Hacker News") return label
        return runCatching { java.net.URI(url).host?.removePrefix("www.") }.getOrNull().orEmpty().ifBlank { label }
    }
}

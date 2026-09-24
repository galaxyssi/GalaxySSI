package com.galaxyssi.watch

internal object WatchWakePolicy {
    fun matches(text: String): Boolean = text.lowercase(java.util.Locale.ROOT)
        .trim().split(Regex("[^a-z]+")).filter(String::isNotBlank) == listOf("hello", "hello")

    fun confidentResult(json: String): Boolean = runCatching {
        val result = org.json.JSONObject(json)
        if (!matches(result.optString("text"))) return false
        val words = result.optJSONArray("result") ?: return false
        words.length() == 2 && (0..1).all { words.getJSONObject(it).optDouble("conf", 0.0) >= 0.72 } &&
            (words.getJSONObject(1).optDouble("end") - words.getJSONObject(0).optDouble("start")) in 0.3..3.5
    }.getOrDefault(false)
}

/** Two stable partial hypotheses can catch a phrase when noisy audio never produces an endpoint. */
internal class WatchWakeCandidate {
    private var firstSeenAt = 0L
    fun observe(partial: String, elapsedMs: Long): Boolean {
        val matches = runCatching { WatchWakePolicy.matches(org.json.JSONObject(partial).optString("partial")) }
            .getOrDefault(false)
        if (!matches) { firstSeenAt = 0; return false }
        if (firstSeenAt == 0L) { firstSeenAt = elapsedMs; return false }
        return elapsedMs - firstSeenAt in 650..3500
    }
}

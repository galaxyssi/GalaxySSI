package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.jsoup.Jsoup

/** Firebase's list events are patches, not a stream of complete story objects. */
object ProactiveAttentionPushPolicy {
    const val STREAM = "https://hacker-news.firebaseio.com/v0/newstories.json"
    fun itemUrl(id: Long): String {
        require(id > 0)
        return "https://hacker-news.firebaseio.com/v0/item/$id.json"
    }

    fun apply(previous: JSONObject, type: String, data: String, now: Long): JSONObject {
        require(type in setOf("put", "patch")) { "unsupported_push_event" }
        require(data.length <= 128 * 1024) { "push_event_too_large" }
        val event = JSONObject(data)
        val state = JSONObject(previous.toString())
        var slots = state.optJSONObject("slots") ?: JSONObject()
        val oldIds = ids(slots)
        val path = event.getString("path")
        val value = event.opt("data")
        if (path == "/" && type == "put") {
            slots = JSONObject()
            when (value) {
                is JSONArray -> (0 until value.length()).forEach { put(slots, it.toString(), value.opt(it)) }
                is JSONObject -> value.keys().forEach { put(slots, it, value.opt(it)) }
                JSONObject.NULL, null -> Unit
                else -> error("invalid_push_snapshot")
            }
        } else if (path == "/" && type == "patch" && value is JSONObject) {
            value.keys().forEach { put(slots, it, value.opt(it)) }
        } else if (type == "put" && path.matches(Regex("/\\d+"))) {
            put(slots, path.removePrefix("/"), value)
        } else error("invalid_push_path")
        val pending = state.optJSONObject("pending") ?: JSONObject()
        // The first snapshot establishes a cursor. Reconnect snapshots enqueue only unseen IDs.
        if (state.optBoolean("initialized")) (ids(slots) - oldIds).forEach { id ->
            if (!pending.has(id.toString())) pending.put(id.toString(), JSONObject().put("at", now))
        }
        pending.keys().asSequence().toList().filter {
            pending.getJSONObject(it).optLong("at") < now - 7 * ProactiveAttentionNewsPolicy.DAY
        }.forEach(pending::remove)
        return state.put("initialized", true).put("slots", slots).put("pending", pending).put("event_at", now)
    }

    private fun put(slots: JSONObject, index: String, value: Any?) {
        require(index.toIntOrNull() in 0..1023) { "invalid_push_index" }
        if (value == null || value == JSONObject.NULL) slots.remove(index)
        else {
            require(value is Number && value.toLong() > 0 && value.toDouble() == value.toLong().toDouble())
            slots.put(index, value.toLong())
        }
    }

    private fun ids(slots: JSONObject): Set<Long> = slots.keys().asSequence().map { slots.getLong(it) }.toSet()

    fun article(json: String, expectedId: Long, now: Long): AttentionFeedArticle? {
        val item = JSONObject(json)
        require(item.optLong("id") == expectedId) { "push_story_identity_mismatch" }
        if (item.optString("type") != "story" || item.optBoolean("dead") || item.optBoolean("deleted")) return null
        val time = item.optLong("time")
        if (time < (now - 7 * ProactiveAttentionNewsPolicy.DAY) / 1000 || time > (now + 300_000) / 1000) return null
        val url = ProactiveAttentionFeedPolicy.publicUrl(item.optString("url")) ?: return null
        val title = Jsoup.parse(item.optString("title")).text().take(240)
        if (title.isBlank()) return null
        return AttentionFeedArticle(ProactiveAttentionFeedPolicy.urlKey(url), "", title,
            Jsoup.parse(item.optString("text")).text().take(800), url, "Hacker News", time * 1000, now,
            discoveryDate = true)
    }

    fun retryDelay(previous: Long): Long = (previous.coerceIn(2_500L, 150_000L) * 2).coerceAtMost(300_000L)
}

package com.galaxyssi.chat

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.time.Instant

class ProactiveAttentionPushPolicyTest {
    private val now = Instant.parse("2026-10-14T12:00:00Z").toEpochMilli()
    private fun initial() = ProactiveAttentionPushPolicy.apply(JSONObject(), "put", """{"path":"/","data":[20,19,18]}""", now)

    @Test fun firstSnapshotIsACursorNotFiveHundredNotifications() {
        val state = initial()
        assertTrue(state.getBoolean("initialized"))
        assertEquals(0, state.getJSONObject("pending").length())
    }

    @Test fun patchAndRepeatedReconnectSnapshotQueueOnlyNewStories() {
        val patched = ProactiveAttentionPushPolicy.apply(initial(), "patch", """{"path":"/","data":{"0":21,"1":20,"2":19}}""", now)
        val reopened = ProactiveAttentionPushPolicy.apply(JSONObject(patched.toString()), "put", """{"path":"/","data":[21,20,19]}""", now)
        assertEquals(setOf("21"), reopened.getJSONObject("pending").keys().asSequence().toSet())
        val gap = ProactiveAttentionPushPolicy.apply(reopened, "put", """{"path":"/","data":[23,22,21]}""", now)
        assertEquals(setOf("21", "22", "23"), gap.getJSONObject("pending").keys().asSequence().toSet())
    }

    @Test fun childPutAndRemovalDoNotLoseOtherSlots() {
        val added = ProactiveAttentionPushPolicy.apply(initial(), "put", """{"path":"/0","data":22}""", now)
        assertEquals(19, added.getJSONObject("slots").getLong("1"))
        val removed = ProactiveAttentionPushPolicy.apply(added, "put", """{"path":"/1","data":null}""", now)
        assertFalse(removed.getJSONObject("slots").has("1"))
        assertEquals(1, removed.getJSONObject("pending").length())
    }

    @Test fun malformedEventDoesNotMutateLastGoodCursor() {
        val old = initial()
        val before = old.toString()
        assertTrue(runCatching { ProactiveAttentionPushPolicy.apply(old, "patch", """{"path":"/bad/path","data":{}}""", now) }.isFailure)
        assertEquals(before, old.toString())
        assertTrue(runCatching { ProactiveAttentionPushPolicy.apply(old, "put", """{"path":"/2000000","data":4}""", now) }.isFailure)
    }

    @Test fun submissionDateIsNotClaimedAsOriginalPublicationDate() {
        val json = JSONObject().put("id", 21).put("type", "story").put("time", now / 1000)
            .put("url", "https://example.org/news").put("title", "New OpenAI model").toString()
        val article = ProactiveAttentionPushPolicy.article(json, 21, now)!!
        assertTrue(article.discoveryDate)
        assertEquals("example.org", article.publisher)
        assertEquals("Hacker News", article.discoveredVia)
        assertTrue(ProactiveAttentionFeedSources.matches(article, AttentionTopic("ai_models", "", "")))
        assertEquals(ProactiveAttentionFeedPolicy.urlKey(article.url), article.key)
        assertTrue(runCatching { ProactiveAttentionPushPolicy.article(json, 22, now) }.isFailure)
    }

    @Test fun rejectedStoriesCannotBecomeNews() {
        val item = JSONObject().put("id", 1).put("type", "story").put("time", now / 1000)
            .put("url", "https://example.org/news").put("title", "Example")
        assertNull(ProactiveAttentionPushPolicy.article(JSONObject(item.toString()).put("deleted", true).toString(), 1, now))
        assertNull(ProactiveAttentionPushPolicy.article(JSONObject(item.toString()).put("type", "comment").toString(), 1, now))
        assertNull(ProactiveAttentionPushPolicy.article(JSONObject(item.toString()).put("url", "https://127.0.0.1/").toString(), 1, now))
        assertNull(ProactiveAttentionPushPolicy.article(JSONObject(item.toString()).put("time", (now + 3600_000) / 1000).toString(), 1, now))
    }

    @Test fun retryDelayBacksOffWithoutAnAttemptCountStop() {
        assertEquals(5_000, ProactiveAttentionPushPolicy.retryDelay(0))
        assertEquals(10_000, ProactiveAttentionPushPolicy.retryDelay(5_000))
        assertEquals(300_000, ProactiveAttentionPushPolicy.retryDelay(Long.MAX_VALUE))
    }
}

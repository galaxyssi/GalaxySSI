package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class VoiceAppContextStoreTest {
    private fun context(article: String) = mapOf("voice_active" to true, "conversation_id" to "conversation-a", "article_id" to article)

    @Test fun questionKeepsOriginalArticleAcrossLaterNavigation() {
        val store = VoiceAppContextStore()
        val original = context("article-a").toMutableMap()
        store.capture("trace-a", original)
        original["article_id"] = "article-b"
        store.bind("trace-a", "conversation-a", "turn-a")
        store.capture("trace-b", context("article-c"))
        store.bind("trace-b", "conversation-a", "turn-b")
        assertEquals("article-a", store.get("conversation-a", "turn-a")?.get("article_id"))
        assertEquals("article-c", store.get("conversation-a", "turn-b")?.get("article_id"))
    }

    @Test fun otherConversationAndUnboundTurnCannotReadAnchor() {
        val store = VoiceAppContextStore()
        store.capture("trace", context("article"))
        store.bind("trace", "conversation-b", "turn")
        assertNull(store.get("conversation-b", "turn"))
        assertNull(store.get("conversation-a", "turn"))
    }

    @Test fun identifiersExpireAndSensitiveTextIsNotRetained() {
        var now = 0L
        val store = VoiceAppContextStore { now }
        store.capture("trace", context("article") + mapOf("text" to "private", "body" to "private"))
        store.bind("trace", "conversation-a", "turn")
        assertFalse(store.get("conversation-a", "turn")!!.containsKey("text"))
        assertFalse(store.get("conversation-a", "turn")!!.containsKey("body"))
        now = 600_000
        assertNull(store.get("conversation-a", "turn"))
    }

    @Test fun cacheIsBoundedAndCanBeCleared() {
        val store = VoiceAppContextStore()
        repeat(100) { store.capture("trace-$it", context("article-$it")); store.bind("trace-$it", "conversation-a", "turn-$it") }
        assertNull(store.get("conversation-a", "turn-0"))
        assertNotNull(store.get("conversation-a", "turn-99"))
        store.clear()
        assertNull(store.get("conversation-a", "turn-99"))
    }
}

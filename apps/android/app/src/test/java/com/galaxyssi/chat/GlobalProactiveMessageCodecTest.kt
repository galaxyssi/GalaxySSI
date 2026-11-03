package com.galaxyssi.chat

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class GlobalProactiveMessageCodecTest {
    private fun message() = GlobalProactiveMessage(id = "attention-feed:one", sourceEventId = "research:attention-research:ai:feed:one",
        sourceConversationId = "", target = GlobalProactiveTarget.NEW_CONVERSATION, title = "中文标题", content = "中文预览",
        topic = "主题", urgent = false, status = GlobalProactiveMessageStatus.DELIVERED, causalEventIds = setOf("cause"),
        viewedAtMillis = 200, notifiedAtMillis = 300, createdAtMillis = 100, deliveredAtMillis = 150,
        newsArticleKey = "one", newsTranslationProvider = AttentionMlKitTranslator.PROVIDER)

    @Test fun allDeliveryAndArticleFieldsRoundTrip() {
        assertEquals(message(), GlobalProactiveMessageCodec.decode(GlobalProactiveMessageCodec.encode(message())))
    }
    @Test fun oldHeadlineDoesNotBecomeAReadyArticle() {
        val old = GlobalProactiveMessageCodec.encode(message()).apply { remove("news_article_key"); remove("news_translation_provider") }
        val restored = GlobalProactiveMessageCodec.decode(old)!!
        assertEquals(200L, restored.viewedAtMillis); assertEquals(300L, restored.notifiedAtMillis)
        assertFalse(AttentionArticlePolicy.visible(restored))
    }
    @Test fun legacyNotificationFallbackIsPreserved() {
        val old = GlobalProactiveMessageCodec.encode(message()).apply { remove("notified_at_millis") }
        assertEquals(150L, GlobalProactiveMessageCodec.decode(old)!!.notifiedAtMillis)
    }
    @Test fun obsoleteExtractedArticleIsHiddenUntilRepairedWithoutResettingReadState() {
        val old = GlobalProactiveMessageCodec.encode(message()).apply { remove("news_article_revision") }
        val restored = GlobalProactiveMessageCodec.decode(old)!!
        assertEquals(200L, restored.viewedAtMillis); assertEquals(300L, restored.notifiedAtMillis)
        assertFalse(AttentionArticlePolicy.visible(restored))
        assertTrue(AttentionArticlePolicy.visible(restored.copy(newsArticleRevision = AttentionArticlePolicy.REVISION)))
    }
    @Test fun missingIdentityIsRejectedAndUnknownEnumsKeepFallbacks() {
        assertNull(GlobalProactiveMessageCodec.decode(JSONObject()))
        val old = GlobalProactiveMessageCodec.encode(message()).put("status", "future").put("target", "future")
        assertEquals(GlobalProactiveMessageStatus.PENDING, GlobalProactiveMessageCodec.decode(old)!!.status)
        assertEquals(GlobalProactiveTarget.CURRENT_CONVERSATION, GlobalProactiveMessageCodec.decode(old)!!.target)
    }
}

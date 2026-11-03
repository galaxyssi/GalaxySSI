package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test
import java.time.Instant

class ProactiveAttentionFeedPolicyTest {
    private val now = Instant.parse("2026-10-14T04:00:00Z").toEpochMilli()
    private fun rss(date: String = "Wed, 14 Oct 2026 01:00:00 GMT",
        url: String = "https://example.org/news/one", title: String = "New release",
        summary: String = "&lt;b&gt;Original summary&lt;/b&gt;") =
        "<rss><channel><item><title>$title</title><link>$url</link><description>$summary</description>" +
            "<source>Original publisher</source><pubDate>$date</pubDate></item></channel></rss>"

    @Test fun publishesDatedSourceSummaryWithoutClaimingFullReading() {
        val article = ProactiveAttentionFeedPolicy.parse(rss(), "ai_models", now).single()
        assertEquals("Original summary", article.summary)
        assertEquals("Original publisher", article.publisher)
        assertEquals(now, article.collectedAt)
        assertEquals(Instant.parse("2026-10-14T01:00:00Z").toEpochMilli(), article.publishedAt)
    }

    @Test fun missingStaleAndFutureDatesDoNotBecomeCurrentNews() {
        listOf("", "Wed, 01 Jul 2026 01:00:00 GMT", "2026-10-16").forEach {
            assertTrue(ProactiveAttentionFeedPolicy.parse(rss(date = it), "ai_models", now).isEmpty())
        }
    }

    @Test fun titleOnlyIsAllowedButNeverInventsASummary() {
        assertEquals("", ProactiveAttentionFeedPolicy.parse(rss(summary = ""), "ai_models", now).single().summary)
    }

    @Test fun sourceUrlIdentityIsStableAcrossTopicsAndPolls() {
        val first = ProactiveAttentionFeedPolicy.parse(rss(), "ai_models", now).single()
        val next = ProactiveAttentionFeedPolicy.parse(rss(title = "Updated release"), "technology", now + 1000).single()
        assertEquals(first.key, next.key)
    }

    @Test fun distinctArticlePathsAndFeedUrlsNeverCollapseToOneIdentity() {
        val first = rss(url = "https://example.org/1/012/807.htm")
        val second = rss(url = "https://example.org/1/012/808.htm")
        val combined = first.replace("</channel>", second.substringAfter("<channel>").substringBefore("</channel>") + "</channel>")
        assertEquals(2, ProactiveAttentionFeedPolicy.parse(combined, "ai_models", now).size)
        assertNotEquals(ProactiveAttentionFeedPolicy.urlKey("https://one.example/rss"),
            ProactiveAttentionFeedPolicy.urlKey("https://two.example/rss"))
    }

    @Test fun duplicatesAndTrackingRedirectsDoNotCreateMultipleArticles() {
        val direct = ProactiveAttentionFeedPolicy.parse(rss(), "ai_models", now).single()
        val redirect = "http://www.bing.com/news/apiclick.aspx?url=https%3A%2F%2Fexample.org%2Fnews%2Fone"
        assertEquals(direct.key, ProactiveAttentionFeedPolicy.parse(rss(url = redirect), "ai_models", now).single().key)
        val duplicated = rss().replace("</channel>", rss().substringAfter("<channel>").substringBefore("</channel>") + "</channel>")
        assertEquals(1, ProactiveAttentionFeedPolicy.parse(duplicated, "ai_models", now).size)
    }

    @Test fun rejectsPrivateCredentialAndExecutableLinks() {
        listOf("javascript:alert(1)", "http://example.org/news", "https://127.0.0.1/admin",
            "https://localhost/page", "https://device.local/page", "https://user:pass@example.org/a",
            "https://example.org:8443/a").forEach {
            assertNull(it, ProactiveAttentionFeedPolicy.publicUrl(it))
        }
    }

    @Test(expected = IllegalArgumentException::class) fun challengePagesAreNotSuccessfulEmptyFeeds() {
        ProactiveAttentionFeedPolicy.parse("<html>Please verify</html>", "ai_models", now)
    }

    @Test fun subscriptionsRemainSearchableWithoutModelPrompts() {
        val topic = AttentionTopic("custom", "My research", "folding & design")
        assertTrue(ProactiveAttentionFeedPolicy.endpoints(topic).all { it.contains("folding+%26+design") })
    }

    @Test fun pollingAdaptsWithoutChangingModelBudgets() {
        assertEquals(ProactiveAttentionFeedPolicy.MIN_INTERVAL,
            ProactiveAttentionFeedPolicy.interval(ProactiveAttentionFeedPolicy.MAX_INTERVAL, 1, false))
        assertTrue(ProactiveAttentionFeedPolicy.interval(0, 0, true) > ProactiveAttentionFeedPolicy.MIN_INTERVAL)
        assertEquals(ProactiveAttentionFeedPolicy.MAX_INTERVAL,
            ProactiveAttentionFeedPolicy.interval(Long.MAX_VALUE, 0, true))
    }

    @Test fun reviewPromptIncludesActualDateAndFreshnessBoundary() {
        val task = GlobalResearchTask(id = "attention-research:ai_models", sourceEventId = "test",
            sourceConversationId = "", topic = "AI", question = "News", depth = GlobalResearchDepth.CONTINUOUS_MONITOR,
            preferredSources = emptyList())
        val prompt = ProactiveAttentionNewsPolicy.reviewPrompt(task, org.json.JSONArray(), now)
        assertTrue(prompt.contains("2026-10-14"))
        assertTrue(prompt.contains("2026-10-07"))
    }

    @Test fun regionalPublisherDatesAndTopicFiltersAreSupported() {
        assertEquals(Instant.parse("2026-10-14T04:36:51Z").toEpochMilli(),
            ProactiveAttentionFeedPolicy.date("Wed, 14 Oct 2026 12:36:51 +0800"))
        val article = ProactiveAttentionFeedPolicy.parse(rss(), "ai_models", now).single()
        assertTrue(ProactiveAttentionFeedSources.matches(article.copy(title = "New AI model"),
            AttentionTopic("ai_models", "", "")))
        assertFalse(ProactiveAttentionFeedSources.matches(article.copy(title = "He said hello", summary = ""),
            AttentionTopic("ai_models", "", "")))
        assertFalse(ProactiveAttentionFeedSources.matches(article.copy(title = "New AI model"),
            AttentionTopic("bonds", "", "")))
        assertFalse(ProactiveAttentionFeedSources.matches(article.copy(title = "\u4ea7\u4e1a\u5927\u4f1a", summary = ""),
            AttentionTopic("industry", "", "")))
    }

    @Test fun sourceMarkupCannotInjectInlineMediaIntoTheSummary() {
        val text = ProactiveAttentionFeedPolicy.markdownText("![hidden](https://example.org/a.png)")
        assertTrue(text.startsWith("!\\[hidden\\]"))
    }
}

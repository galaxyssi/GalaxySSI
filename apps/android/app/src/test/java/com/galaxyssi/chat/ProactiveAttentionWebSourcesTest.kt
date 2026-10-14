package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test
import java.time.Instant

class ProactiveAttentionWebSourcesTest {
    private val now = Instant.parse("2026-10-14T12:00:00Z").toEpochMilli()
    @Test fun discoversPublicFeedsButNeverLocalOrExecutableLinks() {
        val html = """<html><head><link rel="alternate" type="application/atom+xml" href="/feed.xml">
            <link rel="alternate" type="application/rss+xml" href="http://localhost/private">
            <link rel="hub" href="https://hub.example/subscribe"></head></html>"""
        val result = ProactiveAttentionWebSources.discover(html, "https://example.org/news", "custom", now)
        assertEquals(listOf("https://example.org/feed.xml"), result.feeds)
        assertTrue(result.articles.isEmpty())
    }
    @Test fun readsDatedStructuredArticlesWithoutExecutingScripts() {
        val html = """<script type="application/ld+json">{"@graph":[{"@type":"NewsArticle",
            "headline":"Example research","url":"/article/1","description":"Source summary",
            "datePublished":"2026-10-14T10:00:00Z","publisher":{"name":"Publisher"}}]}</script>"""
        val article = ProactiveAttentionWebSources.discover(html, "https://example.org/", "research_papers", now).articles.single()
        assertEquals("https://example.org/article/1", article.url)
        assertEquals("Publisher", article.publisher)
        assertFalse(article.discoveryDate)
        assertTrue(ProactiveAttentionWebSources.discover(html.replace("2026-10-14T10:00:00Z", ""), "https://example.org/", "custom", now).articles.isEmpty())
    }
    @Test fun supportsAtomEntriesAlongsideRss() {
        val atom = """<feed xmlns="http://www.w3.org/2005/Atom"><entry><title>New release</title>
            <link rel="self" href="https://example.org/api/1"/><link rel="alternate" href="https://example.org/post/1"/>
            <published>2026-10-14T10:00:00Z</published><summary>Original summary</summary></entry></feed>"""
        val article = ProactiveAttentionFeedPolicy.parse(atom, "open_source", now).single()
        assertEquals("https://example.org/post/1", article.url)
        assertEquals("Original summary", article.summary)
    }
    @Test fun oneMalformedArticleUrlDoesNotHideOtherArticles() {
        val html = """<script type="application/ld+json">[
            {"@type":"NewsArticle","headline":"Broken","url":"https://example.org/%broken","datePublished":"2026-10-14"},
            {"@type":"NewsArticle","headline":"Valid","url":"https://example.org/valid","datePublished":"2026-10-14"}
            ]</script>"""
        val articles = ProactiveAttentionWebSources.discover(html, "https://example.org/", "custom", now).articles
        assertEquals(listOf("https://example.org/valid"), articles.map { it.url })
    }
    @Test fun explicitUrlsAreOptInAndMustBePublicHttps() {
        assertEquals(listOf("https://example.org/news"), ProactiveAttentionWebSources.explicit(
            AttentionTopic("custom", "News", "Follow https://example.org/news and https://localhost/test")))
    }
    @Test fun atomUpdateTimeDoesNotReplaceKnownPublicationTime() {
        val atom = """<feed><entry><title>Example</title><link href="https://example.org/a"/>
            <updated>2026-10-14T11:00:00Z</updated><published>2026-10-14T01:00:00Z</published></entry></feed>"""
        val article = ProactiveAttentionFeedPolicy.parse(atom, "custom", now).single()
        assertEquals(Instant.parse("2026-10-14T01:00:00Z").toEpochMilli(), article.publishedAt)
        assertFalse(article.discoveryDate)
        assertTrue(ProactiveAttentionFeedPolicy.parse(atom.replace("<published>2026-10-14T01:00:00Z</published>", ""), "custom", now).single().discoveryDate)
    }
}

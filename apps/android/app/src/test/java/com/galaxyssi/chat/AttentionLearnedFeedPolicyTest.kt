package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class AttentionLearnedFeedPolicyTest {
    @Test fun discussionFeedsAreNotLearnedAsPublisherNews() {
        val html = """<link rel='alternate' type='application/rss+xml' href='/feed'>
            <link rel='alternate' type='application/rss+xml' href='/comments/feed'>
            <link rel='alternate' type='application/rss+xml' href='/?feed=comments-rss2'>
            <link rel='alternate' type='application/rss+xml' href='/article/feed' title='Comments on: Research'>"""
        assertEquals(listOf("https://publisher.org/feed"), AttentionLearnedFeedPolicy.discover(html, "https://publisher.org/story"))
        assertFalse(AttentionLearnedFeedPolicy.accepts("https://publisher.org/story", "https://publisher.org/comments/feed"))
        assertFalse(AttentionLearnedFeedPolicy.accepts("https://publisher.org/story", "https://publisher.org/rss/comments.xml"))
    }

    @Test fun publisherAliasesKeepExactPathsQueriesAndEncodedSeparatorsDistinct() {
        assertEquals("https://www.publisher.org/story?q=AI", AttentionLearnedFeedPolicy.publisherAlias("https://publisher.org/story?q=AI"))
        assertEquals("https://publisher.org/story", AttentionLearnedFeedPolicy.publisherAlias("https://www.publisher.org/story"))
        assertNull(AttentionLearnedFeedPolicy.publisherAlias("https://publisher.org/a%2Fb"))
        assertNull(AttentionLearnedFeedPolicy.publisherAlias("https://publisher.org/story#section"))
        assertNull(AttentionLearnedFeedPolicy.publisherAlias("file:///story"))
    }

    @Test fun learnsOnlyPublisherDeclaredHttpsFeedsOnTheSameSite() {
        val html = """<head><link rel="alternate" type="application/rss+xml" href="/feed.xml">
            <link rel="ALTERNATE" type="application/atom+xml; charset=utf-8" href="https://www.publisher.org/atom.xml">
            <link rel="alternate" type="text/html" href="/translation"><link rel="stylesheet" href="/style.css">
            <link rel="alternate" type="application/rss+xml" href="https://other.org/feed.xml"></head>"""
        assertEquals(listOf("https://publisher.org/feed.xml", "https://www.publisher.org/atom.xml"),
            AttentionLearnedFeedPolicy.discover(html, "https://publisher.org/article"))
    }

    @Test fun credentialsPrivateHostsWrongSchemesAndFragmentsAreRejected() {
        for (url in listOf("http://publisher.org/feed", "https://user@publisher.org/feed", "https://127.0.0.1/feed",
            "file:///feed", "javascript:alert(1)", "https://publisher.org/feed#x", "https://publisher.org.evil.example/feed")) {
            assertFalse(url, AttentionLearnedFeedPolicy.accepts("https://publisher.org/article", url))
        }
        assertFalse(AttentionLearnedFeedPolicy.accepts("https://local.test/", "https://publisher.org/feed"))
    }

    @Test fun subscriptionsAreBoundedAndDoNotInventFeedsForProductLandingPages() {
        assertTrue(AttentionLearnedFeedPolicy.discover("<main>Product with no feed</main>", "https://product.org").isEmpty())
        val html = (1..10).joinToString("") { "<link rel='alternate' type='application/rss+xml' href='/feed-$it'>" }
        assertEquals(2, AttentionLearnedFeedPolicy.discover(html, "https://publisher.org/post").size)
        assertFalse(AttentionLearnedFeedPolicy.needsProbe("https://www.ithome.com/1/news.htm"))
        assertFalse(AttentionLearnedFeedPolicy.needsProbe("https://github.com/owner/project"))
        assertTrue(AttentionLearnedFeedPolicy.needsProbe("https://simonwillison.net/post"))
    }
}

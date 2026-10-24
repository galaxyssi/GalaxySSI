package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class AttentionFeedFailurePolicyTest {
    @Test fun networkTimeoutIsSharedAcrossTopicQueriesOnTheSameHost() {
        assertEquals(AttentionFeedFailurePolicy.hostKey("https://news.example/rss?q=AI"),
            AttentionFeedFailurePolicy.hostKey("https://news.example/rss?q=Biology"))
        assertTrue(AttentionFeedFailurePolicy.affectsHost(AgentNativeToolTimeoutException(), false))
        assertTrue(AttentionFeedFailurePolicy.affectsHost(RuntimeException(java.net.SocketTimeoutException()), false))
    }
    @Test fun malformedSearchDocumentDoesNotLoopAcrossHundredsOfTopics() {
        assertTrue(AttentionFeedFailurePolicy.affectsHost(IllegalStateException("news_feed_invalid_document"), true))
    }
    @Test fun badIndividualFeedOrMissingPageDoesNotDisableOtherFeedsOnPublisher() {
        assertFalse(AttentionFeedFailurePolicy.affectsHost(IllegalStateException("news_feed_invalid_document"), false))
        assertFalse(AttentionFeedFailurePolicy.affectsHost(AgentWebMediaException("http_status", "404"), false))
        assertNotEquals(AttentionFeedFailurePolicy.hostKey("https://a.example/feed"),
            AttentionFeedFailurePolicy.hostKey("https://b.example/feed"))
    }
}

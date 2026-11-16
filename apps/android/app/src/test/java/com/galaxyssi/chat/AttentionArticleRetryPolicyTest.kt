package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AttentionArticleRetryPolicyTest {
    @Test fun stopsAfterTheOriginalAttemptAndThreeFailedRetries() {
        for (previous in 0..2) assertFalse(AttentionArticleRetryPolicy.exhausted(previous))
        assertTrue(AttentionArticleRetryPolicy.exhausted(3))
        assertTrue(AttentionArticleRetryPolicy.exhausted(41))
    }

    @Test fun networkAndQualityFailuresRetainTheirBackoff() {
        assertEquals(60_000L, AttentionArticleRetryPolicy.delay(0, "transport_failed"))
        assertEquals(240_000L, AttentionArticleRetryPolicy.delay(2, "transport_failed"))
        assertEquals(1_800_000L, AttentionArticleRetryPolicy.delay(0, "article_body_missing"))
        assertEquals(7_200_000L, AttentionArticleRetryPolicy.delay(2, "article_body_missing"))
    }
}

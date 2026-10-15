package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class GlobalProactiveNotificationPolicyTest {
    @Test fun pausedLearningKeepsFeedAlertsButNotNewWorldModelInsights() {
        val paused = GlobalAgentSettings(enabled = false, proactiveInsightsEnabled = false)
        assertTrue(GlobalProactiveNotificationPolicy.enabledFor(message("attention-feed:article"), paused))
        assertFalse(GlobalProactiveNotificationPolicy.enabledFor(message("world-model"), paused))
        assertFalse(GlobalProactiveNotificationPolicy.enabledFor(message("attention-feed:article"),
            paused.copy(notificationsEnabled = false)))
        assertTrue(GlobalProactiveNotificationPolicy.enabledFor(message("world-model"), GlobalAgentSettings()))
    }

    @Test fun emptyBatchHasNoNotification() {
        assertNull(GlobalProactiveNotificationPolicy.candidate(emptyList()))
    }

    @Test fun singleFindingKeepsDestinationAndAttentionChannel() {
        val finding = message("one").copy(sourceEventId = "research:attention-research:ai_models:version",
            content = "x".repeat(300), urgent = true)
        val candidate = GlobalProactiveNotificationPolicy.candidate(listOf(finding))!!
        assertTrue(candidate.attention)
        assertTrue(candidate.important)
        assertEquals("conversation-one", candidate.conversationId)
        assertEquals(setOf("one"), candidate.messageIds)
        assertEquals(240, candidate.content.length)
    }

    @Test fun batchKeepsAllReceiptsAndOpensLatestUrgentFinding() {
        val candidate = GlobalProactiveNotificationPolicy.candidate(listOf(
            message("one").copy(urgent = true), message("two").copy(urgent = true), message("three")
        ))!!
        assertEquals("conversation-two", candidate.conversationId)
        assertEquals(setOf("one", "two", "three"), candidate.messageIds)
        assertEquals("GalaxySSI has 3 new insights", candidate.title)
        assertEquals("Topic", candidate.content)
        assertFalse(candidate.attention)
    }

    private fun message(id: String) = GlobalProactiveMessage(
        id = id, sourceEventId = "event-$id", sourceConversationId = "source",
        target = GlobalProactiveTarget.NEW_CONVERSATION, title = "Finding", content = "Evidence", topic = "Topic", urgent = false,
        deliveredConversationId = "conversation-$id", status = GlobalProactiveMessageStatus.DELIVERED
    )
}

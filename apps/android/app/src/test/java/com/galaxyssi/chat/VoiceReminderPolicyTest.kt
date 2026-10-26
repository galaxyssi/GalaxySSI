package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class VoiceReminderPolicyTest {
    private fun item(id: String = "a", kind: String = "personal", at: Long = 1) =
        VoiceReminderItem(id, kind, "Reminder", "A real update", at)
    private fun inbox() = GlobalProactiveInboxItem("a", setOf("a"), "title", "body", "topic",
        GlobalProactiveTarget.CURRENT_CONVERSATION, false, "c", "", emptySet(), 1, 1, 0, null)
    private fun workspace(status: AgentWorkspaceStatus) = AgentWorkspace("w", "s", "c", "t", status = status)

    @Test fun newspaperBodyCannotBecomePersonalEvenWithOrdinaryId() {
        assertFalse(VoiceReminderPolicy.personal(inbox().copy(newsArticleKey = "article")))
        assertFalse(VoiceReminderPolicy.personal(inbox().copy(messageIds = setOf("attention-feed:article"))))
        assertTrue(VoiceReminderPolicy.personal(inbox()))
    }
    @Test fun viewedOrAcknowledgedRemindersAreNotReintroduced() {
        assertFalse(VoiceReminderPolicy.personal(inbox().copy(viewedAtMillis = 1)))
        assertFalse(VoiceReminderPolicy.personal(inbox().copy(feedbackKind = GlobalAgentFeedbackKind.NOT_RELEVANT)))
    }
    @Test fun onlyActionableTaskStatesProduceFollowUps() {
        AgentWorkspaceStatus.entries.forEach { status ->
            assertEquals(status.name, status in setOf(AgentWorkspaceStatus.PAUSED, AgentWorkspaceStatus.BLOCKED,
                AgentWorkspaceStatus.WAITING_CONFIRMATION), VoiceReminderPolicy.taskNeedsAttention(workspace(status)))
        }
    }
    @Test fun cancelledOrOrphanTasksCannotClaimRecovery() {
        assertFalse(VoiceReminderPolicy.taskNeedsAttention(workspace(AgentWorkspaceStatus.PAUSED).copy(cancellationRequested = true)))
        assertFalse(VoiceReminderPolicy.taskNeedsAttention(workspace(AgentWorkspaceStatus.PAUSED).copy(conversationId = "")))
    }
    @Test fun oneSourceCannotStarveOtherSources() {
        val values = (1..50).map { item("personal-$it", at = it.toLong()) } +
            listOf(item("calendar", "calendar"), item("task", "task"), item("news", "news"))
        val selected = VoiceReminderPolicy.select(values)
        assertEquals(5, selected.size)
        assertEquals(listOf("task", "calendar", "personal", "personal", "news"), selected.map { it.kind })
    }
    @Test fun calendarIsSoonestFirstAndPersonalIsNewestFirst() {
        val selected = VoiceReminderPolicy.select(listOf(item("c2", "calendar", 2), item("c1", "calendar", 1),
            item("p1", at = 1), item("p2", at = 2)))
        assertEquals(listOf("c1", "c2", "p2", "p1"), selected.map { it.id })
    }
    @Test fun duplicatesBlanksAndUnknownKindsAreNotRendered() {
        assertEquals(listOf(item()), VoiceReminderPolicy.select(listOf(item(), item(), item(""),
            item("b").copy(content = " "), item("x", "article_body"))))
    }
    @Test fun newsCanOnlyOccupyOneSummaryRow() {
        assertEquals(1, VoiceReminderPolicy.select((1..10).map { item("n$it", "news") }).size)
    }
    @Test fun toolResultDistinguishesUnavailableSourcesFromEmptyData() {
        val result = VoiceReminderSnapshot(emptyList(), mapOf("calendar" to "permission_not_granted",
            "weather" to "not_connected")).toJson()
        assertEquals(emptyList<Any>(), result["reminders"])
        assertEquals(false, result["news_bodies_included"])
        assertEquals("permission_not_granted", (result["sources"] as Map<*, *>)["calendar"])
    }
    @Test fun exactResourceAndConversationIdsReachAllProviders() {
        val json = item("w", "task").copy(resourceId = "workspace", conversationId = "conversation", state = "paused").toJson()
        assertEquals("workspace", json["resource_id"])
        assertEquals("conversation", json["conversation_id"])
        assertEquals("paused", json["state"])
    }
}

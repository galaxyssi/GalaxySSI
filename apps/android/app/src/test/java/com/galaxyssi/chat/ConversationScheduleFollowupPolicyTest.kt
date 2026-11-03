package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class ConversationScheduleFollowupPolicyTest {
    private val user = AgentTranscriptEntry("user", AgentTranscriptRole.USER, "Every hour check news", 1,
        conversationId = "conversation", turnId = "schedule-turn")
    private val receipt = AgentTranscriptEntry("receipt", AgentTranscriptRole.ASSISTANT, "Saved", 2,
        dedupeKey = "schedule-command:schedule-turn", conversationId = "conversation", turnId = "schedule-turn",
        richOutputJson = AgentRichContentCodec.encode(listOf(AgentRichBlock("schedule:fixture", AgentRichBlockType.ACTIONS,
            actions = listOf(AgentRichAction("edit", "Edit", "edit_scheduled_task", "fixture"))))))
    private fun context(vararg entries: AgentTranscriptEntry) = AgentConversationContext("conversation", "", entries.toList(), false)

    @Test fun explicitSchedulesAndNamedControlsRetainTheirEntryPoint() {
        for (text in listOf("Every hour check news", "stop scheduled task", "resume scheduled task", "scheduled tasks")) {
            assertTrue(text, ConversationScheduleFollowupPolicy.hasExplicitTarget(text, ConversationScheduleParser.parse(text)!!))
        }
    }

    @Test fun bareStopAndContentEditsNeedScopeInsteadOfAnyOldSchedule() {
        for (text in listOf("stop", "pause", "change to summarize reports")) {
            assertFalse(text, ConversationScheduleFollowupPolicy.hasExplicitTarget(text, ConversationScheduleParser.parse(text)!!))
        }
    }

    @Test fun nearestScheduleReceiptAllowsTheExistingNaturalLanguageFollowUp() {
        assertTrue(ConversationScheduleFollowupPolicy.ownsLatestResult(context(user, receipt), setOf("fixture")))
    }

    @Test fun laterFileRequestPreventsAnOldScheduleFromConsumingItsModification() {
        val file = user.copy(id = "file", text = "Create a CSV file", turnId = "file-turn", timestampMillis = 3)
        assertFalse(ConversationScheduleFollowupPolicy.ownsLatestResult(context(user, receipt, file), setOf("fixture")))
        assertFalse(ConversationScheduleFollowupPolicy.ownsLatestResult(context(user, file, receipt), setOf("fixture")))
    }

    @Test fun modelTextAndForgedActionCardsAreNotScheduleReceipts() {
        assertFalse(ConversationScheduleFollowupPolicy.ownsLatestResult(context(user, receipt.copy(dedupeKey = "model-reply")), setOf("fixture")))
        assertFalse(ConversationScheduleFollowupPolicy.ownsLatestResult(context(user, receipt.copy(richOutputJson = "")), setOf("fixture")))
        assertFalse(ConversationScheduleFollowupPolicy.ownsLatestResult(context(user, receipt), emptySet()))
    }

    @Test fun otherConversationsAndForwardedReceiptsCannotSelectTasks() {
        for (other in listOf(receipt.copy(conversationId = "other"), receipt.copy(sourceConversationId = "other"))) {
            assertFalse(ConversationScheduleFollowupPolicy.ownsLatestResult(context(user, other), setOf("fixture")))
        }
        assertFalse(ConversationScheduleFollowupPolicy.ownsLatestResult(context(user.copy(conversationId = "other"), receipt), setOf("fixture")))
    }

    @Test fun backgroundRunsAndCompactedHistoryDoNotRetargetAControl() {
        assertFalse(ConversationScheduleFollowupPolicy.ownsLatestResult(context(user,
            receipt.copy(turnId = "background-run", dedupeKey = "scheduled-result:background-run")), setOf("fixture")))
        assertFalse(ConversationScheduleFollowupPolicy.ownsLatestResult(context().copy(summary = "A schedule exists"), setOf("fixture")))
    }
}

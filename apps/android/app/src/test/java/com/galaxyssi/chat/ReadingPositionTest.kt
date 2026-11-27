package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class ReadingPositionTest {
    private fun row(id: String, at: Long = 1, turn: String = id, role: AgentTranscriptRole = AgentTranscriptRole.ASSISTANT) =
        AgentTranscriptEntry(id, role, "fixture", at, conversationId = "test", turnId = turn)
    private fun changed(old: List<AgentTranscriptEntry>, new: List<AgentTranscriptEntry>) =
        ReadingPosition.newAnswer(old, new) { it.id == "approval" }

    @Test fun historyBaselinePagingAndConversationChangesAreSilent() {
        val a = row("a", 10)
        assertFalse(changed(emptyList(), listOf(a)))
        assertFalse(changed(listOf(a), listOf(row("older", 10), a)))
        assertFalse(changed(listOf(a), listOf(a, row("later", 12).copy(conversationId = "other"))))
    }
    @Test fun oldTurnGetsOneSignalForTheFirstBodyNotForPaintingOrStreamingRevisions() {
        val user = row("user", 3, "turn", AgentTranscriptRole.USER)
        val other = row("later-question", 9, role = AgentTranscriptRole.USER)
        val stream = row("agent-stream-body", 4, "turn")
        val base = listOf(user, other)
        assertTrue(changed(base, listOf(user, stream, other)))
        assertFalse(changed(base + stream, base + stream.copy(text = "more text", id = "final", timestampMillis = 15)))
    }
    @Test fun pendingApprovalPreviewAndDeliveryMarkersNeverCountAsAnswers() {
        val user = row("user", turn = "t", role = AgentTranscriptRole.USER)
        val base = listOf(user)
        for (e in listOf(row("approval"), row("agent-stream-preview-1"), row("wait").copy(dedupeKey = "ui-reply-waiting:1"),
            row("failure").copy(dedupeKey = "delivery-failed:1"), row("process", role = AgentTranscriptRole.PROCESS))) {
            assertFalse(changed(base, base + e.copy(turnId = "t")))
        }
        val rich = row("rich", 2, "t").copy(text = "", richOutputJson = "[{}]")
        assertTrue(changed(base, base + rich))
        assertFalse(changed(base + rich, base + rich.copy(richOutputJson = "[{},{}]")))
    }
}

package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class CollaborationPagePolicyTest {
    private fun metadata(member: String = "a", result: Boolean = false, activity: Boolean = false,
        status: AgentSubagentStatus = AgentSubagentStatus.RUNNING, run: String = "run") =
        CollaborationTranscriptMetadata(member, member, "Codex", "Research", status, run,
            result = result, activity = activity, primary = member == "a")
    private fun entry(id: String, text: String = id, meta: CollaborationTranscriptMetadata? = null,
        role: AgentTranscriptRole = AgentTranscriptRole.PROCESS, at: Long = 1) =
        AgentTranscriptEntry(id = id, role = role, text = text, timestampMillis = at,
            conversationId = "group", taskId = "task", turnId = "turn", dedupeKey = id,
            collaborationJson = meta?.encode().orEmpty())

    @Test fun groupNeverRendersGlobalTimerOrSearchProcess() {
        val input = listOf(entry("user", role = AgentTranscriptRole.USER), entry("global-process"),
            entry("member", meta = metadata()))
        assertEquals(listOf("user", "member"), CollaborationPagePolicy.project(input).map { it.id })
    }

    @Test fun memberProgressIsIsolatedEvenWithTheSameProviderAndParentTurn() {
        val rows = CollaborationPagePolicy.project(listOf(entry("a", meta = metadata()),
            entry("b", meta = metadata("b")), entry("search-a", meta = metadata(activity = true), at = 2),
            entry("search-b", meta = metadata("b", activity = true), at = 3)))
        val a = CollaborationTranscriptMetadata.decode(rows[0].collaborationJson)!!
        val b = CollaborationTranscriptMetadata.decode(rows[1].collaborationJson)!!
        assertEquals("search-a", a.summary)
        assertEquals("search-b", b.summary)
        assertNotEquals(a.traceTurnId, b.traceTurnId)
    }

    @Test fun completedStatusDisappearsButResearchHistoryStaysWithTheReply() {
        val rows = CollaborationPagePolicy.project(listOf(
            entry("status", meta = metadata(status = AgentSubagentStatus.SUCCEEDED)),
            entry("search", meta = metadata(activity = true), at = 2),
            entry("result", "answer", metadata(result = true, status = AgentSubagentStatus.SUCCEEDED), at = 3)))
        assertEquals(listOf("result"), rows.map { it.id })
        assertTrue(CollaborationTranscriptMetadata.decode(rows.single().collaborationJson)!!.details.contains("search"))
        assertEquals("answer", rows.single().text)
    }

    @Test fun canonicalReplyKeepsItsRichOutputAndGetsMemberAttribution() {
        val canonical = entry("canonical", "answer", role = AgentTranscriptRole.ASSISTANT, at = 4).copy(richOutputJson = "artifact")
        val rows = CollaborationPagePolicy.project(listOf(
            entry("result", "answer", metadata(result = true, status = AgentSubagentStatus.SUCCEEDED), at = 3), canonical))
        assertEquals(1, rows.size)
        assertEquals("canonical", rows.single().id)
        assertEquals("artifact", rows.single().richOutputJson)
        assertEquals("a", CollaborationTranscriptMetadata.decode(rows.single().collaborationJson)!!.memberId)
    }

    @Test fun failureAndPermissionRequestsRemainVisible() {
        val rows = CollaborationPagePolicy.project(listOf(entry("failed", meta = metadata(status = AgentSubagentStatus.FAILED)),
            entry("remote-approval:1"), entry("failure", role = AgentTranscriptRole.ASSISTANT)))
        assertEquals(3, rows.size)
    }

    @Test fun progressWithoutPagedOutStatusStillHasItsMember() {
        val rows = CollaborationPagePolicy.project(listOf(entry("tool", meta = metadata("b", activity = true))))
        assertEquals("b", CollaborationTranscriptMetadata.decode(rows.single().collaborationJson)!!.memberId)
    }

    @Test fun separateRoundsDoNotOverwriteSearchHistory() {
        val rows = CollaborationPagePolicy.project(listOf(entry("first", meta = metadata()),
            entry("second", meta = metadata(run = "next")),
            entry("search", meta = metadata(activity = true, run = "next"))))
        assertEquals("", CollaborationTranscriptMetadata.decode(rows.first().collaborationJson)!!.summary)
        assertEquals("search", CollaborationTranscriptMetadata.decode(rows[1].collaborationJson)!!.summary)
    }

    @Test fun providerModelIsShownOnce() {
        assertEquals("Codex · gpt-6-astra", CollaborationLabelPolicy.provider("Codex · gpt-6-astra", "gpt-6-astra"))
    }

    @Test fun coordinatorResolvesReversibleAmbiguityWithoutInventingCompletion() {
        val instructions = CollaborationGoalPolicy.instructions(true)
        assertTrue(instructions.contains("assumptions immediately"))
        assertTrue(instructions.contains("own ambiguity resolution"))
        assertTrue(instructions.contains("Do not bypass approval"))
        assertTrue(instructions.contains("never mark the real-world goal achieved"))
    }
}

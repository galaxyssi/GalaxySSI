package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class CollaborationTeamPanelPolicyTest {
    private fun member(id: String) = CollaborationMember(id, id, "codex", "Codex", "Researcher", modelId = "gpt-6-astra")
    private val group = CollaborationGroup("group", listOf(member("Euclid"), member("Lovelace"), member("Turing")))
    private fun entry(id: String, person: String = id, status: AgentSubagentStatus = AgentSubagentStatus.RUNNING,
        stage: String = "VERIFY", result: Boolean = false, connection: String = "", paused: Boolean = false,
        time: Long = 100, conversation: String = "group", details: String = "", run: String = "run") =
        AgentTranscriptEntry(id, AgentTranscriptRole.PROCESS, "Evidence", time, conversationId = conversation,
            collaborationJson = CollaborationTranscriptMetadata(person, person, "Codex", "Researcher", status, run,
                result = result, researchStage = stage, connectionState = connection, paused = paused,
                updatedAtMillis = time, details = details).encode())

    @Test fun rosterIncludesUnassignedAndDynamicallyRecruitedMembers() {
        val rows = CollaborationTeamPanelPolicy.rows(group, emptyList(), listOf(entry("Hopper")))
        assertEquals(listOf("Euclid", "Lovelace", "Turing", "Hopper"), rows.map { it.member.id })
        assertNull(rows.first().metadata)
        assertEquals("gpt-6-astra", rows.first().member.modelId)
        assertEquals(1, CollaborationTeamPanelPolicy.running(rows))
    }

    @Test fun authoritativeCurrentAttemptSupersedesOlderResultAndKeepsAction() {
        val rows = CollaborationTeamPanelPolicy.rows(group,
            listOf(entry("result", "Euclid", AgentSubagentStatus.SUCCEEDED, result = true, time = 500)),
            listOf(entry("current", "Euclid", stage = "REVISE", time = 100)))
        assertEquals("REVISE", rows.first().metadata?.researchStage)
        assertEquals(AgentSubagentStatus.RUNNING, rows.first().metadata?.status)
        assertEquals(1, CollaborationTeamPanelPolicy.running(rows))
    }

    @Test fun oldRemovedMembersAndAnotherConversationNeverLeakIntoRoster() {
        val rows = CollaborationTeamPanelPolicy.rows(group, listOf(entry("Old")),
            listOf(entry("Foreign", conversation = "other")))
        assertEquals(3, rows.size)
        assertTrue(rows.all { it.metadata == null })
        assertNull(CollaborationTeamPanelPolicy.status(rows))
    }

    @Test fun nextQueuedStageWinsOverEarlierPublishedResultDuringColdRestore() {
        val result = entry("result", "Euclid", AgentSubagentStatus.SUCCEEDED, stage = "EXPLORE", result = true, time = 500)
        val pending = entry("next", "Euclid", AgentSubagentStatus.QUEUED, stage = "REVISE", time = 50)
        listOf(listOf(result, pending), listOf(pending, result)).forEach { history ->
            val rows = CollaborationTeamPanelPolicy.rows(group, history, emptyList())
            assertEquals("REVISE", rows.first().metadata?.researchStage)
            assertEquals(1, CollaborationTeamPanelPolicy.waiting(rows))
        }
    }

    @Test fun previousRunCannotKeepUnassignedMembersRunningOrPauseTheCurrentTeam() {
        val rows = CollaborationTeamPanelPolicy.rows(group, listOf(
            entry("Euclid", run = "old"), entry("Lovelace", status = AgentSubagentStatus.SUCCEEDED, paused = true, run = "old")),
            listOf(entry("Turing", run = "new")))
        assertNull(rows.first().metadata)
        assertEquals(1, CollaborationTeamPanelPolicy.running(rows))
        assertEquals(ConversationHubAgentStatus.RUNNING, CollaborationTeamPanelPolicy.status(rows))
        assertEquals(false, rows[1].metadata?.paused)
    }

    @Test fun transcriptKeepsPublishedRepliesAndControlCardsOnly() {
        val user = AgentTranscriptEntry("user", AgentTranscriptRole.USER, "Continue", 1, conversationId = "group")
        val control = AgentTranscriptEntry("permission", AgentTranscriptRole.PROCESS, "Permission required", 2, conversationId = "group")
        val entries = listOf(user, entry("pending"), entry("result", result = true), control)
        assertEquals(listOf("user", "result", "permission"), CollaborationTeamPanelPolicy.replies(entries).map { it.id })
    }

    @Test fun waitingAndRecoveryAreNotReportedAsExecuting() {
        val rows = CollaborationTeamPanelPolicy.rows(group, emptyList(), listOf(
            entry("Euclid", connection = "reconciling"), entry("Lovelace", status = AgentSubagentStatus.QUEUED)))
        assertEquals(0, CollaborationTeamPanelPolicy.running(rows))
        assertEquals(2, CollaborationTeamPanelPolicy.waiting(rows))
        assertEquals(ConversationHubAgentStatus.RECONNECTING, CollaborationTeamPanelPolicy.status(rows))
    }

    @Test fun pausedAndCompletedPanelsDoNotAnimate() {
        val paused = CollaborationTeamPanelPolicy.rows(group, emptyList(), listOf(entry("Euclid", paused = true)))
        assertEquals(0, CollaborationTeamPanelPolicy.running(paused))
        assertEquals(0, CollaborationTeamPanelPolicy.waiting(paused))
        assertFalse(CollaborationTeamPanelPolicy.status(paused)!!.animated)
        val completed = CollaborationTeamPanelPolicy.rows(group, emptyList(), listOf(entry("Euclid", status = AgentSubagentStatus.SUCCEEDED)))
        assertEquals(ConversationHubAgentStatus.READ, CollaborationTeamPanelPolicy.status(completed))
    }

    @Test fun emptyContinuationIsWaitingForAPlanNotActiveResearch() {
        val ended = entry("Turing", status = AgentSubagentStatus.SUCCEEDED)
        val metadata = CollaborationTranscriptMetadata.decode(ended.collaborationJson)!!.copy(goalDisposition = "continue")
        val rows = CollaborationTeamPanelPolicy.rows(group, emptyList(), listOf(ended.copy(collaborationJson = metadata.encode())))
        assertTrue(CollaborationTeamPanelPolicy.awaitingPlan(rows))
        assertEquals(0, CollaborationTeamPanelPolicy.running(rows))
        assertEquals(0, CollaborationTeamPanelPolicy.waiting(rows))
        assertFalse(CollaborationTeamPanelPolicy.awaitingPlan(rows.map { it.copy(metadata = it.metadata?.copy(paused = true)) }))
    }

    @Test fun processDetailsStayAssociatedWithTheirExactAttempt() {
        val rows = CollaborationTeamPanelPolicy.rows(group, listOf(entry("old", "Euclid", details = "Observed evidence")),
            listOf(entry("current", "Euclid")))
        assertEquals("Observed evidence", rows.first().metadata?.details)
    }

    @Test fun supportsFull1024MemberRosterWithoutDuplicatingAttempts() {
        val group = CollaborationGroup("group", (1..1024).map { member("Member$it") })
        val rows = CollaborationTeamPanelPolicy.rows(group, emptyList(), group.members.flatMap {
            listOf(entry(it.id), entry("later-${it.id}", it.id, stage = "REVISE"))
        })
        assertEquals(1024, rows.size)
        assertEquals(1024, CollaborationTeamPanelPolicy.running(rows))
        assertTrue(rows.all { it.metadata?.researchStage == "REVISE" })
    }
}

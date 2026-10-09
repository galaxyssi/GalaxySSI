package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class CollaborationUnifiedStateTest {
    private fun member(id: String, person: String = id, status: AgentSubagentStatus = AgentSubagentStatus.RUNNING,
        start: Long = 100L, end: Long = 0L) = AgentTeamMemberSnapshot("codex", "Researcher",
        AgentDeliveryMode.OBSERVE, status, instanceId = id, personId = person, displayName = person,
        collaborationGroupId = "group", executionStartedAtMillis = start, completedAtMillis = end,
        updatedAtMillis = maxOf(start, end))
    private fun team(vararg members: AgentTeamMemberSnapshot) = AgentTeamExecutionSnapshot(
        "run", "team", "group", "turn", "coordinator", "Research", AgentTeamVisibilityMode.VISIBLE,
        AgentTeamExecutionState.INTERRUPTED, members.toList(), createdAtMillis = 50L,
        updatedAtMillis = 250L, interruptedAtMillis = 200L)

    @Test fun oneCurrentRowPerPersonKeepsRunningWorkAndNextDependency() {
        val snapshot = team(member("old", "Turing", AgentSubagentStatus.SUCCEEDED, end = 500L),
            member("running", "Turing"), member("next", "Turing", AgentSubagentStatus.QUEUED),
            member("next-lovelace", "Lovelace", AgentSubagentStatus.QUEUED),
            member("later-lovelace", "Lovelace", AgentSubagentStatus.QUEUED))
        assertEquals(listOf("running", "next-lovelace"), CollaborationCurrentStatePolicy.members(snapshot).map { it.memberId })
    }

    @Test fun interruptedIsRecoveringNotUserPausedOrProvenRunning() {
        val snapshot = team(member("hopper"))
        assertEquals(ConversationHubAgentStatus.RECONNECTING, CollaborationCurrentStatePolicy.status(snapshot, emptyMap()))
        assertEquals(ConversationHubAgentStatus.RECONNECTING, CollaborationCurrentStatePolicy.status(snapshot,
            mapOf("hopper" to CollaborationMemberObservation(300, "Locally dispatched"))))
        val metadata = CollaborationCurrentStatePolicy.metadata(snapshot, snapshot.members.first(), null)
        assertFalse(metadata.paused)
        assertEquals("reconciling", metadata.connectionState)
        assertEquals(0L, metadata.clockStoppedAtMillis)
        assertTrue(CollaborationReplyTiming.isTicking(metadata))
    }

    @Test fun onlyNewAuthenticatedObservationConfirmsOriginalExecution() {
        val snapshot = team(member("hopper"))
        fun status(at: Long, connection: String = "") = CollaborationCurrentStatePolicy.status(snapshot,
            mapOf("hopper" to CollaborationMemberObservation(at, "Checking evidence", connection, confirmed = true)))
        assertEquals(ConversationHubAgentStatus.RECONNECTING, status(150))
        assertEquals(ConversationHubAgentStatus.RUNNING, status(300))
        assertEquals(ConversationHubAgentStatus.RECONNECTING, status(350, "waiting"))
        assertEquals(ConversationHubAgentStatus.RECONNECTING, CollaborationCurrentStatePolicy.status(snapshot,
            mapOf("another-attempt" to CollaborationMemberObservation(500, "Running", confirmed = true))))
    }

    @Test fun explicitPauseStopAndCompletionCannotBeOverriddenByProgress() {
        val snapshot = team(member("hopper"))
        val progress = mapOf("hopper" to CollaborationMemberObservation(300, "Working", confirmed = true))
        assertEquals(ConversationHubAgentStatus.PAUSED, CollaborationCurrentStatePolicy.status(snapshot.copy(paused = true), progress))
        assertEquals(ConversationHubAgentStatus.CANCELLED, CollaborationCurrentStatePolicy.status(
            snapshot.copy(state = AgentTeamExecutionState.CANCELLED), progress))
        val completed = snapshot.members.first().copy(status = AgentSubagentStatus.SUCCEEDED, completedAtMillis = 220)
        val metadata = CollaborationCurrentStatePolicy.metadata(snapshot, completed, progress["hopper"])
        assertEquals(220L, metadata.completedAtMillis)
        assertEquals("", metadata.summary)
        assertFalse(CollaborationReplyTiming.isTicking(metadata))
    }

    @Test fun dependencyNamesAndRealUpdateTimeRoundTrip() {
        val waiting = member("review", "Lovelace", AgentSubagentStatus.QUEUED, start = 0).copy(
            waitingForDependencies = true, pendingDependencyNames = listOf("Hopper", "Euclid"), updatedAtMillis = 70)
        val metadata = CollaborationCurrentStatePolicy.metadata(team(waiting), waiting, null)
        assertEquals("Hopper, Euclid", metadata.dependencies)
        assertEquals(70L, metadata.updatedAtMillis)
        assertEquals(metadata, CollaborationTranscriptMetadata.decode(metadata.encode()))
    }

    @Test fun currentProjectionSurvivesPagedHistoryAndRetainsAllResults() {
        val running = member("new", "Turing")
        val snapshot = team(running)
        fun entry(id: String, metadata: CollaborationTranscriptMetadata) = AgentTranscriptEntry(id,
            AgentTranscriptRole.PROCESS, id, 10, conversationId = "group", taskId = "turn", collaborationJson = metadata.encode())
        val current = CollaborationCurrentStatePolicy.metadata(snapshot, running,
            CollaborationMemberObservation(300, "Latest verified activity", confirmed = true))
        val old = current.copy(current = false, executionMemberId = "old", status = AgentSubagentStatus.FAILED,
            clockStoppedAtMillis = 250, summary = "Stale failure")
        val history = listOf(entry("failure", old), entry("result", old.copy(result = true, status = AgentSubagentStatus.SUCCEEDED)))
        val projected = CollaborationPagePolicy.project(history, listOf(entry("current", current)))
        assertEquals(listOf("result", "current"), projected.map { it.id })
        val visible = CollaborationTranscriptMetadata.decode(projected.last().collaborationJson)!!
        assertEquals("Latest verified activity", visible.summary)
        assertEquals(0L, visible.clockStoppedAtMillis)
        assertTrue(visible.details.contains("failure"))
    }

    @Test fun legacyAutomaticPauseIsEligibleButUserControlsRemainAuthoritative() {
        val run = "run"
        val metadata = mapOf("resource_location" to "distributed", "team_run_id" to run,
            "source_message_id" to AgentTeamDispatchIds.sourceMessageId(run).toString(),
            AgentTeamParentRecoveryPolicy.PAUSED to "true")
        assertTrue(AgentTeamParentRecoveryPolicy.isTeamWait(AgentPhase.PAUSED, metadata))
        assertFalse(AgentTeamParentRecoveryPolicy.isTeamWait(AgentPhase.PAUSED, metadata - AgentTeamParentRecoveryPolicy.PAUSED))
        val audit = listOf(AgentAuditEntry(AgentAuditEvent.TASK_PAUSED,
            "Saved Agent team unavailable; awaiting original outcome", 1))
        assertFalse(AgentTeamParentRecoveryPolicy.userStopped(audit))
        assertTrue(AgentTeamParentRecoveryPolicy.userStopped(audit + AgentAuditEntry(AgentAuditEvent.TASK_PAUSED, "User paused", 2)))
        assertTrue(AgentTeamParentRecoveryPolicy.userStopped(audit + AgentAuditEntry(AgentAuditEvent.TASK_CANCELLED, "User stopped", 2)))
        assertFalse(AgentTeamParentRecoveryPolicy.userStopped(audit + AgentAuditEntry(AgentAuditEvent.TASK_RESUMED, "User resumed", 2)))
    }

    @Test fun newestTerminalFailureIsNotHiddenByAnOlderSuccessfulResult() {
        val snapshot = team(member("old", "Turing", AgentSubagentStatus.SUCCEEDED, end = 100),
            member("new", "Turing", AgentSubagentStatus.FAILED).copy(updatedAtMillis = 300))
        assertEquals("new", CollaborationCurrentStatePolicy.members(snapshot).single().memberId)
    }

    @Test fun remoteCompletionMeansDeliveryPendingNotWholeResearchFinished() {
        val snapshot = team(member("hopper"))
        val progress = mapOf("hopper" to CollaborationMemberObservation(300, "Receiving result", "delivering", true))
        assertEquals(ConversationHubAgentStatus.DELIVERING, CollaborationCurrentStatePolicy.status(snapshot, progress))
        assertEquals(AgentTeamExecutionState.INTERRUPTED, snapshot.state)
        assertEquals(AgentSubagentStatus.RUNNING, snapshot.members.single().status)
    }

    @Test fun evidenceSynchronizationIsDeliveryAndNeverOverridesUserPause() {
        val snapshot = team(member("hopper"))
        val progress = mapOf("hopper" to CollaborationMemberObservation(300, "Synced 12 observations", "evidence_sync"))
        assertEquals(ConversationHubAgentStatus.DELIVERING, CollaborationCurrentStatePolicy.status(snapshot, progress))
        assertEquals(ConversationHubAgentStatus.PAUSED,
            CollaborationCurrentStatePolicy.status(snapshot.copy(paused = true), progress))
        assertEquals("evidence_sync", CollaborationCurrentStatePolicy.metadata(snapshot, snapshot.members.single(),
            progress["hopper"]).connectionState)
    }

    @Test fun backgroundEvidenceCannotReviveCompletedMemberOrChangeItsReplyTime() {
        val completed = member("hopper", status = AgentSubagentStatus.SUCCEEDED, end = 220)
        val reviewer = member("reviewer", "Lovelace", start = 225)
        val snapshot = team(completed, reviewer).copy(state = AgentTeamExecutionState.RUNNING)
        val background = CollaborationMemberObservation(10_000, "Synced remaining history", "evidence_sync")
        val metadata = CollaborationCurrentStatePolicy.metadata(snapshot, completed, background)
        assertEquals(AgentSubagentStatus.SUCCEEDED, metadata.status)
        assertEquals("", metadata.connectionState)
        assertEquals("", metadata.summary)
        assertEquals(220L, metadata.updatedAtMillis)
        assertEquals(220L, metadata.completedAtMillis)
        assertFalse(CollaborationReplyTiming.isTicking(metadata))
        assertEquals(ConversationHubAgentStatus.RUNNING,
            CollaborationCurrentStatePolicy.status(snapshot, mapOf("hopper" to background)))
    }

    @Test fun activeTeamWithConnectionLossUsesTheSameRecoveringState() {
        val snapshot = team(member("hopper")).copy(state = AgentTeamExecutionState.RUNNING)
        assertEquals(ConversationHubAgentStatus.RECONNECTING, CollaborationCurrentStatePolicy.status(snapshot,
            mapOf("hopper" to CollaborationMemberObservation(300, "Offline", "waiting"))))
    }

    @Test fun conversationProjectionRequiresExactParentIdentityAndDoesNotResumeUserPause() {
        val snapshot = team(member("hopper"))
        val workspace = AgentWorkspace("turn", "session", "group", "turn", status = AgentWorkspaceStatus.WAITING_RESPONSE)
        val question = AgentTranscriptEntry("q", AgentTranscriptRole.USER, "Question", 1,
            conversationId = "group", taskId = "turn", turnId = "turn")
        fun status(candidate: AgentTeamExecutionSnapshot, current: AgentWorkspace = workspace) =
            ConversationHubAgentStatusPolicy.resolve(current, question, false, candidate, ConversationHubAgentStatus.RECONNECTING)
        assertEquals(ConversationHubAgentStatus.RECONNECTING, status(snapshot))
        assertEquals(ConversationHubAgentStatus.WAITING_RESPONSE, status(snapshot.copy(taskId = "other")))
        assertEquals(ConversationHubAgentStatus.WAITING_RESPONSE, status(snapshot.copy(conversationId = "other")))
        assertEquals(ConversationHubAgentStatus.PAUSED, status(snapshot, workspace.copy(status = AgentWorkspaceStatus.PAUSED)))
        assertEquals(ConversationHubAgentStatus.CANCELLED, status(snapshot, workspace.copy(status = AgentWorkspaceStatus.CANCELLED)))
    }
}

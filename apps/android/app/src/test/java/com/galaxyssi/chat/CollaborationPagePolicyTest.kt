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

    @Test fun separateRoundsKeepOnlyLatestStatusAndRetainEarlierFailureInProcess() {
        val rows = CollaborationPagePolicy.project(listOf(entry("first", "previous timeout",
            metadata(status = AgentSubagentStatus.FAILED)),
            entry("second", meta = metadata(run = "next"), at = 2),
            entry("search", meta = metadata(activity = true, run = "next"), at = 3)))
        assertEquals(listOf("second"), rows.map { it.id })
        val current = CollaborationTranscriptMetadata.decode(rows.single().collaborationJson)!!
        assertEquals("search", current.summary)
        assertTrue(current.details.contains("previous timeout"))
    }

    @Test fun lateOldProgressCannotResurrectFailedAttempt() {
        val rows = CollaborationPagePolicy.project(listOf(
            entry("old", meta = metadata(status = AgentSubagentStatus.FAILED).copy(startedAtMillis = 10)),
            entry("current", meta = metadata(run = "next").copy(startedAtMillis = 20), at = 20),
            entry("late", meta = metadata(activity = true).copy(startedAtMillis = 10), at = 999)))
        assertEquals(listOf("current"), rows.map { it.id })
    }

    @Test fun resultsStayAppendOnlyAndSupersedeOldFailureStatus() {
        val rows = CollaborationPagePolicy.project(listOf(
            entry("failed", meta = metadata(status = AgentSubagentStatus.FAILED)),
            entry("first-result", meta = metadata(result = true, run = "next", status = AgentSubagentStatus.SUCCEEDED), at = 2),
            entry("new-result", meta = metadata(result = true, run = "third", status = AgentSubagentStatus.SUCCEEDED), at = 3)))
        assertEquals(listOf("first-result", "new-result"), rows.map { it.id })
    }

    @Test fun transientConnectionStateDoesNotOverwriteTerminalOrDependencyState() {
        val pending = metadata().copy(waiting = true)
        val wait = metadata(activity = true).copy(connectionState = "waiting")
        val rows = CollaborationPagePolicy.project(listOf(entry("status", meta = pending),
            entry("wait", meta = wait, at = 2)))
        val current = CollaborationTranscriptMetadata.decode(rows.single().collaborationJson)!!
        assertEquals("waiting", current.connectionState)
        assertTrue(current.waiting)
        val failed = CollaborationPagePolicy.project(listOf(entry("status", meta = pending.copy(status = AgentSubagentStatus.FAILED)),
            entry("wait", meta = wait, at = 2)))
        assertEquals("", CollaborationTranscriptMetadata.decode(failed.single().collaborationJson)!!.connectionState)
    }

    @Test fun authenticatedProgressClearsConnectionWaitAndKeepsOtherMembersIndependent() {
        val rows = CollaborationPagePolicy.project(listOf(entry("a", meta = metadata()), entry("b", meta = metadata("b")),
            entry("offline", meta = metadata(activity = true).copy(connectionState = "waiting"), at = 2),
            entry("reading", meta = metadata(activity = true), at = 3)))
        assertEquals(2, rows.size)
        val current = CollaborationTranscriptMetadata.decode(rows.first().collaborationJson)!!
        assertEquals("", current.connectionState)
        assertEquals("reading", current.summary)
    }

    @Test fun stagesSharePersonIdentityButNamesAndProvidersNeverMergeDifferentPeople() {
        val rows = CollaborationPagePolicy.project(listOf(
            entry("old-stage", meta = metadata().copy(executionMemberId = "explore", startedAtMillis = 1,
                status = AgentSubagentStatus.FAILED)),
            entry("current-stage", meta = metadata().copy(executionMemberId = "repair", startedAtMillis = 2)),
            entry("another-person", meta = metadata("b").copy(name = "a", startedAtMillis = 3))))
        assertEquals(listOf("current-stage", "another-person"), rows.map { it.id })
    }

    @Test fun completedReplyRetainsSupersededFailureAndItsToolHistory() {
        val rows = CollaborationPagePolicy.project(listOf(
            entry("old", "original error", metadata(status = AgentSubagentStatus.FAILED)),
            entry("old-tool", "original tool observation", metadata(activity = true), at = 2),
            entry("result", "recovered answer", metadata(result = true, run = "recovered", status = AgentSubagentStatus.SUCCEEDED), at = 3)))
        val detail = CollaborationTranscriptMetadata.decode(rows.single().collaborationJson)!!.details
        assertTrue(detail.contains("original error"))
        assertTrue(detail.contains("original tool observation"))
    }

    @Test fun parallelResultCannotHideStillRunningWorkByTheSamePerson() {
        val rows = CollaborationPagePolicy.project(listOf(
            entry("running", meta = metadata().copy(executionMemberId = "long", startedAtMillis = 10)),
            entry("finished", meta = metadata(result = true, status = AgentSubagentStatus.SUCCEEDED)
                .copy(executionMemberId = "short", startedAtMillis = 20), at = 30)))
        assertEquals(listOf("running", "finished"), rows.map { it.id })
    }

    @Test fun freshRecoveryObservationReplacesPersistedInterruptedSummary() {
        val status = entry("status", meta = metadata().copy(summary = "waiting after restart", clockStoppedAtMillis = 20))
        val old = entry("old", "old progress", metadata(activity = true), at = 10)
        val before = CollaborationPagePolicy.project(listOf(status, old)).single()
        assertEquals("waiting after restart", CollaborationTranscriptMetadata.decode(before.collaborationJson)!!.summary)
        val fresh = entry("recovered", "original task is running", metadata(activity = true), at = 30)
        val after = CollaborationPagePolicy.project(listOf(status, old, fresh)).single()
        assertEquals("original task is running", CollaborationTranscriptMetadata.decode(after.collaborationJson)!!.summary)
    }

    @Test fun providerModelIsShownOnce() {
        assertEquals("Codex · gpt-6-astra", CollaborationLabelPolicy.provider("Codex · gpt-6-astra", "gpt-6-astra"))
    }

    @Test fun canonicalReplyUsesMemberCompletionTimeNotLaterParentDelivery() {
        val meta = metadata(result = true, status = AgentSubagentStatus.SUCCEEDED).copy(startedAtMillis = 1_000L)
        val rows = CollaborationPagePolicy.project(listOf(entry("result", "answer", meta, at = 6_000L),
            entry("canonical", "answer", role = AgentTranscriptRole.ASSISTANT, at = 99_000L)))
        val projected = CollaborationTranscriptMetadata.decode(rows.single().collaborationJson)!!
        assertEquals(6_000L, projected.completedAtMillis)
        assertEquals(5_000L, CollaborationReplyTiming.elapsedMillis(projected, rows.single().timestampMillis, 999_000L))
    }

    @Test fun orphanProgressCannotStartAnUnboundedClock() {
        val rows = CollaborationPagePolicy.project(listOf(entry("tool", meta = metadata(activity = true)
            .copy(startedAtMillis = 1_000L), at = 6_000L)))
        val projected = CollaborationTranscriptMetadata.decode(rows.single().collaborationJson)!!
        assertFalse(CollaborationReplyTiming.isTicking(projected))
        assertEquals(5_000L, CollaborationReplyTiming.elapsedMillis(projected, 6_000L, 999_000L))
    }

    @Test fun coordinatorResolvesReversibleAmbiguityWithoutInventingCompletion() {
        val instructions = CollaborationGoalPolicy.instructions(true)
        assertTrue(instructions.contains("assumptions immediately"))
        assertTrue(instructions.contains("own ambiguity resolution"))
        assertTrue(instructions.contains("Do not bypass approval"))
        assertTrue(instructions.contains("never mark the real-world goal achieved"))
    }
}

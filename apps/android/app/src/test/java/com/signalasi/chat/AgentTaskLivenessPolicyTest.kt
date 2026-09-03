package com.signalasi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentTaskLivenessPolicyTest {
    private val policy = AgentTaskLivenessPolicy(
        queuedWarningMillis = 10L,
        queuedTimeoutMillis = 20L,
        runningWarningMillis = 100L,
        runningTimeoutMillis = 200L,
        waitingResponseWarningMillis = 300L,
        waitingResponseTimeoutMillis = 400L,
        absoluteTimeoutMillis = 1_000L,
        watchdogIntervalMillis = 60_000L,
        heartbeatWriteThrottleMillis = 0L
    )

    @Test
    fun runningTaskWarnsBeforeRequestingModelAssessment() {
        val workspace = workspace(
            status = AgentWorkspaceStatus.RUNNING,
            events = listOf(event(1L, AgentTaskEventKinds.RUNNING, 1_000L))
        )

        assertEquals(
            AgentTaskLivenessState.HEALTHY,
            policy.evaluate(workspace, 1_099L).state
        )
        assertEquals(
            AgentTaskLivenessState.STALLED,
            policy.evaluate(workspace, 1_100L).state
        )
        assertEquals(
            AgentTaskLivenessState.ASSESSMENT_REQUIRED,
            policy.evaluate(workspace, 1_200L).state
        )
    }

    @Test
    fun progressAfterStallClearsUnresolvedWarning() {
        val stalled = workspace(
            status = AgentWorkspaceStatus.RUNNING,
            events = listOf(
                event(1L, AgentTaskEventKinds.RUNNING, 1_000L),
                event(2L, AgentTaskEventKinds.STALLED, 1_100L)
            )
        )
        val recovered = stalled.copy(
            eventSequence = 3L,
            eventJournal = stalled.eventJournal + event(3L, AgentTaskEventKinds.PROGRESS, 1_110L)
        )

        assertTrue(policy.hasUnresolvedStall(stalled))
        assertFalse(policy.hasUnresolvedStall(recovered))
        assertEquals(
            AgentTaskLivenessState.HEALTHY,
            policy.evaluate(recovered, 1_150L).state
        )
    }

    @Test
    fun recoveryWaitDoesNotRetriggerTheSameUnresolvedStall() {
        val waitingForRemote = workspace(
            status = AgentWorkspaceStatus.WAITING_RESPONSE,
            events = listOf(
                event(1L, AgentTaskEventKinds.RUNNING, 1_000L),
                event(2L, AgentTaskEventKinds.STALLED, 1_100L),
                event(3L, AgentTaskEventKinds.RECOVERY_WAITING_RESPONSE, 1_110L)
            )
        )

        assertTrue(policy.hasUnresolvedStall(waitingForRemote))
        assertEquals(
            AgentTaskLivenessState.STALLED,
            policy.evaluate(waitingForRemote, 1_350L).state
        )
    }

    @Test
    fun realRemoteProgressAfterRecoveryWaitReopensLivenessRecovery() {
        val recovered = workspace(
            status = AgentWorkspaceStatus.WAITING_RESPONSE,
            events = listOf(
                event(1L, AgentTaskEventKinds.STALLED, 1_100L),
                event(2L, AgentTaskEventKinds.RECOVERY_WAITING_RESPONSE, 1_110L),
                event(3L, AgentTaskEventKinds.PROGRESS, 1_120L)
            )
        )

        assertFalse(policy.hasUnresolvedStall(recovered))
    }

    @Test
    fun modelAssessmentRemainsPendingUntilRealProgressArrives() {
        val awaitingAssessment = workspace(
            status = AgentWorkspaceStatus.RUNNING,
            events = listOf(
                event(1L, AgentTaskEventKinds.RUNNING, 1_000L),
                event(2L, AgentTaskEventKinds.STALLED, 1_100L),
                event(3L, AgentTaskEventKinds.LIVENESS_ASSESSMENT_REQUESTED, 1_200L)
            )
        )
        val recovered = awaitingAssessment.copy(
            eventSequence = 4L,
            eventJournal = awaitingAssessment.eventJournal +
                event(4L, AgentTaskEventKinds.PROGRESS, 1_210L)
        )

        assertTrue(policy.hasPendingAssessment(awaitingAssessment))
        assertFalse(policy.hasPendingAssessment(recovered))
    }

    @Test
    fun userControlledWaitsDoNotTimeOut() {
        listOf(
            AgentWorkspaceStatus.WAITING_CONFIRMATION,
            AgentWorkspaceStatus.PAUSED,
            AgentWorkspaceStatus.BLOCKED
        ).forEach { status ->
            assertEquals(
                AgentTaskLivenessState.HEALTHY,
                policy.evaluate(workspace(status), 10_000L).state
            )
        }
    }

    @Test
    fun configuredAbsoluteDeadlineRequestsAssessmentWithoutStoppingTheTask() {
        val workspace = workspace(
            status = AgentWorkspaceStatus.RUNNING,
            events = listOf(event(1L, AgentTaskEventKinds.PROGRESS, 1_950L))
        )

        val decision = policy.evaluate(workspace, 2_000L)

        assertEquals(AgentTaskLivenessState.ASSESSMENT_REQUIRED, decision.state)
        assertEquals("absolute_deadline_assessment_due", decision.reason)
    }

    @Test
    fun defaultPolicyAllowsLongTasksThatKeepMakingProgress() {
        val now = 12 * 60 * 60_000L
        val workspace = workspace(
            status = AgentWorkspaceStatus.RUNNING,
            events = listOf(event(1L, AgentTaskEventKinds.PROGRESS, now - 1_000L))
        )

        val decision = AgentTaskLivenessPolicy().evaluate(workspace, now)

        assertEquals(AgentTaskLivenessState.HEALTHY, decision.state)
        assertTrue(decision.lifetimeMillis > 2 * 60 * 60_000L)
    }

    @Test
    fun completedReplySuppressesLateWatchdogPresentation() {
        val entries = listOf(
            transcript(AgentTranscriptRole.USER, "", "turn"),
            transcript(AgentTranscriptRole.PROCESS, "task-watchdog:turn", "turn"),
            transcript(AgentTranscriptRole.ASSISTANT, "result:plan:action:hash", "turn"),
            transcript(
                role = AgentTranscriptRole.ASSISTANT,
                dedupeKey = "assistant-final:turn:other-turn",
                turnId = "other-turn",
                taskId = "turn"
            )
        )

        assertTrue(AgentTaskTerminalReplyPolicy.hasTerminalReply(entries, "turn"))
        assertTrue(AgentTaskTerminalReplyPolicy.hasTerminalReply(entries, "other-turn"))
        assertFalse(AgentTaskTerminalReplyPolicy.hasTerminalReply(entries, "unrelated-turn"))
    }

    @Test
    fun approvalAndTimeoutMessagesAreNotTerminalReplies() {
        val entries = listOf(
            transcript(AgentTranscriptRole.ASSISTANT, "approval:plan:action", "turn"),
            transcript(AgentTranscriptRole.ASSISTANT, "task-watchdog-timeout:turn", "turn")
        )

        assertFalse(AgentTaskTerminalReplyPolicy.hasTerminalReply(entries, "turn"))
    }

    private fun workspace(
        status: AgentWorkspaceStatus,
        events: List<AgentWorkspaceEvent> = emptyList()
    ) = AgentWorkspace(
        workspaceId = "workspace",
        sessionId = "session",
        conversationId = "conversation",
        taskId = "task",
        status = status,
        eventSequence = events.maxOfOrNull(AgentWorkspaceEvent::sequence) ?: 0L,
        eventJournal = events,
        createdAtMillis = 1_000L,
        updatedAtMillis = events.maxOfOrNull(AgentWorkspaceEvent::timestampMillis) ?: 1_000L
    )

    private fun event(sequence: Long, kind: String, timestamp: Long) = AgentWorkspaceEvent(
        sequence = sequence,
        kind = kind,
        timestampMillis = timestamp
    )

    private fun transcript(
        role: AgentTranscriptRole,
        dedupeKey: String,
        turnId: String,
        taskId: String = turnId
    ) =
        AgentTranscriptEntry(
            id = "$role-$dedupeKey",
            role = role,
            text = "message",
            timestampMillis = 1_000L,
            dedupeKey = dedupeKey,
            conversationId = "conversation",
            turnId = turnId,
            taskId = taskId
        )
}

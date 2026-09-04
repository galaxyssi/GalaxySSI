package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentExecutionLoopTimelineTest {
    @Test
    fun canonicalPhasesMapToStructuredRunEvents() {
        val loop = AgentExecutionLoop.create { 1_000L }
        val plan = AgentExecutionLoopTimelinePolicy.project(
            loop.start("task", AgentExecutionLoopBudget())
        )
        val act = AgentExecutionLoopTimelinePolicy.project(
            loop.transition(
                AgentExecutionLoopPhase.ACT,
                actionId = "tool-1",
                toolCall = true
            )
        )
        val observe = AgentExecutionLoopTimelinePolicy.project(
            loop.transition(AgentExecutionLoopPhase.OBSERVE, actionId = "tool-1")
        )
        val replan = AgentExecutionLoopTimelinePolicy.project(
            loop.transition(AgentExecutionLoopPhase.REPLAN, actionId = "tool-1")
        )

        assertEquals(AgentRunControlEventType.PLANNING, plan.controlEventType)
        assertEquals(AgentRunControlEventType.TOOL_STARTED, act.controlEventType)
        assertEquals("tool-1", act.toolCallId)
        assertEquals(AgentRunControlEventType.TOOL_PROGRESS, observe.controlEventType)
        assertEquals(AgentRunControlEventType.RETRYING, replan.controlEventType)
        assertEquals("plan", plan.payload["timeline_kind"])
        assertEquals("tool", act.payload["timeline_kind"])
        assertEquals("retry", replan.payload["timeline_kind"])
    }

    @Test
    fun recoveryFromFailedStateReopensTheRunLedger() {
        val loop = AgentExecutionLoop.create { 1_000L }
        loop.start("task", AgentExecutionLoopBudget(maxRetries = 2))
        loop.transition(AgentExecutionLoopPhase.FAILED, "Temporary failure")
        val recovered = loop.transition(
            AgentExecutionLoopPhase.ACT,
            actionId = "retry",
            retry = true
        )

        val projection = AgentExecutionLoopTimelinePolicy.project(recovered)

        assertEquals(AgentRunControlEventType.RUN_RECOVERED, projection.controlEventType)
        assertEquals(true, projection.payload["loop_retry"])
    }

    @Test
    fun completedLoopUsesExistingFinalReplyInsteadOfAnotherProcessLine() {
        val loop = AgentExecutionLoop.create { 1_000L }
        loop.start("task", AgentExecutionLoopBudget())
        loop.transition(AgentExecutionLoopPhase.VERIFY)
        loop.transition(AgentExecutionLoopPhase.FINALIZE)
        loop.transition(AgentExecutionLoopPhase.LEARN)

        val completed = AgentExecutionLoopTimelinePolicy.project(
            loop.transition(AgentExecutionLoopPhase.COMPLETED)
        )

        assertEquals(AgentRunControlEventType.RUN_COMPLETED, completed.controlEventType)
        assertNull(completed.label)
    }

    @Test
    fun projectionCarriesBoundedUsageAndRevisionMetadata() {
        val loop = AgentExecutionLoop.create { 1_000L }
        loop.start("task", AgentExecutionLoopBudget())
        val event = loop.transition(
            AgentExecutionLoopPhase.ACT,
            actionId = "action",
            toolCall = true
        )

        val projection = AgentExecutionLoopTimelinePolicy.project(event)

        assertEquals(event.snapshot.revision, projection.payload["loop_revision"])
        assertEquals(1, projection.payload["loop_actions"])
        assertEquals(1, projection.payload["loop_tool_calls"])
        assertEquals("action", projection.payload["loop_action_id"])
        assertTrue(AgentExecutionLoopTimelinePolicy.isSameRevision(
            runEvent(projection),
            event.snapshot.revision
        ))
        assertFalse(AgentExecutionLoopTimelinePolicy.isSameRevision(
            runEvent(projection),
            event.snapshot.revision + 1
        ))
    }

    @Test
    fun transcriptKeysRoundTripTheirLoopPhase() {
        val loop = AgentExecutionLoop.create { 1_000L }
        val event = loop.start("task", AgentExecutionLoopBudget())
        val key = AgentExecutionLoopTimelinePolicy.transcriptDedupeKey("turn", event)

        assertEquals(
            AgentExecutionLoopPhase.PLAN,
            AgentExecutionLoopTimelinePolicy.phaseFromTranscriptDedupeKey(key)
        )
        assertNull(AgentExecutionLoopTimelinePolicy.phaseFromTranscriptDedupeKey("audit:1"))
    }

    @Test
    fun detailedToolEventsReplaceGenericLivePlaceholders() {
        val genericAct = transcript("agent-loop:turn:ACT:2", "Executing task step")
        val genericObserve = transcript("agent-loop:turn:OBSERVE:3", "Inspecting result")
        val detailedStart = transcript("audit:4:TOOL_STARTED:1", "Phone Linux: python app.py")
        val detailedComplete = transcript("audit:5:TOOL_COMPLETED:1", "Phone Linux completed")

        val visible = AgentExecutionLoopTimelinePolicy.suppressSupersededPlaceholders(
            listOf(genericAct, genericObserve, detailedStart, detailedComplete)
        )

        assertEquals(listOf(detailedStart, detailedComplete), visible)
    }

    @Test
    fun placeholdersRemainVisibleUntilDetailedToolEventsArrive() {
        val genericAct = transcript("agent-loop:turn:ACT:2", "Executing task step")
        val genericObserve = transcript("agent-loop:turn:OBSERVE:3", "Inspecting result")

        val visible = AgentExecutionLoopTimelinePolicy.suppressSupersededPlaceholders(
            listOf(genericAct, genericObserve)
        )

        assertEquals(listOf(genericAct, genericObserve), visible)
    }

    @Test
    fun activeLocalPhasesCanPauseOrCancel() {
        listOf(
            AgentPhase.PLANNING,
            AgentPhase.WAITING_CONFIRMATION,
            AgentPhase.EXECUTING,
            AgentPhase.VERIFYING
        ).forEach { phase ->
            assertEquals(
                listOf(
                    AgentExecutionLoopTimelineAction.PAUSE,
                    AgentExecutionLoopTimelineAction.CANCEL
                ),
                AgentExecutionLoopTimelinePolicy.actionsForPhase(phase)
            )
        }
    }

    @Test
    fun nonPausableActivePhasesOnlyOfferCancellation() {
        listOf(AgentPhase.OBSERVING, AgentPhase.WAITING_RESPONSE).forEach { phase ->
            assertEquals(
                listOf(AgentExecutionLoopTimelineAction.CANCEL),
                AgentExecutionLoopTimelinePolicy.actionsForPhase(phase)
            )
        }
    }

    @Test
    fun terminalRecoveryActionsMatchTheFailureState() {
        assertEquals(
            listOf(
                AgentExecutionLoopTimelineAction.RETRY,
                AgentExecutionLoopTimelineAction.REPLAN
            ),
            AgentExecutionLoopTimelinePolicy.actionsForPhase(AgentPhase.FAILED)
        )
        assertEquals(
            listOf(
                AgentExecutionLoopTimelineAction.REPLAN,
                AgentExecutionLoopTimelineAction.CANCEL
            ),
            AgentExecutionLoopTimelinePolicy.actionsForPhase(AgentPhase.BLOCKED)
        )
        assertTrue(
            AgentExecutionLoopTimelinePolicy.actionsForPhase(AgentPhase.COMPLETED).isEmpty()
        )
        assertTrue(
            AgentExecutionLoopTimelinePolicy.actionsForPhase(AgentPhase.CANCELLED).isEmpty()
        )
    }

    @Test
    fun runTimelineCoverageIncludesPlanToolsRetryAndResult() {
        val events = listOf(
            controlEvent(AgentRunControlEventType.PLANNING),
            controlEvent(AgentRunControlEventType.TOOL_STARTED, toolCallId = "tool-1"),
            controlEvent(AgentRunControlEventType.TOOL_COMPLETED, toolCallId = "tool-1"),
            controlEvent(AgentRunControlEventType.RETRYING),
            controlEvent(AgentRunControlEventType.RUN_COMPLETED)
        )

        val coverage = AgentRunTimelineContract.coverage(events)

        assertTrue(coverage.hasPlan)
        assertEquals(2, coverage.toolEventCount)
        assertEquals(1, coverage.retryEventCount)
        assertTrue(coverage.hasResult)
        assertTrue(coverage.complete)
    }

    @Test
    fun failedRunIsTerminalButIncompleteWithoutAPlan() {
        val coverage = AgentRunTimelineContract.coverage(
            listOf(controlEvent(AgentRunControlEventType.RUN_FAILED))
        )

        assertTrue(coverage.hasFailure)
        assertTrue(coverage.terminal)
        assertFalse(coverage.complete)
    }

    private fun transcript(key: String, text: String) = AgentTranscriptEntry(
        id = key,
        role = AgentTranscriptRole.PROCESS,
        text = text,
        timestampMillis = 1_000L,
        dedupeKey = key,
        conversationId = "conversation",
        turnId = "turn",
        taskId = "task"
    )

    private fun runEvent(projection: AgentExecutionLoopTimelineProjection) =
        AgentRunControlEvent(
            conversationId = "conversation",
            messageId = "turn",
            taskId = "task",
            runId = "run",
            agentId = "galaxyssi-mobile",
            deviceId = "phone",
            type = projection.controlEventType,
            sequence = 1L,
            payload = projection.payload
        )

    private fun controlEvent(
        type: AgentRunControlEventType,
        toolCallId: String = ""
    ) = AgentRunControlEvent(
        conversationId = "conversation",
        messageId = "turn",
        taskId = "task",
        runId = "run",
        toolCallId = toolCallId,
        agentId = "galaxyssi-mobile",
        deviceId = "phone",
        type = type,
        sequence = 1L
    )
}

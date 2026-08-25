package com.signalasi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentModelToolLoopTimelineTest {
    @Test
    fun modelRoundUpdatesOneVisibleProcessEntry() {
        val requested = AgentModelToolLoopTimelinePolicy.project(
            event(AgentModelToolLoopEventType.MODEL_REQUESTED, sequence = 2, round = 2)
        )
        val responded = AgentModelToolLoopTimelinePolicy.project(
            event(
                AgentModelToolLoopEventType.MODEL_RESPONDED,
                sequence = 3,
                round = 2,
                details = mapOf("tool_call_count" to 3)
            )
        )

        assertEquals("round:2", requested.dedupeSuffix)
        assertEquals(requested.dedupeSuffix, responded.dedupeSuffix)
        assertEquals(AgentModelToolTimelineText.MODEL_REASONING, requested.text)
        assertEquals(AgentModelToolTimelineText.MODEL_SELECTED_TOOLS, responded.text)
        assertEquals(3, responded.count)
    }

    @Test
    fun toolLifecycleAndRetryUpdateOneVisibleProcessEntry() {
        val details = mapOf("tool_id" to "phone.workspace.read")
        val started = AgentModelToolLoopTimelinePolicy.project(
            event(
                AgentModelToolLoopEventType.TOOL_STARTED,
                sequence = 4,
                toolCallId = "call-1",
                invocationId = "invocation-1",
                details = details
            )
        )
        val retrying = AgentModelToolLoopTimelinePolicy.project(
            event(
                AgentModelToolLoopEventType.TOOL_RETRY_SCHEDULED,
                sequence = 5,
                toolCallId = "call-1",
                invocationId = "invocation-1",
                details = details + ("error_code" to "temporary")
            )
        )
        val finished = AgentModelToolLoopTimelinePolicy.project(
            event(
                AgentModelToolLoopEventType.TOOL_FINISHED,
                sequence = 6,
                toolCallId = "call-1",
                invocationId = "invocation-2",
                details = details + ("status" to "succeeded")
            )
        )

        assertEquals("tool:call-1", started.dedupeSuffix)
        assertEquals(started.dedupeSuffix, retrying.dedupeSuffix)
        assertEquals(started.dedupeSuffix, finished.dedupeSuffix)
        assertEquals(AgentModelToolTimelineText.TOOL_RUNNING, started.text)
        assertEquals(AgentModelToolTimelineText.TOOL_RETRYING, retrying.text)
        assertEquals(AgentModelToolTimelineText.TOOL_SUCCEEDED, finished.text)
        assertEquals("phone.workspace.read", finished.payload["tool_id"])
    }

    @Test
    fun modelLoopFailureDoesNotTerminateTheOuterAgentRun() {
        val projection = AgentModelToolLoopTimelinePolicy.project(
            event(
                AgentModelToolLoopEventType.LOOP_FAILED,
                sequence = 7,
                details = mapOf("code" to "model_failed")
            )
        )

        assertEquals(AgentRunControlEventType.STEP_COMPLETED, projection.controlEventType)
        assertEquals(AgentRunTimelineKind.OBSERVE, projection.timelineKind)
        assertEquals(AgentModelToolTimelineText.MODEL_LOOP_STOPPED, projection.text)
        assertEquals("terminal", projection.dedupeSuffix)
        assertFalse(projection.controlEventType == AgentRunControlEventType.RUN_FAILED)
    }

    @Test
    fun projectionDropsSensitiveModelDetails() {
        val projection = AgentModelToolLoopTimelinePolicy.project(
            event(
                AgentModelToolLoopEventType.TOOL_CALL_REJECTED,
                sequence = 8,
                toolCallId = "call-2",
                details = mapOf(
                    "tool_id" to "phone.files.write",
                    "arguments" to mapOf("secret" to "value"),
                    "prompt" to "private prompt",
                    "message" to "Input was rejected"
                )
            )
        )

        assertEquals("Input was rejected", projection.detail)
        assertFalse(projection.payload.containsKey("arguments"))
        assertFalse(projection.payload.containsKey("prompt"))
        assertTrue(projection.payload.containsKey("message"))
    }

    @Test
    fun lifecycleOnlyEventsStayOutOfTheVisibleTranscript() {
        assertNull(
            AgentModelToolLoopTimelinePolicy.project(
                event(AgentModelToolLoopEventType.LOOP_STARTED, sequence = 1)
            ).text
        )
        assertNull(
            AgentModelToolLoopTimelinePolicy.project(
                event(AgentModelToolLoopEventType.LOOP_COMPLETED, sequence = 9)
            ).text
        )
    }

    private fun event(
        type: AgentModelToolLoopEventType,
        sequence: Long,
        round: Int = 1,
        toolCallId: String? = null,
        invocationId: String? = null,
        details: AgentNativeJsonObject = emptyMap()
    ) = AgentModelToolLoopEvent(
        sequence = sequence,
        type = type,
        occurredAtEpochMillis = 1_000L + sequence,
        sessionId = "session",
        turnId = "model-turn",
        taskId = "model-task",
        toolManifestSha256 = "a".repeat(64),
        round = round,
        toolCallId = toolCallId,
        invocationId = invocationId,
        details = details
    )
}

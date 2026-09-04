package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentActiveTurnPolicyTest {
    @Test
    fun `task control words require a local runtime plan`() {
        assertFalse(AgentActiveTurnPolicy.hasLocalControlTarget(hasCurrentPlan = false))
        assertTrue(AgentActiveTurnPolicy.hasLocalControlTarget(hasCurrentPlan = true))
    }

    @Test
    fun `failed persisted task is not treated as an active turn`() {
        assertFalse(
            AgentActiveTurnPolicy.isRuntimeActive(
                phase = AgentPhase.WAITING_RESPONSE,
                loopPhase = AgentExecutionLoopPhase.WAITING_RESPONSE,
                persistedTaskPhase = AgentPhase.FAILED
            )
        )
    }

    @Test
    fun `terminal execution loop is not treated as an active turn`() {
        assertFalse(
            AgentActiveTurnPolicy.isRuntimeActive(
                phase = AgentPhase.WAITING_RESPONSE,
                loopPhase = AgentExecutionLoopPhase.FAILED
            )
        )
    }

    @Test
    fun `waiting response remains active without terminal evidence`() {
        assertTrue(
            AgentActiveTurnPolicy.isRuntimeActive(
                phase = AgentPhase.WAITING_RESPONSE,
                loopPhase = AgentExecutionLoopPhase.WAITING_RESPONSE,
                persistedTaskPhase = AgentPhase.WAITING_RESPONSE
            )
        )
    }

    @Test
    fun explicitContinuationsAreRecognizedWithoutChangingIndependentTasks() {
        assertTrue(AgentActiveTurnPolicy.continuesPriorTask("继续"))
        assertTrue(AgentActiveTurnPolicy.continuesPriorTask("Use the previous result and retry"))
        assertFalse(AgentActiveTurnPolicy.continuesPriorTask("新任务：查今天的新闻"))
        assertFalse(AgentActiveTurnPolicy.continuesPriorTask("hello"))
    }

    @Test
    fun standaloneCommandsInterruptTheActiveTask() {
        listOf(
            "Stop",
            "Cancel the current task.",
            "\u505c\u6b62\u5f53\u524d\u4efb\u52a1",
            "\u4e0d\u7528\u7ee7\u7eed\u4e86"
        ).forEach { request ->
            val decision = AgentActiveTurnPolicy.decide(request, "Build an Android app")
            assertEquals(request, AgentActiveTurnDisposition.INTERRUPT, decision.disposition)
            assertEquals(
                request,
                AgentActiveTurnInterventionKind.INTERRUPT,
                decision.interventionKind
            )
        }
    }

    @Test
    fun explicitNewTasksRemainIndependent() {
        val decision = AgentActiveTurnPolicy.decide(
            "\u65b0\u4efb\u52a1\uff1a\u67e5\u4eca\u5929\u7684\u65b0\u95fb",
            "\u6784\u5efa Android \u5e94\u7528"
        )

        assertEquals(AgentActiveTurnDisposition.INDEPENDENT, decision.disposition)
        assertFalse(decision.intervenes)
    }

    @Test
    fun goalChangesAndConstraintsSteerWithoutFalseInterrupts() {
        val goalChange = AgentActiveTurnPolicy.decide(
            "\u6539\u6210 Android \u539f\u751f\u5e94\u7528",
            "\u505a\u4e00\u4e2a\u7f51\u9875\u5e94\u7528"
        )
        val constraint = AgentActiveTurnPolicy.decide(
            "Do not stop after the first page.",
            "Export the whole report"
        )

        assertEquals(AgentActiveTurnDisposition.STEER, goalChange.disposition)
        assertEquals(
            AgentActiveTurnInterventionKind.GOAL_CHANGE,
            goalChange.interventionKind
        )
        assertEquals(AgentActiveTurnDisposition.STEER, constraint.disposition)
        assertEquals(
            AgentActiveTurnInterventionKind.CONSTRAINT,
            constraint.interventionKind
        )
    }

    @Test
    fun replacementPromptPreservesTheGoalAndLatestInstruction() {
        val prompt = AgentActiveTurnPolicy.supersedingGoal(
            activeGoal = "Build a web game",
            intervention = "Change the goal to an Android game",
            kind = AgentActiveTurnInterventionKind.GOAL_CHANGE
        )

        assertTrue(prompt.contains("Build a web game"))
        assertTrue(prompt.contains("Change the goal to an Android game"))
        assertTrue(prompt.contains("latest instruction has priority"))
    }

    @Test
    fun aNewAttachmentIsIndependentWithoutAnExplicitContinuation() {
        assertEquals(
            AgentActiveTurnDisposition.INDEPENDENT,
            AgentActiveTurnPolicy.decide(
                request = "Review this image",
                activeGoal = "Build an Android app",
                hasNewAttachments = true
            ).disposition
        )
        assertEquals(
            AgentActiveTurnDisposition.STEER,
            AgentActiveTurnPolicy.decide(
                request = "Use this image instead",
                activeGoal = "Review the earlier image",
                hasNewAttachments = true
            ).disposition
        )
    }
}

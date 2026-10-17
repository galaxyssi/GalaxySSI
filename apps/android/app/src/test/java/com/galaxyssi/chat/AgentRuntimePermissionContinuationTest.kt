package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class AgentRuntimePermissionContinuationTest {
    private val pending = AgentRuntimePermissionContinuation("session", "conversation", "turn", "plan", 1,
        "action", listOf("android.permission.CAMERA"))
    private val action = AgentAction("action", AgentActionKind.CALL_NATIVE_TOOL, "camera", AgentRisk.LOW,
        AgentActionStatus.PROPOSED, "Capture test frame")
    private fun plan() = AgentPlan("fixture", ScreenContext("", pageTitle = ""), emptyList(), listOf(action), planId = "plan")

    @Test fun persistedGateRestoresExactScopeWithoutClaimingExecution() {
        val result = pending.result(true)
        assertEquals(pending, AgentRuntimePermissionContinuation.parse(result))
        assertFalse(result.success)
        assertFalse(AgentGoalEvidence.permitsSuccess(result))
        assertEquals("false", result.metadata["dispatch_accepted"])
        assertTrue(pending.matches("session", "conversation", "turn", AgentPhase.BLOCKED, plan()))
        assertTrue(pending.matches("session", "conversation", "turn", AgentPhase.PAUSED, plan()))
    }

    @Test fun differentConversationTurnSessionOrPlanCannotResume() {
        assertFalse(pending.matches("other", "conversation", "turn", AgentPhase.BLOCKED, plan()))
        assertFalse(pending.matches("session", "other", "turn", AgentPhase.BLOCKED, plan()))
        assertFalse(pending.matches("session", "conversation", "other", AgentPhase.BLOCKED, plan()))
        assertFalse(pending.matches("session", "conversation", "turn", AgentPhase.BLOCKED, plan().copy(revision = 2)))
        assertFalse(pending.matches("session", "conversation", "turn", AgentPhase.BLOCKED, plan().copy(planId = "other")))
    }

    @Test fun completedDispatchedOrCancelledWorkNeverResumes() {
        for (status in listOf(AgentActionStatus.COMPLETED, AgentActionStatus.RUNNING,
            AgentActionStatus.WAITING_RESPONSE, AgentActionStatus.FAILED, AgentActionStatus.BLOCKED)) {
            assertFalse(pending.matches("session", "conversation", "turn", AgentPhase.BLOCKED,
                plan().copy(actions = listOf(action.copy(status = status)))))
        }
        for (phase in listOf(AgentPhase.COMPLETED, AgentPhase.CANCELLED, AgentPhase.EXECUTING, AgentPhase.FAILED)) {
            assertFalse(pending.matches("session", "conversation", "turn", phase, plan()))
        }
    }

    @Test fun unscopedAndDispatchedReceiptsCannotBecomePermissionGates() {
        val result = pending.result(false)
        assertNull(AgentRuntimePermissionContinuation.parse(null))
        assertNull(AgentRuntimePermissionContinuation.parse(result.copy(metadata = result.metadata - "permission_turn_id")))
        assertNull(AgentRuntimePermissionContinuation.parse(result.copy(metadata = result.metadata + ("dispatch_accepted" to "true"))))
        assertNull(AgentRuntimePermissionContinuation.parse(result.copy(metadata = result.metadata + ("permission_plan_revision" to "0"))))
    }

    @Test fun settingsAndSyntheticPermissionsCannotTriggerRuntimePrompt() {
        for (permission in listOf("", "android.permission.INTERNET", "android.permission.BIND_ACCESSIBILITY_SERVICE",
            "android.permission.NORMAL_APP_EXECUTION", "arbitrary.tool.permission")) {
            val result = pending.copy(permissions = listOf(permission)).result(false)
            assertNull(AgentRuntimePermissionContinuation.parse(result))
        }
    }
}

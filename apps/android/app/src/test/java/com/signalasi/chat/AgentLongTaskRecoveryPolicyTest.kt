package com.signalasi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

class AgentLongTaskRecoveryPolicyTest {
    @Test
    fun interruptedMutationIsRecoveredThroughObservationAndReplanning() {
        val plan = plan(
            AgentActionStatus.FAILED,
            evidence = AGENT_INTERRUPTED_EXECUTION_EVIDENCE
        )
        val session = session(
            phase = AgentPhase.PAUSED,
            plan = plan,
            result = AgentActionResult("agent-interrupted", false, "Process restarted")
        )

        val decision = AgentLongTaskRecoveryPolicy.decide(
            workspace(AgentWorkspaceStatus.PAUSED),
            session
        )

        assertEquals(AgentLongTaskRecoveryMode.INTERRUPTED_EXECUTION, decision?.mode)
    }

    @Test
    fun livenessAssessmentTakesPriorityOverInterruptedRecovery() {
        val workspace = workspace(AgentWorkspaceStatus.RUNNING).copy(
            eventSequence = 1L,
            eventJournal = listOf(
                AgentWorkspaceEvent(
                    sequence = 1L,
                    kind = AgentTaskEventKinds.LIVENESS_ASSESSMENT_REQUESTED,
                    message = "No progress",
                    timestampMillis = 100L
                )
            )
        )
        val session = session(
            phase = AgentPhase.PAUSED,
            plan = plan(AgentActionStatus.FAILED, AGENT_INTERRUPTED_EXECUTION_EVIDENCE),
            result = AgentActionResult("agent-interrupted", false, "Process restarted")
        )

        val decision = AgentLongTaskRecoveryPolicy.decide(workspace, session)

        assertEquals(AgentLongTaskRecoveryMode.LIVENESS_ASSESSMENT, decision?.mode)
        assertEquals("No progress", decision?.reason)
    }

    @Test
    fun userPausedTaskIsNeverAutomaticallyResumed() {
        val session = session(
            phase = AgentPhase.PAUSED,
            plan = plan(AgentActionStatus.PROPOSED),
            result = AgentActionResult("agent-paused", true, "Paused by user")
        )

        assertNull(
            AgentLongTaskRecoveryPolicy.decide(
                workspace(AgentWorkspaceStatus.PAUSED),
                session
            )
        )
    }

    @Test
    fun activeOrTerminalWorkspaceCannotBeClaimedAgain() {
        val session = session(
            phase = AgentPhase.PAUSED,
            plan = plan(AgentActionStatus.FAILED, AGENT_INTERRUPTED_EXECUTION_EVIDENCE),
            result = AgentActionResult("agent-interrupted", false, "Interrupted")
        )
        val paused = workspace(AgentWorkspaceStatus.PAUSED)

        assertNull(
            AgentLongTaskRecoveryPolicy.decide(
                paused,
                session,
                activeWorkspaceIds = setOf(paused.workspaceId)
            )
        )
        assertNull(
            AgentLongTaskRecoveryPolicy.decide(
                workspace(AgentWorkspaceStatus.COMPLETED),
                session
            )
        )
    }

    @Test
    fun processClaimPreventsConcurrentRecoveryAndCanBeReleased() {
        val workspaceId = "workspace-claim-${System.nanoTime()}"
        val firstClaim = AgentLongTaskRecoveryClaims.tryAcquire(workspaceId)

        assertNotNull(firstClaim)
        assertNull(AgentLongTaskRecoveryClaims.tryAcquire(workspaceId))

        firstClaim?.close()
        val nextClaim = AgentLongTaskRecoveryClaims.tryAcquire(workspaceId)
        assertNotNull(nextClaim)
        nextClaim?.close()
    }

    private fun workspace(status: AgentWorkspaceStatus) = AgentWorkspace(
        workspaceId = "workspace",
        sessionId = "session",
        conversationId = "conversation",
        taskId = "task",
        status = status
    )

    private fun session(
        phase: AgentPhase,
        plan: AgentPlan,
        result: AgentActionResult
    ) = AgentSessionSnapshot(
        sessionId = "session",
        phase = phase,
        currentGoal = "Continue the project",
        currentScreen = ScreenContext(foregroundApp = "SignalASI", pageTitle = "Agent"),
        currentPlan = plan,
        auditTrail = emptyList(),
        lastActionResult = result,
        processInstanceId = AgentProcessIdentity.instanceId,
        updatedAtMillis = 1L
    )

    private fun plan(
        status: AgentActionStatus,
        evidence: String = ""
    ) = AgentPlan(
        goal = "Continue the project",
        screen = ScreenContext(foregroundApp = "SignalASI", pageTitle = "Agent"),
        steps = emptyList(),
        actions = listOf(
            AgentAction(
                id = "action",
                kind = AgentActionKind.CALL_NATIVE_TOOL,
                target = "signalasi.project.repository.status",
                risk = AgentRisk.LOW,
                status = status,
                description = "Inspect repository state",
                evidence = evidence,
                requiresConfirmation = false
            )
        ),
        confirmationRequired = false
    )
}

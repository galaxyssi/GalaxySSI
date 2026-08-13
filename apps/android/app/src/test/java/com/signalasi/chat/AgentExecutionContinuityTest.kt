package com.signalasi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentExecutionContinuityTest {
    @Test
    fun interruptedProjectActionBecomesUnverifiedEvidenceInsteadOfAReplay() {
        val running = AgentAction(
            id = "write-project-file",
            kind = AgentActionKind.CALL_NATIVE_TOOL,
            target = "Phone workspace",
            risk = AgentRisk.MEDIUM,
            status = AgentActionStatus.RUNNING,
            description = "Write the project source file",
            parameters = mapOf("tool_id" to AgentPhoneNativeToolCatalog.WORKSPACE_WRITE_TEXT),
            requiresConfirmation = false
        )
        val recovered = projectPlan(running).recoverInterruptedExecution()

        assertEquals(AgentActionStatus.FAILED, recovered.actions.single().status)
        assertEquals(AGENT_INTERRUPTED_EXECUTION_EVIDENCE, recovered.actions.single().evidence)
        assertTrue(recovered.hasInterruptedExecutionEvidence())

        val scheduled = recovered.markInterruptedRecoveryScheduled()
        assertFalse(scheduled.hasInterruptedExecutionEvidence())
        assertEquals(AGENT_INTERRUPTED_RECOVERY_SCHEDULED_EVIDENCE, scheduled.actions.single().evidence)
    }

    @Test
    fun interruptedRecoveryRequiresInspectionBeforeAnotherMutation() {
        val interrupted = AgentAction(
            id = "run-build",
            kind = AgentActionKind.CALL_NATIVE_TOOL,
            target = "Phone runtime",
            risk = AgentRisk.MEDIUM,
            status = AgentActionStatus.FAILED,
            description = "Build the Android project",
            evidence = AGENT_INTERRUPTED_EXECUTION_EVIDENCE,
            result = "The app process ended before this action produced a verified result",
            requiresConfirmation = false
        )
        val request = AgentRequest(
            goal = "Improve SignalASI and open a pull request",
            screen = ScreenContext(foregroundApp = "com.signalasi.chat", pageTitle = "SignalASI"),
            targets = emptyList(),
            memories = emptyList(),
            runtimeContext = AgentRuntimeContextBuilder.build(
                sessionId = "test",
                goal = "Improve SignalASI and open a pull request",
                screen = ScreenContext(foregroundApp = "com.signalasi.chat", pageTitle = "SignalASI"),
                permissionMode = PermissionMode.AUTO_LOW_RISK,
                highRiskGuard = true,
                memoryCapture = false,
                callableTargets = emptyList(),
                memories = emptyList()
            )
        )

        val prompt = AgentSupervisedProjectLoop.interruptedRecoveryPrompt(request, interrupted)

        assertTrue(prompt.contains("Do not repeat that mutation blindly"))
        assertTrue(prompt.contains("Git status, diff, execution receipts, and artifacts"))
        assertTrue(prompt.contains("Build the Android project"))
    }

    private fun projectPlan(action: AgentAction) = AgentPlan(
        goal = "Improve SignalASI",
        screen = ScreenContext(foregroundApp = "com.signalasi.chat", pageTitle = "SignalASI"),
        steps = emptyList(),
        actions = listOf(action),
        plannerProfile = PHONE_SUPERVISED_PROJECT_PLANNER_PROFILE
    )
}

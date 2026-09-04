package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentSupervisedProjectRecoveryPolicyTest {
    @Test
    fun actualFailureRecoveryTurnsRemainDiagnosticOnly() {
        val history = listOf(
            connector("supervise-phone-project-1"),
            connector("supervise-phone-project-recovery-2-1"),
            connector("supervise-phone-project-recovery-4-2")
        )

        assertEquals(2, AgentSupervisedProjectRecoveryPolicy.recoveryCount(history))
    }

    @Test
    fun verifiedPhoneToolProgressStartsANewRecoveryWindow() {
        val history = listOf(
            connector("supervise-phone-project-recovery-2-1"),
            connector("supervise-phone-project-recovery-4-2"),
            verifiedPhoneTool("inspect-repository"),
            connector("supervise-phone-project-recovery-6-1")
        )

        assertEquals(1, AgentSupervisedProjectRecoveryPolicy.recoveryCount(history))
    }

    @Test
    fun structuredEvidenceDistinguishesUnknownOutcomeFromFailure() {
        val unknown = verifiedPhoneTool("stalled").copy(
            status = AgentActionStatus.FAILED,
            evidence = """{"outcome_state":"unknown","watchdog_reason":"no_progress"}"""
        )
        val failed = verifiedPhoneTool("failed").copy(
            status = AgentActionStatus.FAILED,
            evidence = """{"outcome_state":"failed"}"""
        )

        assertTrue(AgentSupervisedProjectRecoveryPolicy.hasUnknownOutcome(unknown))
        assertFalse(AgentSupervisedProjectRecoveryPolicy.hasUnknownOutcome(failed))
    }

    private fun connector(id: String) = AgentAction(
        id = id,
        kind = AgentActionKind.CALL_CONNECTOR,
        target = "Codex",
        description = "Review evidence",
        risk = AgentRisk.LOW,
        status = AgentActionStatus.COMPLETED,
        parameters = mapOf("connector_task_mode" to PHONE_SUPERVISED_PROJECT_CONNECTOR_MODE),
        requiresConfirmation = false
    )

    private fun verifiedPhoneTool(id: String) = AgentAction(
        id = id,
        kind = AgentActionKind.CALL_NATIVE_TOOL,
        target = AgentOnDeviceRuntimeTools.EXECUTE,
        description = "Inspect repository",
        risk = AgentRisk.LOW,
        status = AgentActionStatus.COMPLETED,
        parameters = mapOf("tool_id" to AgentOnDeviceRuntimeTools.EXECUTE),
        requiresConfirmation = false,
        result = "Repository state inspected",
        evidence = "native_tool_status:succeeded"
    )
}

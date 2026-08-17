package com.signalasi.chat

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentSupervisedProjectRecoveryPolicyTest {
    @Test
    fun successfulObservationTurnsDoNotConsumeFailureRecoveryBudget() {
        val history = (1..20).map { index -> connector("supervise-phone-project-$index") }

        assertTrue(AgentSupervisedProjectRecoveryPolicy.canRecover(history, 3))
    }

    @Test
    fun actualFailureRecoveryTurnsConsumeFailureRecoveryBudget() {
        val history = listOf(
            connector("supervise-phone-project-1"),
            connector("supervise-phone-project-recovery-2-1"),
            connector("supervise-phone-project-recovery-4-2")
        )

        assertFalse(AgentSupervisedProjectRecoveryPolicy.canRecover(history, 2))
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
}

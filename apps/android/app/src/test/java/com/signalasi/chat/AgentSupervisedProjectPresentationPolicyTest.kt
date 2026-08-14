package com.signalasi.chat

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentSupervisedProjectPresentationPolicyTest {
    @Test
    fun `hides the matching supervised ActionPlan stream`() {
        assertFalse(
            AgentSupervisedProjectPresentationPolicy.shouldExposeConnectorStream(
                phase = AgentPhase.WAITING_RESPONSE,
                pendingAction = supervisedConnector(),
                expectedSourceMessageId = 42L,
                incomingSourceMessageId = 42L
            )
        )
    }

    @Test
    fun `keeps ordinary replies and unrelated streams visible`() {
        assertTrue(
            AgentSupervisedProjectPresentationPolicy.shouldExposeConnectorStream(
                phase = AgentPhase.WAITING_RESPONSE,
                pendingAction = supervisedConnector(),
                expectedSourceMessageId = 42L,
                incomingSourceMessageId = 43L
            )
        )
        assertTrue(
            AgentSupervisedProjectPresentationPolicy.shouldExposeConnectorStream(
                phase = AgentPhase.WAITING_RESPONSE,
                pendingAction = supervisedConnector().copy(
                    parameters = mapOf("connector_task_mode" to "ordinary")
                ),
                expectedSourceMessageId = 42L,
                incomingSourceMessageId = 42L
            )
        )
    }

    @Test
    fun `identifies model control payloads so streams never render them as replies`() {
        assertTrue(
            AgentSupervisedProjectControlPayload.isControlPayload(
                """{"execution_location":"phone","summary":"Inspecting the project","actions":[]}"""
            )
        )
        assertFalse(AgentSupervisedProjectControlPayload.isControlPayload("A normal assistant reply"))
    }

    @Test
    fun `supervised connector is always planning only`() {
        val action = supervisedConnector().copy(
            parameters = supervisedConnector().parameters + mapOf(
                INTERNAL_TASK_EXECUTION_MODE to AgentTaskExecutionMode.AUTO_COMPLETE.wireValue
            ),
            requiresConfirmation = true
        ).enforceSupervisedPlanningBoundary()

        assertTrue(action.executionModeWireValue(AgentTaskExecutionMode.AUTO_COMPLETE) == AgentTaskExecutionMode.PLAN_ONLY.wireValue)
        assertFalse(action.requiresConfirmation)
    }

    @Test
    fun `direct connector progress is accepted only for its exact conversation turn`() {
        val binding = PendingDirectConnectorRun(
            action = supervisedConnector(),
            conversationId = "conversation-1",
            turnId = "turn-1",
            taskId = "task-1",
            contactId = "desktop_codex"
        )

        assertTrue(
            AgentSupervisedProjectPresentationPolicy.matchesDirectConnectorTaskEvent(
                binding,
                "desktop_codex",
                "conversation-1",
                "turn-1",
                "task-1"
            )
        )
        assertFalse(
            AgentSupervisedProjectPresentationPolicy.matchesDirectConnectorTaskEvent(
                binding,
                "desktop_codex",
                "conversation-2",
                "turn-1",
                "task-1"
            )
        )
    }

    private fun supervisedConnector() = AgentAction(
        id = "supervisor",
        kind = AgentActionKind.CALL_CONNECTOR,
        target = "Codex",
        description = "Author the next phone project plan",
        risk = AgentRisk.LOW,
        status = AgentActionStatus.WAITING_RESPONSE,
        parameters = mapOf(
            "connector_task_mode" to PHONE_SUPERVISED_PROJECT_CONNECTOR_MODE
        ),
        requiresConfirmation = false
    )
}

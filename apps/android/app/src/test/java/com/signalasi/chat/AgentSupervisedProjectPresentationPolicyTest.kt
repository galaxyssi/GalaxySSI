package com.signalasi.chat

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentSupervisedProjectPresentationPolicyTest {
    @Test
    fun `internal supervised planning failures do not create a user recovery card`() {
        assertFalse(
            AgentSupervisedProjectPresentationPolicy.shouldShowFailureRecovery(
                pendingAction = supervisedConnector(),
                isSupervisedSource = false
            )
        )
        assertFalse(
            AgentSupervisedProjectPresentationPolicy.shouldShowFailureRecovery(
                pendingAction = null,
                isSupervisedSource = true
            )
        )
        assertTrue(
            AgentSupervisedProjectPresentationPolicy.shouldShowFailureRecovery(
                pendingAction = null,
                isSupervisedSource = false
            )
        )
    }

    @Test
    fun `supervised plan failure stays internal after current action changes`() {
        assertFalse(
            AgentSupervisedProjectPresentationPolicy.shouldShowFailureRecovery(
                pendingAction = AgentAction(
                    id = "inspect",
                    kind = AgentActionKind.CALL_NATIVE_TOOL,
                    target = "signalasi.project.repository.inspect",
                    description = "Inspect the phone repository",
                    risk = AgentRisk.LOW,
                    status = AgentActionStatus.COMPLETED
                ),
                isSupervisedSource = false,
                isSupervisedPlan = true
            )
        )
    }

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
    fun `hides a registered supervised source after runtime phase changes`() {
        assertFalse(
            AgentSupervisedProjectPresentationPolicy.shouldExposeConnectorStream(
                phase = AgentPhase.EXECUTING,
                pendingAction = null,
                expectedSourceMessageId = 0L,
                incomingSourceMessageId = 42L,
                isSupervisedSource = true
            )
        )
    }

    @Test
    fun `does not hide an ordinary source solely because another plan is supervised`() {
        assertTrue(
            AgentSupervisedProjectPresentationPolicy.shouldExposeConnectorStream(
                phase = AgentPhase.EXECUTING,
                pendingAction = supervisedConnector(),
                expectedSourceMessageId = 42L,
                incomingSourceMessageId = 43L,
                isSupervisedSource = false
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
    fun `identifies an incomplete supervised control stream before valid JSON exists`() {
        assertTrue(
            AgentSupervisedProjectControlPayload.isControlPayloadFragment(
                """{"execution_location":"phone","summary":"Inspecting""""
            )
        )
        assertTrue(
            AgentSupervisedProjectControlPayload.isControlPayloadFragment(
                """```json
                    {"execution_location":"phone"
                """.trimIndent()
            )
        )
        assertTrue(
            AgentSupervisedProjectControlPayload.isControlPayloadFragment(
                "\uFEFF{\"execution_location\":\"phone\",\"actions\":["
            )
        )
        assertFalse(
            AgentSupervisedProjectControlPayload.isControlPayloadFragment(
                "A normal answer containing a phone execution summary."
            )
        )
        assertTrue(
            AgentSupervisedProjectControlPayload.isTranscriptControlPayload(
                text = "",
                richOutputJson = """{"blocks":[{"text":"{\"execution_location\":\"phone\"}"}]}"""
            )
        )
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
    fun `task complete marker closes from existing verified evidence without another screen capture`() {
        val completion = AgentAction(
            id = "complete",
            kind = AgentActionKind.DRAFT_PLAN,
            target = "task-complete",
            description = "The phone result was verified.",
            risk = AgentRisk.LOW,
            status = AgentActionStatus.PROPOSED,
            requiresConfirmation = false
        )
        val ordinaryDraft = completion.copy(target = "local-agent-runtime")

        assertTrue(AgentTaskCompletionPolicy.closesFromVerifiedEvidence(completion))
        assertFalse(AgentTaskCompletionPolicy.closesFromVerifiedEvidence(ordinaryDraft))
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

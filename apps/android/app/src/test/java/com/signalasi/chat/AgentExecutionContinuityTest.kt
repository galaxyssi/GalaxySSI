package com.signalasi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentExecutionContinuityTest {

    @Test
    fun `persisted restore does not replace a live runtime in the active conversation`() {
        assertFalse(
            AgentWorkspaceRestoreArbitrationPolicy.shouldScanPersistedWorkspaces(
                hasLiveRuntimeInConversation = true,
                hasActiveSupervisorTaskInConversation = false
            )
        )
    }

    @Test
    fun `persisted restore does not race an active supervisor task`() {
        assertFalse(
            AgentWorkspaceRestoreArbitrationPolicy.shouldScanPersistedWorkspaces(
                hasLiveRuntimeInConversation = false,
                hasActiveSupervisorTaskInConversation = true
            )
        )
    }

    @Test
    fun `persisted restore is allowed only while the active conversation is idle`() {
        assertTrue(
            AgentWorkspaceRestoreArbitrationPolicy.shouldScanPersistedWorkspaces(
                hasLiveRuntimeInConversation = false,
                hasActiveSupervisorTaskInConversation = false
            )
        )
        assertTrue(
            AgentWorkspaceRestoreArbitrationPolicy.belongsToActiveConversation(
                candidateConversationId = "conversation-a",
                activeConversationId = "conversation-a"
            )
        )
        assertFalse(
            AgentWorkspaceRestoreArbitrationPolicy.belongsToActiveConversation(
                candidateConversationId = "conversation-b",
                activeConversationId = "conversation-a"
            )
        )
    }

    @Test
    fun `workspace recovery yields when the user starts a newer task`() {
        assertFalse(
            AgentWorkspaceRestoreArbitrationPolicy.stillOwnsRecovery(
                candidateWorkspaceId = "old-workspace",
                startedConversationId = "old-conversation",
                currentConversationId = "new-conversation",
                activeSupervisorWorkspaceIds = setOf("new-workspace"),
                liveRuntimeWorkspaceIds = setOf("new-workspace")
            )
        )
        assertFalse(
            AgentWorkspaceRestoreArbitrationPolicy.stillOwnsRecovery(
                candidateWorkspaceId = "old-workspace",
                startedConversationId = "conversation-a",
                currentConversationId = "conversation-a",
                activeSupervisorWorkspaceIds = setOf("new-workspace"),
                liveRuntimeWorkspaceIds = emptySet()
            )
        )
    }

    @Test
    fun `workspace recovery may continue for its own persisted task`() {
        assertTrue(
            AgentWorkspaceRestoreArbitrationPolicy.stillOwnsRecovery(
                candidateWorkspaceId = "workspace-a",
                startedConversationId = "conversation-a",
                currentConversationId = "conversation-a",
                activeSupervisorWorkspaceIds = setOf("workspace-a"),
                liveRuntimeWorkspaceIds = setOf("workspace-a")
            )
        )
    }

    @Test
    fun backgroundWaitingResponseIsRestoredWithoutOpeningItsConversation() {
        assertTrue(
            AgentWorkspaceRestorePolicy.shouldRestore(
                workspaceStatus = AgentWorkspaceStatus.WAITING_RESPONSE,
                phase = AgentPhase.WAITING_RESPONSE,
                belongsToCurrentConversation = false,
                hasPendingAction = false,
                interruptedRecovery = false
            )
        )
        assertFalse(
            AgentWorkspaceRestorePolicy.shouldRestore(
                workspaceStatus = AgentWorkspaceStatus.PAUSED,
                phase = AgentPhase.PAUSED,
                belongsToCurrentConversation = false,
                hasPendingAction = false,
                interruptedRecovery = false
            )
        )
        assertTrue(
            AgentWorkspaceRestorePolicy.shouldRestore(
                workspaceStatus = AgentWorkspaceStatus.FAILED,
                phase = AgentPhase.WAITING_RESPONSE,
                belongsToCurrentConversation = false,
                hasPendingAction = false,
                interruptedRecovery = false
            )
        )
    }

    @Test
    fun waitingHandoffRecoversOnlyWhenItHasNeitherQueueEntryNorRemoteAcceptance() {
        val pending = mapOf("source_message_id" to "1308")

        assertTrue(
            AgentPendingHandoffRecoveryPolicy.shouldRecover(
                AgentPhase.WAITING_RESPONSE,
                1308L,
                remainsInReliableOutbox = false,
                metadata = pending
            )
        )
        assertFalse(
            AgentPendingHandoffRecoveryPolicy.shouldRecover(
                AgentPhase.WAITING_RESPONSE,
                1308L,
                remainsInReliableOutbox = true,
                metadata = pending
            )
        )
        assertFalse(
            AgentPendingHandoffRecoveryPolicy.shouldRecover(
                AgentPhase.WAITING_RESPONSE,
                1308L,
                remainsInReliableOutbox = false,
                metadata = pending + mapOf(
                    "transport_accepted_at" to "9500",
                    "remote_task_status" to "accepted"
                ),
                nowMillis = 10_000L,
                staleAfterMillis = 1_000L
            )
        )
        assertTrue(
            AgentPendingHandoffRecoveryPolicy.shouldRecover(
                AgentPhase.WAITING_RESPONSE,
                1308L,
                remainsInReliableOutbox = false,
                metadata = pending + mapOf(
                    "transport_accepted_at" to "8000",
                    "remote_task_status" to "accepted"
                ),
                nowMillis = 10_000L,
                staleAfterMillis = 1_000L
            )
        )
        assertFalse(
            AgentPendingHandoffRecoveryPolicy.shouldRecover(
                AgentPhase.WAITING_RESPONSE,
                1308L,
                remainsInReliableOutbox = false,
                metadata = pending + ("remote_task_status" to "running")
            )
        )
    }

    @Test
    fun strandedHandoffRecoveryHasABoundedPersistentBudget() {
        val metadata = mapOf("handoff_recovery_attempt" to "2")

        assertFalse(
            AgentPendingHandoffRecoveryPolicy.shouldRecover(
                AgentPhase.WAITING_RESPONSE,
                1308L,
                remainsInReliableOutbox = false,
                metadata = metadata
            )
        )
        assertTrue(
            AgentPendingHandoffRecoveryPolicy.isExhausted(
                AgentPhase.WAITING_RESPONSE,
                1308L,
                remainsInReliableOutbox = false,
                metadata = metadata
            )
        )
    }

    @Test
    fun blockedInterruptedHandoffRecoveryIsRestored() {
        val action = AgentAction(
            id = "connector-retry",
            kind = AgentActionKind.CALL_CONNECTOR,
            target = "Codex",
            risk = AgentRisk.LOW,
            status = AgentActionStatus.BLOCKED,
            description = "Continue model reasoning",
            parameters = mapOf(
                "handoff_recovery_attempt" to "1",
                "superseded_source_message_id" to "1308"
            ),
            requiresConfirmation = false
        )
        val plan = projectPlan(action)

        assertEquals(
            action,
            AgentPendingHandoffRecoveryPolicy.interruptedRecoveryAction(AgentPhase.BLOCKED, plan)
        )
        assertTrue(
            AgentWorkspaceRestorePolicy.shouldRestore(
                workspaceStatus = AgentWorkspaceStatus.BLOCKED,
                phase = AgentPhase.BLOCKED,
                belongsToCurrentConversation = false,
                hasPendingAction = false,
                interruptedRecovery = false,
                interruptedHandoffRecovery = true
            )
        )
    }

    @Test
    fun runningWorkspaceWithInterruptedEvidenceResumesAfterProcessRestart() {
        val interrupted = AgentAction(
            id = "interrupted-import",
            kind = AgentActionKind.CALL_NATIVE_TOOL,
            target = "Phone workspace",
            risk = AgentRisk.LOW,
            status = AgentActionStatus.FAILED,
            description = "Import project archive",
            requiresConfirmation = false,
            evidence = AGENT_INTERRUPTED_EXECUTION_EVIDENCE
        )
        val plan = projectPlan(interrupted)
        val interruptedResult = AgentActionResult(
            actionId = "agent-interrupted",
            success = false,
            message = "Execution was interrupted"
        )

        assertTrue(
            AgentInterruptedWorkspaceRecoveryPolicy.shouldResume(
                AgentWorkspaceStatus.RUNNING,
                AgentPhase.PAUSED,
                plan,
                interruptedResult
            )
        )
        assertTrue(
            AgentInterruptedWorkspaceRecoveryPolicy.shouldResume(
                AgentWorkspaceStatus.PAUSED,
                AgentPhase.PAUSED,
                plan,
                interruptedResult
            )
        )
        assertTrue(
            AgentInterruptedWorkspaceRecoveryPolicy.shouldResume(
                AgentWorkspaceStatus.WAITING_CONFIRMATION,
                AgentPhase.PAUSED,
                plan,
                interruptedResult
            )
        )
        assertTrue(
            AgentInterruptedWorkspaceRecoveryPolicy.shouldResume(
                AgentWorkspaceStatus.WAITING_RESPONSE,
                AgentPhase.PAUSED,
                plan,
                interruptedResult
            )
        )
        assertTrue(
            AgentInterruptedWorkspaceRecoveryPolicy.shouldResume(
                AgentWorkspaceStatus.FAILED,
                AgentPhase.PAUSED,
                plan,
                interruptedResult
            )
        )
        assertFalse(
            AgentInterruptedWorkspaceRecoveryPolicy.shouldResume(
                AgentWorkspaceStatus.COMPLETED,
                AgentPhase.PAUSED,
                plan,
                interruptedResult
            )
        )
        assertTrue(
            AgentInterruptedWorkspaceRecoveryPolicy.shouldResume(
                AgentWorkspaceStatus.PAUSED,
                AgentPhase.PAUSED,
                plan.markInterruptedRecoveryScheduled(),
                interruptedResult
            )
        )
        assertTrue(
            AgentInterruptedWorkspaceRecoveryPolicy.shouldResume(
                AgentWorkspaceStatus.PAUSED,
                AgentPhase.PAUSED,
                plan.copy(
                    actions = plan.actions.map { it.copy(evidence = "") },
                    actionHistory = emptyList()
                ),
                interruptedResult
            )
        )
        assertFalse(
            AgentInterruptedWorkspaceRecoveryPolicy.shouldResume(
                AgentWorkspaceStatus.PAUSED,
                AgentPhase.PAUSED,
                plan,
                AgentActionResult("agent-paused", true, "Paused by the user")
            )
        )
    }
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

    @Test
    fun persistedConnectorDeliveryFailureIsRecoverable() {
        val plan = projectPlan(
            AgentAction(
                id = "supervise-project",
                kind = AgentActionKind.CALL_CONNECTOR,
                target = "codex",
                risk = AgentRisk.LOW,
                status = AgentActionStatus.FAILED,
                description = "Ask Codex",
                requiresConfirmation = false
            )
        ).markConnectorDeliveryFailed("supervise-project", 1450L)
        val failed = AgentActionResult(
            actionId = "supervise-project",
            success = false,
            message = "The request was not delivered",
            metadata = mapOf(
                "delivery_failed" to "true",
                "source_message_id" to "1450"
            )
        )

        assertTrue(
            AgentConnectorDeliveryRecoveryPolicy.shouldResume(
                workspaceStatus = AgentWorkspaceStatus.FAILED,
                phase = AgentPhase.FAILED,
                lastActionResult = failed,
                plan = plan
            )
        )
        assertTrue(
            AgentWorkspaceRestorePolicy.shouldRestore(
                workspaceStatus = AgentWorkspaceStatus.FAILED,
                phase = AgentPhase.FAILED,
                belongsToCurrentConversation = true,
                hasPendingAction = false,
                interruptedRecovery = false,
                failedDeliveryRecovery = true
            )
        )
    }

    @Test
    fun unrelatedTerminalFailureIsNotRecoveredAsDeliveryFailure() {
        val failed = AgentActionResult(
            actionId = "run-build",
            success = false,
            message = "Compilation failed"
        )

        assertFalse(
            AgentConnectorDeliveryRecoveryPolicy.shouldResume(
                workspaceStatus = AgentWorkspaceStatus.FAILED,
                phase = AgentPhase.FAILED,
                lastActionResult = failed,
                plan = projectPlan(
                    AgentAction(
                        id = "run-build",
                        kind = AgentActionKind.CALL_NATIVE_TOOL,
                        target = "phone-linux",
                        risk = AgentRisk.LOW,
                        status = AgentActionStatus.FAILED,
                        description = "Run build",
                        requiresConfirmation = false
                    )
                )
            )
        )
        assertFalse(
            AgentConnectorDeliveryRecoveryPolicy.shouldResume(
                workspaceStatus = AgentWorkspaceStatus.FAILED,
                phase = AgentPhase.FAILED,
                lastActionResult = failed.copy(
                    metadata = mapOf(
                        "delivery_failed" to "true",
                        "source_message_id" to "0"
                    )
                ),
                plan = projectPlan(
                    AgentAction(
                        id = "run-build",
                        kind = AgentActionKind.CALL_NATIVE_TOOL,
                        target = "phone-linux",
                        risk = AgentRisk.LOW,
                        status = AgentActionStatus.FAILED,
                        description = "Run build",
                        requiresConfirmation = false
                    )
                )
            )
        )
    }

    @Test
    fun persistedPlanEvidenceRecoversWhenResultMetadataWasCompactedAway() {
        val plan = projectPlan(
            AgentAction(
                id = "connector-call",
                kind = AgentActionKind.CALL_CONNECTOR,
                target = "codex",
                risk = AgentRisk.LOW,
                status = AgentActionStatus.FAILED,
                description = "Ask Codex",
                requiresConfirmation = false
            )
        ).markConnectorDeliveryFailed("connector-call", 2048L)

        assertEquals(2048L, plan.connectorDeliveryFailureSourceMessageId())
        assertTrue(
            AgentConnectorDeliveryRecoveryPolicy.shouldResume(
                workspaceStatus = AgentWorkspaceStatus.FAILED,
                phase = AgentPhase.FAILED,
                lastActionResult = AgentActionResult("connector-call", false, "failed"),
                plan = plan
            )
        )
    }

    @Test
    fun successfulNativeDispatchIsRecoveredForObservationInsteadOfReplay() {
        val running = AgentAction(
            id = "clone-project",
            kind = AgentActionKind.CALL_NATIVE_TOOL,
            target = "Phone workspace",
            risk = AgentRisk.MEDIUM,
            status = AgentActionStatus.RUNNING,
            description = "Clone the project",
            parameters = mapOf("tool_id" to AgentMobileProjectNativeTools.CLONE),
            requiresConfirmation = false
        )
        val plan = projectPlan(running)
        val result = AgentActionResult(
            actionId = running.id,
            success = true,
            message = "Repository cloned",
            metadata = mapOf(
                "native_tool_status" to AgentNativeToolResultStatus.SUCCEEDED.wireValue,
                "invocation_id" to "invocation-1",
                "native_tool_output" to "{\"branch\":\"main\"}"
            )
        )

        assertEquals(running, AgentInterruptedDispatchRecoveryPolicy.completedAction(plan, result))
        assertTrue(
            AgentInterruptedWorkspaceRecoveryPolicy.shouldResume(
                AgentWorkspaceStatus.FAILED,
                AgentPhase.PAUSED,
                plan,
                result
            )
        )
    }

    @Test
    fun incompleteOrFailedNativeDispatchIsNeverAcceptedAsVerifiedRecovery() {
        val running = AgentAction(
            id = "write-project",
            kind = AgentActionKind.CALL_NATIVE_TOOL,
            target = "Phone workspace",
            risk = AgentRisk.MEDIUM,
            status = AgentActionStatus.RUNNING,
            description = "Write a project file",
            requiresConfirmation = false
        )
        val plan = projectPlan(running)
        val missingReceipt = AgentActionResult(
            actionId = running.id,
            success = true,
            message = "Write returned",
            metadata = mapOf("native_tool_status" to AgentNativeToolResultStatus.SUCCEEDED.wireValue)
        )
        val failed = missingReceipt.copy(
            success = false,
            metadata = mapOf(
                "native_tool_status" to AgentNativeToolResultStatus.FAILED.wireValue,
                "invocation_id" to "invocation-2"
            )
        )

        assertEquals(null, AgentInterruptedDispatchRecoveryPolicy.completedAction(plan, missingReceipt))
        assertEquals(null, AgentInterruptedDispatchRecoveryPolicy.completedAction(plan, failed))
        assertFalse(
            AgentInterruptedWorkspaceRecoveryPolicy.shouldResume(
                AgentWorkspaceStatus.FAILED,
                AgentPhase.PAUSED,
                plan,
                failed
            )
        )
    }

    private fun projectPlan(action: AgentAction) = AgentPlan(
        goal = "Improve SignalASI",
        screen = ScreenContext(foregroundApp = "com.signalasi.chat", pageTitle = "SignalASI"),
        steps = emptyList(),
        actions = listOf(action),
        plannerProfile = PHONE_SUPERVISED_PROJECT_PLANNER_PROFILE
    )
}

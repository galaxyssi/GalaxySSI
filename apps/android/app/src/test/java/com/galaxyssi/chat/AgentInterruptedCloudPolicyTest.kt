package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class AgentInterruptedCloudPolicyTest {
    private val screen = ScreenContext("GalaxySSI", pageTitle = "Test")
    private val action = AgentAction("cloud", AgentActionKind.CALL_CONNECTOR, "DeepSeek", AgentRisk.LOW,
        AgentActionStatus.WAITING_RESPONSE, "Request", parameters = mapOf("connector_adapter_type" to "cloud-model-api"))
    private fun session() = AgentSessionSnapshot("session", AgentPhase.WAITING_RESPONSE, "Question", screen,
        AgentPlan("Question", screen, emptyList(), listOf(action)), emptyList(),
        AgentActionResult("agent-interrupted", false, "Process ended"), processInstanceId = "old", updatedAtMillis = 100)

    @Test fun oldCloudWaitWithLostReceiptIsNotARunningRequest() {
        assertEquals(action, AgentInterruptedCloudPolicy.pending(session(), "new", false))
        val stopped = AgentInterruptedCloudPolicy.finish(session(), action, "new", 200, "Cloud request interrupted")
        assertEquals(AgentPhase.FAILED, stopped.phase)
        assertEquals("false", stopped.lastActionResult?.metadata?.get("awaiting_response"))
        assertEquals("true", stopped.lastActionResult?.metadata?.get("non_retriable"))
        assertEquals(AgentActionStatus.FAILED, stopped.currentPlan?.actions?.single()?.status)
    }

    @Test fun activeRequestAndDesktopWaitAreNotFailed() {
        assertNull(AgentInterruptedCloudPolicy.pending(session(), "new", true))
        val desktop = action.copy(parameters = mapOf("connector_adapter_type" to "desktop-codex"))
        assertNull(AgentInterruptedCloudPolicy.pending(session().copy(currentPlan = session().currentPlan!!.copy(
            actions = listOf(desktop))), "new", false))
    }

    @Test fun userPauseAndCompletedResponseArePreserved() {
        assertNull(AgentInterruptedCloudPolicy.pending(session().copy(lastActionResult =
            AgentActionResult("agent-paused", true, "Paused")), "new", false))
        assertNull(AgentInterruptedCloudPolicy.pending(session().copy(phase = AgentPhase.COMPLETED), "new", false))
    }

    @Test fun coldBootKeepsDurableRemoteDispatchIdentity() {
        val receipt = AgentActionResult(action.id, true, "Waiting", mapOf("awaiting_response" to "true",
            "source_message_id" to "123", "contact_id" to "cloud:test", "resource_location" to "cloud"))
        val original = session().copy(lastActionResult = receipt)
        assertNotNull(AgentInterruptedCloudPolicy.pending(original, "new", false))
        val waiting = AgentColdBootRecoveryPolicy.pauseSession(original, "new", 200, "Restarted")
        assertEquals(receipt, waiting.lastActionResult)
        assertEquals(AgentPhase.WAITING_RESPONSE, waiting.phase)
        assertEquals(AgentActionStatus.WAITING_RESPONSE, waiting.currentPlan?.actions?.single()?.status)
        assertNull(AgentInterruptedCloudPolicy.pending(waiting, "new", false))
        val dispatchCommit = session().copy(currentPlan = session().currentPlan!!.copy(
            actions = listOf(action.copy(status = AgentActionStatus.RUNNING, evidence = AGENT_NODE_OBSERVATION_PENDING))),
            lastActionResult = receipt)
        assertNotNull(AgentInterruptedCloudPolicy.pending(dispatchCommit, "new", false))
        val recovered = AgentColdBootRecoveryPolicy.pauseSession(dispatchCommit, "new", 200, "Restarted")
        assertEquals(receipt, recovered.lastActionResult)
        assertEquals(AgentPhase.WAITING_RESPONSE, recovered.phase)
        assertEquals(AgentActionStatus.WAITING_RESPONSE, recovered.currentPlan?.actions?.single()?.status)
        assertNull(AgentInterruptedCloudPolicy.pending(recovered, "new", false))
    }

    @Test fun startupFailsLostHttpBeforeStampingTheCurrentProcess() {
        var saved = session().copy(lastActionResult = AgentActionResult(action.id, true, "Waiting",
            mapOf("awaiting_response" to "true", "source_message_id" to "123", "contact_id" to "cloud:test")))
        var failed = 0
        val sequence = AgentStartupRecoverySequence(
            reconcileCloud = {
                AgentInterruptedCloudPolicy.pending(saved, "new", false)?.let {
                    if (saved.phase != AgentPhase.FAILED) {
                        saved = AgentInterruptedCloudPolicy.finish(saved, it, "new", 200, "Interrupted")
                        failed++
                    }
                }
            },
            reconcile = {
                if (AgentColdBootRecoveryPolicy.belongsToPreviousProcess(saved, "new")) {
                    saved = AgentColdBootRecoveryPolicy.pauseSession(saved, "new", 200, "Restarted")
                }
            },
            dispatch = {
                assertEquals(AgentPhase.FAILED, saved.phase)
                assertEquals("123", saved.lastActionResult?.metadata?.get("source_message_id"))
                assertEquals("false", saved.lastActionResult?.metadata?.get("awaiting_response"))
            })
        sequence.run(); sequence.run()
        assertEquals(1, failed)
    }

    @Test fun committedCloudReplyRemainsAdmissibleAfterStartup() {
        var saved = session().copy(lastActionResult = AgentActionResult(action.id, true, "Waiting",
            mapOf("awaiting_response" to "true", "source_message_id" to "123", "contact_id" to "cloud:test")))
        var checkedInbox = false
        AgentStartupRecoverySequence(
            reconcileCloud = {
                assertNotNull(AgentInterruptedCloudPolicy.pending(saved, "new", false))
                checkedInbox = true // Production recovery preserves an already committed inbox response.
            },
            reconcile = {
                assertTrue(checkedInbox)
                saved = AgentColdBootRecoveryPolicy.pauseSession(saved, "new", 200, "Restarted")
            },
            dispatch = {
                assertEquals(AgentPhase.WAITING_RESPONSE, saved.phase)
                assertTrue(AgentConnectorReceiptAdmission.saved(saved, 123, "cloud:test", "", "", ""))
            }).run()
    }

    @Test fun recoveryMarkerSurvivesAFullCheckpointHistory() {
        val workspace = AgentWorkspace("workspace", "session", "conversation", "turn", eventSequence = 100,
            checkpoints = (1..AgentWorkspaceLimits.MAX_CHECKPOINTS).map {
                AgentWorkspaceCheckpoint("checkpoint-$it", eventSequence = it.toLong(), createdAtMillis = it.toLong())
            })
        val marker = AgentInterruptedCloudRecovery.checkpoint(workspace, 200)
        val normalized = AgentWorkspaceBounds.normalizeOrNull(workspace.copy(checkpoints = workspace.checkpoints + marker))
        assertTrue(normalized!!.checkpoints.contains(marker))
        assertEquals(AgentWorkspaceLimits.MAX_CHECKPOINTS, normalized.checkpoints.size)
    }

    @Test fun anOldProjectionMarkerCannotHideAReintroducedOrphanWait() {
        val workspace = AgentWorkspace("workspace", "session", "conversation", "turn")
        val projected = workspace.copy(checkpoints = listOf(AgentInterruptedCloudRecovery.checkpoint(workspace, 200)))
        val stopped = AgentInterruptedCloudPolicy.finish(session(), action, "new", 200, "Interrupted")
        assertTrue(AgentInterruptedCloudRecovery.alreadyProjected(projected, stopped))
        val restored = session().copy(phase = AgentPhase.PAUSED)
        assertFalse(AgentInterruptedCloudRecovery.alreadyProjected(projected, restored))
        assertNotNull(AgentInterruptedCloudPolicy.pending(restored, "new", false))
        assertNull(AgentInterruptedCloudPolicy.pending(restored, "new", true))
    }
}

package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class AgentRecoveryTranscriptTest {
    private val workspace = AgentWorkspace("workspace", "workspace-session", "conversation", "turn",
        status = AgentWorkspaceStatus.PAUSED)
    private val screen = ScreenContext("test", pageTitle = "test")
    private fun session(phase: AgentPhase = AgentPhase.COMPLETED) = AgentSessionSnapshot(
        "runtime-session", phase, "Goal", screen, null, emptyList(), AgentActionResult("result", true, "Answer"),
        executionLoopSnapshot = AgentExecutionLoop.create().start("turn", AgentExecutionLoopBudget()).snapshot,
        updatedAtMillis = 21L)

    @Test fun completedSessionRecoversTheProjectionGapWithoutRequiringEqualSessionAndTurnIds() {
        assertEquals(AgentLongTaskRecoveryMode.TRANSCRIPT_PROJECTION,
            AgentLongTaskRecoveryPolicy.decide(workspace, session())?.mode)
    }

    @Test fun failedAndCancelledSessionResultsCanAlsoBeCommitted() {
        listOf(AgentPhase.FAILED, AgentPhase.CANCELLED).forEach {
            assertTrue(AgentRecoveryTranscript.needsProjection(workspace, session(it)))
        }
    }

    @Test fun finishedCancelledAndActivelyOwnedWorkspacesCannotBeReclaimed() {
        AgentWorkspaceStatus.entries.filter { it.isTerminal }.forEach {
            assertFalse(AgentRecoveryTranscript.needsProjection(workspace.copy(status = it), session()))
        }
        assertFalse(AgentRecoveryTranscript.needsProjection(workspace.copy(cancellationRequested = true), session()))
        assertNull(AgentLongTaskRecoveryPolicy.decide(workspace, session(), setOf(workspace.workspaceId)))
    }

    @Test fun terminalResultFromAnotherTaskCannotBeProjected() {
        assertFalse(AgentRecoveryTranscript.needsProjection(workspace.copy(taskId = "other"), session()))
        assertFalse(AgentRecoveryTranscript.needsProjection(workspace, session().copy(executionLoopSnapshot = null)))
    }

    @Test fun waitingResultRequiresAnExactPendingCheckpoint() {
        val saved = session(AgentPhase.WAITING_CONFIRMATION)
        val checkpoint = AgentWorkspaceCheckpoint(AgentRecoveryTranscript.CHECKPOINT_ID,
            stateJson = AgentRecoveryTranscript.pendingCheckpoint(workspace, saved))
        val pending = workspace.copy(checkpoints = listOf(checkpoint))
        assertFalse(AgentRecoveryTranscript.needsProjection(workspace, saved))
        assertTrue(AgentRecoveryTranscript.needsProjection(pending, saved))
        assertFalse(AgentRecoveryTranscript.needsProjection(pending.copy(conversationId = "other"), saved))
        assertFalse(AgentRecoveryTranscript.needsProjection(pending, saved.copy(sessionId = "other")))
        assertFalse(AgentRecoveryTranscript.needsProjection(pending, saved.copy(updatedAtMillis = 22L)))
        assertFalse(AgentRecoveryTranscript.needsProjection(pending, saved.copy(phase = AgentPhase.WAITING_RESPONSE)))
        assertFalse(AgentRecoveryTranscript.needsProjection(pending,
            saved.copy(executionLoopSnapshot = saved.executionLoopSnapshot!!.copy(revision = 100L))))
    }

    @Test fun malformedAndAcknowledgedCheckpointsDoNotRescheduleWaitingResults() {
        listOf("invalid", "{}", "{\"pending\":false}").forEach {
            assertFalse(AgentRecoveryTranscript.needsProjection(workspace.copy(checkpoints = listOf(
                AgentWorkspaceCheckpoint(AgentRecoveryTranscript.CHECKPOINT_ID, stateJson = it))),
                session(AgentPhase.WAITING_RESPONSE)))
        }
    }

    @Test fun commitOrdersProjectionBeforeTerminalSnapshotAndAcknowledgement() {
        val order = mutableListOf<String>()
        AgentRecoveryTranscript.commit({ order += "transcript" }, { order += "workspace" }, { order += "ack" })
        assertEquals(listOf("transcript", "workspace", "ack"), order)
    }

    @Test fun failedProjectionCannotFinishTheWorkspace() {
        val order = mutableListOf<String>()
        assertThrows(IllegalStateException::class.java) {
            AgentRecoveryTranscript.commit({ error("disk") }, { order += "workspace" }, { order += "ack" })
        }
        assertTrue(order.isEmpty())
    }

    @Test fun failedWorkspaceWriteCannotAcknowledgeProjection() {
        var acknowledged = false
        assertThrows(IllegalStateException::class.java) {
            AgentRecoveryTranscript.commit({}, { error("disk") }, { acknowledged = true })
        }
        assertFalse(acknowledged)
    }

    @Test fun displayAdapterPreservesArtifactsAndApprovalWithoutBuildingARuntime() {
        val action = AgentAction("approve", AgentActionKind.DELETE_TEXT, "text", AgentRisk.HIGH,
            AgentActionStatus.PENDING_CONFIRMATION, "Delete text")
        val saved = session(AgentPhase.WAITING_CONFIRMATION).copy(
            currentPlan = AgentPlan("Goal", screen, emptyList(), listOf(action), artifactRichOutputJson = "fixture"))
        val state = AgentRecoveryTranscript.state(saved)
        assertEquals(saved.phase, state.phase)
        assertEquals(saved.lastActionResult, state.lastActionResult)
        assertEquals(action, state.pendingAction)
        assertEquals("fixture", state.plan!!.artifactRichOutputJson)
        assertEquals(saved.executionLoopSnapshot, state.executionLoop)
        assertTrue(state.runtimeContext.nativeTools.isEmpty())
    }
}

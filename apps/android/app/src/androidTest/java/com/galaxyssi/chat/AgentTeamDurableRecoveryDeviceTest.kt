package com.galaxyssi.chat

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Isolated fixtures only. No connector requests, contacts, or existing task data are cleared. */
@RunWith(AndroidJUnit4::class)
class AgentTeamDurableRecoveryDeviceTest {
    private val context get() = ApplicationProvider.getApplicationContext<Context>()

    @Test fun encryptedCheckpointResumesOnlyRemainingWork() = runBlocking {
        val id = "durable-recovery-${UUID.randomUUID()}"
        val request = AgentRunRequest(conversationId = id, messageId = id, taskId = id, runId = id,
            goal = "Recovery fixture", idempotencyKey = id)
        val definition = AgentTeamDefinition(teamId = id, primaryAgentId = "lead", members = listOf(
            AgentTeamMember("observer", AgentDeliveryMode.OBSERVE), AgentTeamMember("lead", AgentDeliveryMode.RESPOND)))
        val store = EncryptedAgentTeamExecutionStore(context)
        store.create(definition, request)
        store.append(AgentSubagentEvent(1L, id, "observer", AgentSubagentEventKinds.CHILD_SUCCEEDED,
            childStatus = AgentSubagentStatus.SUCCEEDED, result = AgentSubagentChildResult(id, "observer", id,
                1, AgentSubagentStatus.SUCCEEDED, output = "saved evidence", startedAtMillis = 1, completedAtMillis = 2)))
        store.markInterrupted(id)
        val recreated = EncryptedAgentTeamExecutionStore(context)
        val runtime = AgentTeamExecutionRuntime(recreated)
        try {
            val invoked = mutableListOf<String>()
            val result = withTimeout(10_000) { runtime.resume(requireNotNull(recreated.resumeCheckpoint(id))) {
                invoked += it.member.memberId
                assertEquals("saved evidence", it.handoff.dependencies.single().output)
                AgentSubagentOutput("final fixture result")
            }.await() }
            assertEquals(listOf("lead"), invoked)
            assertEquals(AgentTeamExecutionState.SUCCEEDED, result.snapshot.state)
            assertEquals("saved evidence", result.snapshot.members.first { it.memberId == "observer" }.output)
        } finally { runtime.close(); store.remove(id) }
    }

    @Test fun explicitPauseAndStopSurviveStoreRecreation() = runBlocking {
        val id = "control-recovery-${UUID.randomUUID()}"
        val store = AgentTeamDurableControl(context)
        try {
            store.set(id, AgentTeamUserControl.PAUSE)
            assertEquals(AgentTeamUserControl.PAUSE, AgentTeamDurableControl(context).get(id))
            store.set(id, AgentTeamUserControl.RUN)
            withTimeout(1000) { AgentTeamDurableControl(context).awaitDispatch(id) }
            store.set(id, AgentTeamUserControl.STOP)
            assertEquals(AgentTeamUserControl.STOP, AgentTeamDurableControl(context).get(id))
            var cancelled = false
            try { store.awaitDispatch(id) } catch (_: kotlinx.coroutines.CancellationException) { cancelled = true }
            assertTrue(cancelled)
        } finally { store.remove(id) }
    }

    @Test fun dispatchBoundarySurvivesStoreRecreation() {
        val id = "dispatch-recovery-${UUID.randomUUID()}"
        val store = AgentTeamDispatchCheckpoint(context)
        try {
            store.begin(id)
            assertTrue(AgentTeamDispatchCheckpoint(context).wasNotDispatched(id))
            store.dispatching(id)
            assertFalse(AgentTeamDispatchCheckpoint(context).wasNotDispatched(id))
            var rejected = false
            try { store.begin(id) } catch (_: IllegalStateException) { rejected = true }
            assertTrue(rejected)
        } finally { store.remove(id) }
    }

    @Test fun exactFalseSilenceFailureIsRepairedWithoutRerunningTeam() {
        val id = "parent-recovery-${UUID.randomUUID()}"
        val transcript = AgentTranscriptStore(context)
        val conversation = transcript.createAgentConversation("Recovery fixture")
        val workspaceStore = EncryptedAgentWorkspaceStore(context)
        val source = AgentTeamDispatchIds.sourceMessageId(id)
        val contact = AgentTeamDispatchIds.responseContactId(id)
        val reason = context.getString(R.string.agent_desktop_status_unavailable)
        val team = AgentTeamExecutionSnapshot(id, id, conversation.id, id, "lead", "Fixture",
            AgentTeamVisibilityMode.VISIBLE, AgentTeamExecutionState.SUCCEEDED, emptyList(), "Saved final",
            createdAtMillis = System.currentTimeMillis() - 1000)
        val delivery = AgentPendingDelivery(source, conversation.id, id, id, contact)
        try {
            workspaceStore.upsert(AgentWorkspace(id, "task:$id", conversation.id, id,
                status = AgentWorkspaceStatus.FAILED, errorMessage = reason))
            SharedPreferencesAgentSessionStore(context, "task:$id").save(AgentSessionSnapshot("fixture", AgentPhase.WAITING_RESPONSE,
                "Fixture", ScreenContext("fixture", pageTitle = "fixture"), null, emptyList(),
                AgentActionResult("fixture", true, "Waiting", mapOf("resource_location" to "distributed", "team_run_id" to id,
                    "source_message_id" to source.toString(), "contact_id" to contact)), updatedAtMillis = System.currentTimeMillis()))
            AgentTerminalDeliveryStore.mark(context, delivery, reason)
            assertTrue(AgentTeamParentDeliveryRecovery(context).prepare(team))
            assertNull(AgentTerminalDeliveryStore.find(context, source))
            assertEquals(AgentWorkspaceStatus.WAITING_RESPONSE, workspaceStore.find(id)?.status)
            assertTrue(AgentTeamParentDeliveryRecovery(context).prepare(team))
        } finally {
            AgentTerminalDeliveryStore.find(context, source)?.let { AgentTerminalDeliveryStore.removeExact(context, it) }
            AgentPendingDeliveryStore.remove(context, source)
            SharedPreferencesAgentSessionStore(context, "task:$id").clear()
            workspaceStore.delete(id)
            transcript.deleteConversation(conversation.id)
        }
    }

    @Test fun repairSelectedCompletedTeamWithoutExecutingModels() {
        val runId = InstrumentationRegistry.getArguments().getString("selected_team_run").orEmpty()
        assumeTrue("Explicit diagnostic selection required", runId.isNotBlank())
        val team = requireNotNull(EncryptedAgentTeamExecutionStore(context).snapshot(runId))
        assertTrue(team.state in setOf(AgentTeamExecutionState.SUCCEEDED, AgentTeamExecutionState.COMPLETED_WITH_FAILURES))
        assertTrue(team.finalOutput.isNotBlank())
        val before = team.members.map { it.memberId to it.completedAtMillis }
        AgentConnectorTeamCompletionSink(context).publish(team)
        val deadline = android.os.SystemClock.elapsedRealtime() + 60_000
        while (android.os.SystemClock.elapsedRealtime() < deadline && !AgentTeamParentDeliveryRecovery(context).committed(team)) {
            android.os.SystemClock.sleep(500)
        }
        assertTrue("Canonical final response must be committed", AgentTeamParentDeliveryRecovery(context).committed(team))
        assertEquals(AgentWorkspaceStatus.COMPLETED, EncryptedAgentWorkspaceStore(context).find(team.taskId)?.status)
        assertEquals(before, EncryptedAgentTeamExecutionStore(context).snapshot(runId)?.members?.map { it.memberId to it.completedAtMillis })
    }
}

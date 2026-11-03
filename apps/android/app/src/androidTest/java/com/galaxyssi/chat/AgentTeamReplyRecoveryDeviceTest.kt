package com.galaxyssi.chat

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.util.UUID
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** Isolated encrypted fixtures; no re-pairing, history clearing, or provider execution. */
@RunWith(AndroidJUnit4::class)
class AgentTeamReplyRecoveryDeviceTest {
    private val context get() = ApplicationProvider.getApplicationContext<Context>()

    @Test fun missingReceiveIntentSurvivesStoreRecreationAndResumesOnlySuccessor() = runBlocking {
        val id = "reply-recovery-${UUID.randomUUID()}"
        val request = AgentRunRequest(id, id, id, id, goal = "Recovery fixture", idempotencyKey = id)
        val definition = AgentTeamDefinition(id, "lead", listOf(
            AgentTeamMember("codex", AgentDeliveryMode.OBSERVE, instanceId = "observer"),
            AgentTeamMember("lead", AgentDeliveryMode.RESPOND, dependsOnAgentIds = setOf("observer"))))
        val owner = stableAgentTeamMemberRunId(id, "observer")
        val source = AgentTeamDispatchIds.sourceMessageId("member:$id:observer")
        val store = EncryptedAgentTeamExecutionStore(context)
        val ledger = EncryptedAgentManagedResponseLedger(context)
        store.create(definition, request)
        store.append(AgentSubagentEvent(1, id, "observer", AgentSubagentEventKinds.CHILD_RUNNING,
            childStatus = AgentSubagentStatus.RUNNING))
        AgentTeamDispatchCheckpoint(context).dispatching(owner)
        store.markInterrupted(id)
        val recreated = EncryptedAgentTeamExecutionStore(context)
        val runtime = AgentTeamExecutionRuntime(recreated)
        try {
            val team = requireNotNull(recreated.snapshot(id))
            val checkpoint = requireNotNull(recreated.deliveryCheckpoint(id))
            val wire = AgentPendingDelivery(source, id, id, "wire-$id", "fixture-contact")
            assertNull(ledger.findOwner(owner))
            assertEquals(1, AgentTeamReplyRecovery.restore(team, checkpoint, ledger, AgentTeamUserControl.RUN,
                AgentTeamDispatchCheckpoint(context)::wasNotDispatched) { _, _ -> wire })
            val response = AgentConnectorResponse(source, wire.contactId, "durable original result",
                conversationId = id, turnId = id, taskId = wire.taskId)
            // Commit without emitting a live-controller wake for this isolated fixture.
            EncryptedAgentManagedResponseLedger(context).acknowledge(response)
            // Simulate the late dispatch receipt arriving after the result, then another process recreation.
            ledger.register(requireNotNull(ledger.findOwner(owner)).copy(state = AgentManagedResponseState.PENDING, response = null))
            val received = requireNotNull(EncryptedAgentManagedResponseLedger(context).findOwner(owner))
            assertEquals(AgentManagedResponseState.COMPLETED, received.state)
            assertTrue(recreated.applyLateResponse(received))
            assertTrue(recreated.applyLateResponse(received))
            ledger.markApplied(owner)
            val invoked = mutableListOf<String>()
            val result = withTimeout(10_000) { runtime.resume(requireNotNull(recreated.resumeCheckpoint(id))) {
                invoked += it.member.memberId
                assertEquals("durable original result", it.handoff.dependencies.single().output)
                AgentSubagentOutput("final fixture")
            }.await() }
            assertEquals(listOf("lead"), invoked)
            assertEquals(AgentTeamExecutionState.SUCCEEDED, result.snapshot.state)
            assertEquals(AgentManagedResponseState.APPLIED, EncryptedAgentManagedResponseLedger(context).findOwner(owner)?.state)
        } finally {
            runtime.close()
            ledger.removeOwner(owner)
            AgentTeamDispatchCheckpoint(context).remove(owner)
            store.remove(id)
        }
    }

    @Test fun completedFollowupsNeverEvictOrMaskInterruptedResearchProjection() {
        val id = "header-recovery-${UUID.randomUUID()}"
        fun snapshot(run: String, state: AgentTeamExecutionState, at: Long, research: Boolean) =
            AgentTeamExecutionSnapshot(run, id, id, run, "fixture", "Fixture", AgentTeamVisibilityMode.VISIBLE, state,
                listOf(AgentTeamMemberSnapshot("fixture", "Research", AgentDeliveryMode.RESPOND,
                    AgentSubagentStatus.RUNNING, collaborationGroupId = id, researchStage = if (research) "EXPLORE" else "")),
                createdAtMillis = at, updatedAtMillis = at)
        val original = snapshot(id, AgentTeamExecutionState.INTERRUPTED, 1, true)
        try {
            CollaborationCurrentStateStore.publish(context, original)
            repeat(70) { index -> CollaborationCurrentStateStore.publish(context,
                snapshot("$id-followup-$index", AgentTeamExecutionState.SUCCEEDED, 2L + index, false)) }
            assertEquals(id, CollaborationCurrentStateStore.latest(id)?.supervisorRunId)
            assertEquals(id, CollaborationCurrentStateStore.entries(id).single().let {
                CollaborationTranscriptMetadata.decode(it.collaborationJson)?.runId
            })
            assertEquals(ConversationHubAgentStatus.RECONNECTING, CollaborationCurrentStateStore.status(original))
        } finally {
            // Retire this fixture only; production projections and encrypted user data are left intact.
            CollaborationCurrentStateStore.publish(context, original.copy(state = AgentTeamExecutionState.SUCCEEDED,
                updatedAtMillis = System.currentTimeMillis()))
        }
    }
}

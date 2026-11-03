package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AgentCloudWatchdogIsolationDeviceTest {
    @Test fun cloudReplySurvivesStaleDesktopProbesAndRetainsItsExactBinding() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val transcripts = AgentTranscriptStore(context)
        val conversation = transcripts.createAgentConversation("Cloud watchdog isolation test").id
        val turn = UUID.randomUUID().toString()
        val source = ChatHistoryStore.reserveMessageId(context)
        // No provider-name heuristic: any cloud API contact must be isolated.
        val contact = "watchdog-test-${UUID.randomUUID()}"
        val delivery = AgentPendingDelivery(source, conversation, turn, turn, contact)
        val sessions = SharedPreferencesAgentSessionStore(context, "task:$turn")
        val workspaces = EncryptedAgentWorkspaceStore(context)
        val claim = checkNotNull(AgentLongTaskRecoveryClaims.tryAcquire(turn))
        try {
            val screen = ScreenContext("GalaxySSI", pageTitle = "Cloud watchdog test")
            val action = AgentAction("cloud-test", AgentActionKind.CALL_CONNECTOR, "Cloud API", AgentRisk.LOW,
                AgentActionStatus.WAITING_RESPONSE, "Test cloud dispatch")
            val result = AgentActionResult(action.id, true, "Waiting", mapOf(
                "source_message_id" to source.toString(), "contact_id" to contact,
                "conversation_id" to conversation, "turn_id" to turn, "task_id" to turn,
                "resource_location" to "cloud", "connector_adapter_type" to "cloud-model-api",
                "resource_started_at" to "1000", "awaiting_response" to "true"))
            workspaces.upsert(AgentWorkspace(turn, turn, conversation, turn,
                status = AgentWorkspaceStatus.WAITING_RESPONSE))
            sessions.save(AgentSessionSnapshot(turn, AgentPhase.WAITING_RESPONSE, "Cloud watchdog test", screen,
                AgentPlan("Cloud watchdog test", screen, emptyList(), listOf(action)), emptyList(), result,
                processInstanceId = AgentProcessIdentity.instanceId, updatedAtMillis = System.currentTimeMillis()))
            AgentPendingDeliveryStore.put(context, delivery)
            listOf(1_000L, 31_000L, 61_000L, 181_000L).forEach {
                AndroidAgentRemoteSilence.shouldProbe(context, source, it)
            }
            assertTrue(AndroidAgentRemoteSilence.expired(context, source, emptyMap(), 181_000L))
            assertFalse(AndroidAgentRemoteSilence.inspectDelivery(context, delivery, 181_000L))
            assertEquals(delivery, AgentPendingDeliveryStore.find(context, source))
            assertEquals(AgentWorkspaceStatus.WAITING_RESPONSE, workspaces.find(turn)?.status)
            assertEquals(result, sessions.load()?.lastActionResult)
            assertFalse(AgentTerminalDeliveryStore.isTerminal(context, source))
            assertFalse(AndroidAgentRemoteSilence.expired(context, source, emptyMap(), 181_000L))
            assertTrue(transcripts.page(conversation, pageSize = 20).entries.isEmpty())

            // A recovered session may be absent; an unknown pending receipt is still not Desktop work.
            sessions.clear()
            assertFalse(AndroidAgentRemoteSilence.inspectDelivery(context, delivery, 400_000L))
            assertEquals(delivery, AgentPendingDeliveryStore.find(context, source))
        } finally {
            AgentTerminalDeliveryStore.find(context, source)?.let { AgentTerminalDeliveryStore.removeExact(context, it) }
            AgentPendingDeliveryStore.remove(context, source)
            sessions.clear()
            workspaces.delete(turn)
            transcripts.deleteConversation(conversation)
            claim.close()
        }
    }
}
